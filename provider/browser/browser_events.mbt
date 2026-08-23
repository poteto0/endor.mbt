///|
/// Subscribe to an EIP-1193 event on the injected wallet.
///
/// A payload that is not valid JSON is dropped at the boundary, and one that
/// does not decode is dropped by the typed helper: an event arrives outside any
/// call the dapp made. A wallet with no event API registers nothing, and
/// `unsubscribe` is still safe.
///
/// ```
/// fn watch(wallet : @browser.BrowserProvider) -> @provider.Subscription {
///   @provider.on_accounts_changed(wallet, accounts => println(accounts))
/// }
/// ```
pub impl @provider.EventSource for BrowserProvider with fn subscribe(
  self,
  event~,
  handler~,
) {
  let listener = @js.on(self.eth, event~, handler~)
  // `removeListener` matches on function identity, so unsubscribing hands back
  // the very handle `on` registered
  @provider.Subscription::new(() => {
    @js.remove_listener(self.eth, event~, listener~)
  })
}

///|
/// Whether the injected wallet exposes the EIP-1193 event API
/// (`on` / `removeListener`).
///
/// Subscribing to a wallet that does not is harmless — the handler simply never
/// fires — so this is for telling the user why, not for guarding the call.
pub fn BrowserProvider::has_events(self : BrowserProvider) -> Bool {
  @js.has_events(self.eth)
}
