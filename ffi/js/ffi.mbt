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
/// - failure: `{"err": {"code": <int>, "message": <string>, "data": <any>}}`
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
  #|          message: String((e && e.message) ? e.message : e),
  #|          data: (e && e.data !== undefined) ? e.data : null
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
/// Parse the JSON-string envelope returned from the JavaScript boundary:
///
/// - success: `{"ok": <result>}`
/// - failure: `{"err": {"code": <int>, "message": <string>, "data": <any>}}`
///
/// `data` is optional — `Null` when the wallet attached none.
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

    let data = err_obj.get("data").unwrap_or(Json::null())
    raise RemoteError(code, message, data)
  }

  guard obj.get("ok") is Some(v) else {
    raise InvalidEnvelope("FFI envelope missing ok/err")
  }

  v
}
