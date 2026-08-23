///|
/// Opaque handle to a listener registered on the *window*, not on a provider.
///
/// Some wallet protocols talk over `window` events rather than the EIP-1193
/// emitter: a different target, a different register / unregister pair, and a
/// payload that can carry a live provider object next to its JSON description.
/// Like `Listener`, it exists because `removeEventListener` matches on identity.
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
/// The payload is half data and half object: the live EIP-1193 object goes in
/// `detail.provider` and everything else in `detail`, so the handler takes both.
/// An event carrying no provider is dropped, as is a detail that will not
/// stringify — a wallet's provider object is often not serialisable at all.
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
/// of the string the boundary carries.
///
/// A detail that is not valid JSON is dropped: the handler is not called, since
/// an event arrives outside any call the dapp made.
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
