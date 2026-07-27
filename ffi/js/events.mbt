///|
/// Opaque handle to a listener registered with `eth.on(...)`.
///
/// EIP-1193 providers follow the Node `EventEmitter` contract, where
/// `removeListener` matches on the *identity* of the function that was
/// registered. The wrapper closure `on` installs is therefore not discardable:
/// it is handed back as this handle so `remove_listener` can pass the very same
/// JS function reference.
#external
pub type Listener

///|
/// `true` when the injected provider exposes the EIP-1193 event API
/// (`on` / `removeListener`). Wallets that only implement `request` exist, so
/// callers must not assume it.
extern "js" fn _has_events(eth : Ethereum) -> Bool =
  #| (eth) => !!(eth && typeof eth.on === 'function' && typeof eth.removeListener === 'function')

///|
pub fn has_events(eth : Ethereum) -> Bool {
  _has_events(eth)
}

///|
/// Register `handler` for `event` and return the handle identifying it.
///
/// The payload crosses the boundary as a JSON string, the way `request`'s
/// answer does, so nothing but strings and numbers has to survive it: the
/// wrapper `JSON.stringify`s whatever the wallet emitted, mapping the
/// `undefined` an argument-less event carries onto `null`. Unlike `request` it
/// carries no `{ok}` / `{err}` envelope, because an event has no error channel
/// to encode.
///
/// A wallet with no event API is not an error here — the handle comes back
/// unregistered and `remove_listener` is a no-op on it, which keeps
/// unsubscribing safe on every wallet.
extern "js" fn _on(
  eth : Ethereum,
  event : String,
  handler : (String) -> Unit,
) -> Listener =
  #| (eth, event, handler) => {
  #|   const listener = (payload) =>
  #|     handler(JSON.stringify(payload === undefined ? null : payload))
  #|   if (typeof eth.on === 'function') {
  #|     eth.on(event, listener)
  #|   }
  #|   return listener
  #| }

///|
/// Subscribe `handler` to `event`, parsing the payload back out of the string
/// the boundary carries — the same split as `request` / `decode_envelope`, so
/// no package above this one has to know the wire is a string.
///
/// A payload that is not valid JSON is dropped: the handler is not called. An
/// event arrives outside any call the dapp made, so there is nowhere to raise
/// to, and a wallet emitting nonsense must not take the page down.
pub fn on(
  eth : Ethereum,
  event~ : String,
  handler~ : (Json) -> Unit,
) -> Listener {
  _on(eth, event, payload_json => {
    let payload = @json.parse(payload_json) catch { _ => return }
    handler(payload)
  })
}

///|
/// Unregister the listener `on` returned. Calling it for a wallet that never
/// registered anything, or twice for the same handle, does nothing.
extern "js" fn _remove_listener(
  eth : Ethereum,
  event : String,
  listener : Listener,
) -> Unit =
  #| (eth, event, listener) => {
  #|   if (typeof eth.removeListener === 'function') {
  #|     eth.removeListener(event, listener)
  #|   }
  #| }

///|
pub fn remove_listener(
  eth : Ethereum,
  event~ : String,
  listener~ : Listener,
) -> Unit {
  _remove_listener(eth, event, listener)
}
