///|
/// Opaque handle to the injected `globalThis.ethereum` EIP-1193 provider
/// object. This is the only package that talks to JavaScript directly.
#external
pub type Ethereum

///|
/// `true` when `globalThis.ethereum` is present.
extern "js" fn _has_ethereum() -> Bool =
  #| () => (typeof globalThis.ethereum !== 'undefined' && globalThis.ethereum !== null)

///|
pub fn has_ethereum() -> Bool {
  _has_ethereum()
}

///|
/// Fetch the injected provider object (assumes `js_has_ethereum()` is true).
extern "js" fn _get_ethereum() -> Ethereum =
  #| () => globalThis.ethereum

///|
pub fn get_ethereum() -> Ethereum {
  _get_ethereum()
}

///|
/// `true` when the injected provider identifies itself as MetaMask.
extern "js" fn _is_metamask(eth : Ethereum) -> Bool =
  #| (eth) => !!(eth && eth.isMetaMask)

///|
pub fn is_metamask(eth : Ethereum) -> Bool {
  _is_metamask(eth)
}

///|
/// Call `ethereum.request(payload)` where `payload` is a JSON string of
/// `{ method, params }`. The returned promise **always resolves** to a JSON
/// string envelope so structured error codes survive the boundary:
///
/// - success: `{"ok": <result>}`
/// - failure: `{"err": {"code": <int>, "message": <string>}}`
extern "js" fn _request(
  eth : Ethereum,
  payload_json : String,
) -> @js_async.Promise[String] =
  #| (eth, payload) =>
  #|   eth.request(JSON.parse(payload))
  #|      .then(r => JSON.stringify({ ok: (r === undefined ? null : r) }))
  #|      .catch(e => JSON.stringify({
  #|        err: {
  #|          code: (e && typeof e.code === 'number') ? e.code : -32603,
  #|          message: String((e && e.message) ? e.message : e)
  #|        }
  #|      }))

///|
pub fn request(
  eth : Ethereum,
  payload_json : String,
) -> @js_async.Promise[String] {
  _request(eth, payload_json)
}

///|
pub fn spawn(task : async () -> Unit) -> Unit {
  @js_async.Promise::from_async(task) |> ignore
}

///|
/// Parse the JSON-string envelope returned from the JavaScript boundary.
///
/// The envelope format is:
///
/// - success: `{"ok": <result>}`
/// - failure: `{"err": {"code": <int>, "message": <string>}}`
pub fn decode_envelope(result_json : String) -> Json raise JsError {
  let parsed = @json.parse(result_json) catch {
    e => raise InvalidEnvelope("malformed FFI envelope: \{e}")
  }

  guard parsed is Object(obj) else {
    raise InvalidEnvelope("FFI envelope not an object")
  }

  if obj.get("err") is Some(Object(err_obj)) {
    let code = match err_obj.get("code") {
      Some(Number(c, ..)) => c.to_int()
      _ => -32603
    }

    let message = match err_obj.get("message") {
      Some(String(s)) => s
      _ => ""
    }

    raise RemoteError(code, message)
  }

  guard obj.get("ok") is Some(v) else {
    raise InvalidEnvelope("FFI envelope missing ok/err")
  }

  v
}

///|
/// POST `body` to `url` as `application/json`. Transport and nothing else: the
/// JSON-RPC framing above this is `provider/http`'s business, and what an HTTP
/// status *means* is `@fetch.FetchTransport`'s.
///
/// The returned promise **always resolves**, to the status and the response
/// body separated by one newline:
///
/// ```text
/// 200\n{"jsonrpc":"2.0","id":1,"result":"0x1"}
/// 0\nfailed to fetch
/// ```
///
/// Status `0` is the answer that never came — a refused connection, a DNS
/// failure — and then the rest is the thrown message.
///
/// Deliberately *not* the `{"ok"|"err"}` envelope `decode_envelope` reads.
/// That envelope exists because `_request` hands back a live JS value, which
/// has to be serialized to cross the boundary at all; a response body is
/// already a string and already JSON, so wrapping it would be a second escape
/// pass and a second parse of every byte, only to unwrap it again. Splitting
/// on one newline costs neither. It also keeps `-32603` out of JavaScript:
/// which failures are which error is a decision `provider/error.mbt` owns.
extern "js" fn _post_json(
  url : String,
  body : String,
) -> @js_async.Promise[String] =
  #| (url, body) =>
  #|   fetch(url, {
  #|     method: 'POST',
  #|     headers: { 'content-type': 'application/json' },
  #|     body,
  #|   })
  #|     .then(res => res.text().then(text => `${res.status}\n${text}`))
  #|     .catch(e => `0\n${String((e && e.message) ? e.message : e)}`)

///|
/// POST `body` to `url`, answering with `"<status>\n<response body>"` — see
/// `_post_json` for what that says and why it is not the `ok`/`err` envelope.
pub fn post_json(url : String, body : String) -> @js_async.Promise[String] {
  _post_json(url, body)
}
