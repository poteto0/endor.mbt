///|
/// How an HTTP JSON-RPC request leaves the process: one POST of a JSON body,
/// answered by the response body as text.
///
/// The transport owns the endpoint URL and any headers it needs (an API key, a
/// bearer token), which is what keeps `HttpProvider` free of every difference
/// between one HTTP client and the next: `fetch` in a browser, a Node agent, a
/// native client. It POSTs `body` with `content-type: application/json` and
/// answers with the raw response body — the JSON-RPC envelope is parsed above,
/// not here.
///
/// A network failure or a non-2xx status raises
/// `@provider.ProviderError::internal(...)` with a message naming what
/// happened (the status and the URL, say): the transport reports *transport*
/// failures, and a JSON-RPC `error` object is not one of them — that is a
/// well-formed answer, and `HttpProvider` maps it.
///
/// ```
/// struct AlwaysEmpty {}
///
/// impl @http.HttpTransport for AlwaysEmpty with fn post(_, _) {
///   "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"0x1\"}"
/// }
/// ```
pub(open) trait HttpTransport {
  /// POST `body` as `application/json`, answering with the response body text.
  async fn post(Self, body : String) -> String raise @provider.ProviderError
}

///|
/// A `Provider` that speaks JSON-RPC over HTTP, so the read layer works with
/// no browser wallet in sight: a node URL is enough.
///
/// Ids are assigned per provider instance, starting at 1 and incrementing with
/// each request, and the id a response carries is checked against the one that
/// was sent.
///
/// It deliberately does **not** implement `EventSource`. Plain HTTP pushes
/// nothing: there is no `accountsChanged` and no `chainChanged` behind a POST
/// endpoint, and that is exactly why `EventSource` is a trait of its own —
/// a transport can answer RPC without being able to push anything back.
///
/// ```
/// async fn[T : @http.HttpTransport] chain(
///   transport : T,
/// ) -> @endor.ChainId raise @provider.ProviderError {
///   @provider.chain_id(@http.HttpProvider::new(transport))
/// }
/// ```
pub struct HttpProvider[T] {
  priv transport : T
  priv mut next_id : Int
}

///|
/// Build a provider over `transport`. Ids start at 1.
pub fn[T] HttpProvider::new(transport : T) -> HttpProvider[T] {
  HttpProvider::{ transport, next_id: 1 }
}

///|
/// The methods HTTP structurally cannot serve: they need a wallet UI — a
/// prompt, a chain switch — and there is nothing behind an HTTP endpoint to
/// prompt.
///
/// Deliberately short. `eth_sendTransaction`, `eth_accounts`, `personal_sign`
/// and `eth_signTypedData_v4` are *not* here: a node with unlocked accounts
/// (Anvil, a dev node) really does serve them, so refusing them locally would
/// be a lie. A node that cannot serve a method answers `-32601`, which
/// `ProviderError::from_code` maps already.
fn needs_a_wallet(method_name : String) -> Bool {
  method_name.has_prefix("wallet_") || method_name == "eth_requestAccounts"
}

///|
/// Perform one JSON-RPC call over the transport.
pub impl[T : HttpTransport] @provider.Provider for HttpProvider[T] with fn request(
  self,
  method_name~,
  params~,
) {
  // Before any I/O: what HTTP cannot answer is not worth a round trip.
  if needs_a_wallet(method_name) {
    raise @provider.UnsupportedMethod
  }
  let id = self.next_id
  self.next_id = id + 1
  let payload = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string(method_name),
    "params": params,
  })
  let body = self.transport.post(payload.stringify())
  let parsed = @json.parse(body) catch {
    e =>
      raise @provider.ProviderError::internal(
        "malformed JSON-RPC response: \{e}",
      )
  }
  guard parsed is Object(fields) else {
    raise @provider.ProviderError::internal(
      "JSON-RPC response is not an object: \{body}",
    )
  }
  check_id(fields, id)
  if fields.get("error") is Some(error) && !(error is Null) {
    raise @provider.ProviderError::from_error_object(error)
  }
  // `null` is a legitimate result — a receipt for a transaction that has not
  // been mined — so absence is the missing *key*, not the null value.
  guard fields.get("result") is Some(result) else {
    raise @provider.ProviderError::internal(
      "JSON-RPC response carries neither result nor error: \{body}",
    )
  }
  result
}

///|
/// Check the id a response carries against the one that was sent. An absent id
/// is accepted — some nodes omit it when they answer an error — so only a
/// *present and different* one is a mismatch.
fn check_id(
  fields : Map[String, Json],
  sent : Int,
) -> Unit raise @provider.ProviderError {
  match fields.get("id") {
    None | Some(Null) => ()
    Some(Number(got, ..)) if got.to_int() == sent => ()
    Some(other) =>
      raise @provider.ProviderError::internal(
        "JSON-RPC id mismatch: sent \{sent}, got \{other.stringify()}",
      )
  }
}
