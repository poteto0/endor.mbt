///|
/// Opaque handle to a listener registered on the *window*, not on the provider.
///
/// EIP-6963 talks over `window` events rather than the EIP-1193 emitter, so
/// this is a separate path from `Listener`: a different target, a different
/// pair of register / unregister functions, and a payload that carries a live
/// provider object next to its JSON description.
///
/// Like `Listener`, it exists because `removeEventListener` matches on the
/// *identity* of the function that was registered.
#external
pub type WindowListener

///|
/// Register `handler` for `eip6963:announceProvider`.
///
/// The announcement's `detail` is half data and half object: `info` is plain
/// JSON, `provider` is the live EIP-1193 object the wallet is offering. Only
/// the first half can cross as a string, so the handler takes both — the JSON
/// text and the object handle — and an announcement missing either is dropped
/// at the boundary rather than passed on half-built.
///
/// A host with no `addEventListener` (a bare node runtime, say) is not an
/// error: nothing is registered, the handle comes back inert, and
/// `remove_window_listener` is a no-op on it.
extern "js" fn _on_announce(
  handler : (String, Ethereum) -> Unit,
) -> WindowListener =
  #| (handler) => {
  #|   const listener = (event) => {
  #|     const detail = (event && event.detail) || {}
  #|     if (!detail.info || !detail.provider) return
  #|     handler(JSON.stringify(detail.info), detail.provider)
  #|   }
  #|   if (typeof globalThis.addEventListener === 'function') {
  #|     globalThis.addEventListener('eip6963:announceProvider', listener)
  #|   }
  #|   return listener
  #| }

///|
/// Subscribe `handler` to `eip6963:announceProvider`, parsing the info back out
/// of the string the boundary carries — the same split as `on` /
/// `remove_listener`, so no package above this one has to know the wire is a
/// string.
///
/// An `info` that is not valid JSON is dropped: the handler is not called. An
/// announcement arrives outside any call the dapp made, so there is nowhere to
/// raise to.
pub fn on_announce(handler~ : (Json, Ethereum) -> Unit) -> WindowListener {
  _on_announce((info_json, eth) => {
    let info = @json.parse(info_json) catch { _ => return }
    handler(info, eth)
  })
}

///|
/// Unregister the window listener `on_announce` returned. Calling it for a host
/// that never registered anything, or twice for the same handle, does nothing.
extern "js" fn _remove_window_listener(
  event : String,
  listener : WindowListener,
) -> Unit =
  #| (event, listener) => {
  #|   if (typeof globalThis.removeEventListener === 'function') {
  #|     globalThis.removeEventListener(event, listener)
  #|   }
  #| }

///|
pub fn remove_announce_listener(listener : WindowListener) -> Unit {
  _remove_window_listener("eip6963:announceProvider", listener)
}

///|
/// Dispatch `eip6963:requestProvider`, which is what makes every installed
/// wallet announce itself. Wallets also announce unprompted at load time, so
/// this is a re-ask rather than the only way an announcement arrives — and it
/// must be sent *after* the listener is registered.
extern "js" fn _request_providers() -> Unit =
  #| () => {
  #|   if (typeof globalThis.dispatchEvent === 'function' && typeof Event === 'function') {
  #|     globalThis.dispatchEvent(new Event('eip6963:requestProvider'))
  #|   }
  #| }

///|
pub fn request_providers() -> Unit {
  _request_providers()
}
