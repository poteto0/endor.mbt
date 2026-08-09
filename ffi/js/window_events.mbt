///|
/// Opaque handle to a listener registered on the *window*, not on a provider.
///
/// Some wallet protocols talk over `window` events rather than the EIP-1193
/// emitter, so this is a separate path from `Listener`: a different target, a
/// different pair of register / unregister functions, and a payload that can
/// carry a live provider object next to its JSON description.
///
/// Like `Listener`, it exists because `removeEventListener` matches on the
/// *identity* of the function that was registered.
#external
pub type WindowListener

///|
/// `true` when the host has a `window` to talk over — a page does, a bare node
/// runtime or a worker may not. Registering on one that does not is harmless,
/// so this is for telling a caller not to bother waiting for an answer.
extern "js" fn _has_window_events() -> Bool =
  #| () => (typeof globalThis.addEventListener === 'function' && typeof globalThis.dispatchEvent === 'function')

///|
pub fn has_window_events() -> Bool {
  _has_window_events()
}

///|
/// Register `handler` for the window event named `event`.
///
/// The payload is half data and half object: an event that offers a provider
/// puts the live EIP-1193 object in `detail.provider` and everything else in
/// `detail`. Only the second half can cross as a string, so the handler takes
/// both — the JSON text of `detail`, and the object handle. An event carrying
/// no provider is dropped here, because there is no null `Ethereum` for it to
/// cross as; *what else* makes a payload usable is not this layer's to say.
///
/// `provider` is left out of the string. A wallet's provider object is live —
/// event handlers holding it back, getters that run — and more than one real
/// wallet is not serialisable at all, so stringifying the whole detail throws
/// and takes that wallet's event down with it. It crosses as the handle, which
/// is the only useful form of it anyway. A detail that still will not stringify
/// is dropped rather than raised, for the same reason a malformed one is.
extern "js" fn _on_window_event(
  event : String,
  handler : (String, Ethereum) -> Unit,
) -> WindowListener =
  #| (event, handler) => {
  #|   const listener = (e) => {
  #|     const detail = (e && e.detail) || {}
  #|     if (!detail.provider) return
  #|     let json
  #|     try {
  #|       json = JSON.stringify(detail, (key, value) =>
  #|         key === 'provider' ? undefined : value)
  #|     } catch {
  #|       return
  #|     }
  #|     if (json === undefined) return
  #|     handler(json, detail.provider)
  #|   }
  #|   if (typeof globalThis.addEventListener === 'function') {
  #|     globalThis.addEventListener(event, listener)
  #|   }
  #|   return listener
  #| }

///|
/// Subscribe `handler` to the window event `event`, parsing the detail back out
/// of the string the boundary carries — the same split as `on` /
/// `remove_listener`, so no package above this one has to know the wire is a
/// string.
///
/// A detail that is not valid JSON is dropped: the handler is not called. An
/// event arrives outside any call the dapp made, so there is nowhere to raise
/// to.
pub fn on_window_event(
  event~ : String,
  handler~ : (Json, Ethereum) -> Unit,
) -> WindowListener {
  _on_window_event(event, (detail_json, eth) => {
    let detail = @json.parse(detail_json) catch { _ => return }
    handler(detail, eth)
  })
}

///|
/// Unregister the listener `on_window_event` returned. Calling it for a host
/// with no `window`, or twice for the same handle, does nothing.
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
pub fn remove_window_listener(
  event~ : String,
  listener~ : WindowListener,
) -> Unit {
  _remove_window_listener(event, listener)
}

///|
/// Dispatch the window event named `event`, with no detail on it. This is how a
/// page *asks* — a wallet answers with an event of its own.
extern "js" fn _dispatch_window_event(event : String) -> Unit =
  #| (event) => {
  #|   if (typeof globalThis.dispatchEvent === 'function' && typeof Event === 'function') {
  #|     globalThis.dispatchEvent(new Event(event))
  #|   }
  #| }

///|
pub fn dispatch_window_event(event~ : String) -> Unit {
  _dispatch_window_event(event)
}
