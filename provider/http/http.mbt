///|
/// How an HTTP JSON-RPC request leaves the process: one POST of a JSON body,
/// answered by the response body as text.
///
/// `Endpoint` is the implementation almost everyone wants, and it is portable,
/// so this trait is not what makes the SDK work off the browser — it is the
/// seam for a caller whose HTTP is its own: a client with retries or a
/// connection pool, an authenticating proxy, a recorded fixture in a test. It
/// POSTs `body` with `content-type: application/json` and answers with the raw
/// response body — the JSON-RPC envelope is parsed above, not here.
///
/// A network failure raises `@provider.Transport` and a non-2xx status
/// `@provider.HttpStatus`: the transport reports *transport* failures, and a
/// JSON-RPC `error` object is not one of them — that is a well-formed answer,
/// and `HttpProvider` maps it.
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
/// async fn chain(
///   url : String,
/// ) -> @endor.ChainId raise @provider.ProviderError {
///   @provider.chain_id(@endpoint.at(url))
/// }
/// ```
pub struct HttpProvider[T] {
  priv transport : T
  priv mut next_id : Int
  priv retry : @provider.RetryPolicy
  priv batch : Window?
}

///|
/// Build a provider over `transport`. Ids start at 1, retries are the default
/// policy, and calls are not batched.
pub fn[T] HttpProvider::new(transport : T) -> HttpProvider[T] {
  HttpProvider::{
    transport,
    next_id: 1,
    retry: @provider.RetryPolicy::default(),
    batch: None,
  }
}

///|
/// The same provider, retrying on `policy`. The copy gets an id counter and a
/// batch window of its own — ids only have to be unique within one of those,
/// and two providers that retry differently should not share a POST.
pub fn[T] HttpProvider::with_retry(
  self : HttpProvider[T],
  policy : @provider.RetryPolicy,
) -> HttpProvider[T] {
  self.copied(retry=policy, batch=self.batch.map(w => w.policy))
}

///|
/// Every wither goes through here, so "a copy never shares a window" is one
/// function's property rather than a line each of them has to remember. A copy
/// carries the batch *policy* across and nothing else: the calls waiting in the
/// original window belong to the original.
fn[T] HttpProvider::copied(
  self : HttpProvider[T],
  retry~ : @provider.RetryPolicy,
  batch~ : @provider.BatchPolicy?,
) -> HttpProvider[T] {
  { ..self, retry, batch: batch.map(Window::new) }
}

///|
/// The same provider, folding concurrent calls into one JSON-RPC array: calls
/// that start within `policy`'s window leave as a single POST, and each gets
/// its own answer back by id.
///
/// **Off unless you ask for it**, unlike `with_retry`. Retrying costs a caller
/// nothing when nothing fails, but a window costs a lone read the whole `wait`
/// before it is even sent — and whether that trade is right depends on what the
/// endpoint is and what the caller is doing, which only the caller knows. A
/// provider that never sees `with_batch` behaves exactly as it did before this
/// existed.
///
/// The window belongs to **this provider value**, so folding is scoped to it:
/// build it once and share it between the calls that should fold. One built
/// per call folds nothing and pays the whole `wait`.
///
/// ```
/// async fn heights[T : @http.HttpTransport](
///   node : @http.HttpProvider[T],
/// ) -> Array[Result[Json, @provider.ProviderError]] raise @provider.ProviderError {
///   // one provider, so these two land in one window — and one POST
///   @provider.request_many(node, [
///     @provider.BatchCall::new(method_name="eth_chainId", params=Json::array([])),
///     @provider.BatchCall::new(method_name="eth_blockNumber", params=Json::array([])),
///   ])
/// }
/// ```
pub fn[T] HttpProvider::with_batch(
  self : HttpProvider[T],
  policy : @provider.BatchPolicy,
) -> HttpProvider[T] {
  self.copied(retry=self.retry, batch=Some(policy))
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
/// Perform one JSON-RPC call over the transport, retrying the failures that are
/// about this attempt rather than about the request.
///
/// The retry sits here rather than in `HttpTransport`, because a hosted RPC
/// asking for a moment often does it *inside a 200* — `-32005`, or a body
/// carrying `{ code: 429 }` — which `post` cannot see and `send_once` has
/// already turned into a `ProviderError` by the time this reads it.
pub impl[T : HttpTransport] @provider.Provider for HttpProvider[T] with fn request(
  self,
  method_name~,
  params~,
) {
  // Before any I/O: what HTTP cannot answer is not worth a round trip.
  if needs_a_wallet(method_name) {
    raise @provider.UnsupportedMethod
  }
  // The window retries the POST it folds into, so a call that goes in must not
  // also be retried here — and one that must be sent at most once cannot be in
  // an array that a retry resends whole.
  let may_be_resent = !@provider.is_not_idempotent(method_name)
  if self.batch is Some(window) && may_be_resent {
    return self.send_batched(window, method_name~, params~)
  }
  @provider.retry_loop(method_name~, policy=self.retry, () => {
    self.send_once(method_name~, params~)
  })
}

///|
/// One attempt: one id, one POST, one envelope read. Each retry comes back
/// through here and takes a fresh id, which is what the node answers against.
async fn[T : HttpTransport] HttpProvider::send_once(
  self : HttpProvider[T],
  method_name~ : String,
  params~ : Json,
) -> Json raise @provider.ProviderError {
  let id = self.next_id
  self.next_id = id + 1
  let body = self.transport.post(
    envelope(id~, method_name~, params~).stringify(),
  )
  let parsed = @json.parse(body) catch {
    e => raise @provider.MalformedResponse("response is not JSON: \{e}")
  }
  guard parsed is Object(fields) else {
    raise @provider.MalformedResponse(
      "response is not an object: \{@provider.body_preview(body)}",
    )
  }
  check_id(fields, id)
  match read_answer(fields) {
    Ok(result) => result
    Err(e) => raise e
  }
}

///|
/// The request envelope, spelled once: a batched call and a lone one put the
/// same four members on the wire, and only the brackets around them differ.
fn envelope(id~ : Int, method_name~ : String, params~ : Json) -> Json {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string(method_name),
    "params": params,
  })
}

///|
/// Read one JSON-RPC answer object: the node's `error` as an `Err`, its
/// `result` as an `Ok`, and a body that is neither as a raise — an element of a
/// batch and a whole response are the same shape here.
///
/// `null` is a legitimate result — a receipt for a transaction that has not
/// been mined — so absence is the missing *key*, not the null value.
fn read_answer(
  fields : Map[String, Json],
) -> Result[Json, @provider.ProviderError] raise @provider.ProviderError {
  if fields.get("error") is Some(error) && !(error is Null) {
    return Err(@provider.ProviderError::from_error_object(error))
  }
  guard fields.get("result") is Some(result) else {
    raise @provider.MalformedResponse(
      "answer carries neither result nor error: \{@provider.body_preview(Json::object(fields).stringify())}",
    )
  }
  Ok(result)
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
      raise @provider.MalformedResponse(
        "id mismatch: sent \{sent}, got \{@provider.body_preview(other.stringify())}",
      )
  }
}
