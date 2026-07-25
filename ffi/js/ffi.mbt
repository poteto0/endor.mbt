///|
/// Opaque handle to the injected `globalThis.ethereum` EIP-1193 provider
/// object. This is the only package that talks to JavaScript directly.
#external
type Ethereum

///|
/// `true` when `globalThis.ethereum` is present.
extern "js" fn js_has_ethereum() -> Bool =
  #| () => (typeof globalThis.ethereum !== 'undefined' && globalThis.ethereum !== null)

///|
/// Fetch the injected provider object (assumes `js_has_ethereum()` is true).
extern "js" fn js_get_ethereum() -> Ethereum =
  #| () => globalThis.ethereum

///|
/// `true` when the injected provider identifies itself as MetaMask.
extern "js" fn js_is_metamask(eth : Ethereum) -> Bool =
  #| (eth) => !!(eth && eth.isMetaMask)

///|
/// Call `ethereum.request(payload)` where `payload` is a JSON string of
/// `{ method, params }`. The returned promise **always resolves** to a JSON
/// string envelope so structured error codes survive the boundary:
///
/// - success: `{"ok": <result>}`
/// - failure: `{"err": {"code": <int>, "message": <string>}}`
extern "js" fn js_request(
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
