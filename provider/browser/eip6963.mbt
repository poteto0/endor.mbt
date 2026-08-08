///|
/// What a wallet says about itself when it announces over
/// [EIP-6963](https://eips.ethereum.org/EIPS/eip-6963).
///
/// This is read off the wire and never built by a caller, so every field is
/// public and `from_json` is the only thing that makes one. `rdns` is the
/// stable identity — a reverse-DNS name the wallet owns (`io.metamask`) — and
/// is what a dapp should key on; `uuid` is fresh per page load, and `name` and
/// `icon` are for showing the user.
pub(all) struct ProviderInfo {
  uuid : String
  name : String
  icon : String
  rdns : String
}

///|
/// Decode an announcement's `info`. All four fields are required by EIP-6963,
/// so an object missing any of them is not an announcement this SDK can key on
/// and is answered with `None` — the caller drops it.
fn ProviderInfo::from_json(json : Json) -> ProviderInfo? {
  guard json is Object(obj) else { return None }
  fn field(name : String) -> String? {
    guard obj.get(name) is Some(String(s)) && s != "" else { return None }
    Some(s)
  }

  guard field("uuid") is Some(uuid) &&
    field("name") is Some(name) &&
    field("icon") is Some(icon) &&
    field("rdns") is Some(rdns) else {
    return None
  }
  Some(ProviderInfo::{ uuid, name, icon, rdns })
}

///|
/// One wallet `discover` found, and how it was found.
///
/// `info` is `None` for the legacy `globalThis.ethereum` injection, which
/// announces nothing and therefore names itself nowhere: there is no honest
/// `ProviderInfo` to give it. A dapp showing a picker labels that entry itself
/// ("Injected wallet", `is_metamask()`, …).
pub(all) struct DiscoveredWallet {
  info : ProviderInfo?
  provider : BrowserProvider
}

///|
/// Subscribe to EIP-6963 announcements, and ask every installed wallet to
/// announce itself.
///
/// This is the honest shape of the protocol: **enumeration never finishes**.
/// Wallets announce unprompted at load and again whenever anyone asks, and an
/// extension can be woken after the page is up, so the answer is a stream, not
/// a list. A wallet may announce more than once — the same `rdns` arriving
/// twice is normal and is not filtered here.
///
/// `unsubscribe` on the returned handle stops delivery, and is safe to call
/// twice or on a host with no `window` at all.
///
/// Use `discover` instead when what you want is a list to draw a picker from.
///
/// ```
/// fn watch() -> @provider.Subscription {
///   @browser.BrowserProvider::on_announce((info, _) => println(info.name))
/// }
/// ```
pub fn BrowserProvider::on_announce(
  handler : (ProviderInfo, BrowserProvider) -> Unit,
) -> @provider.Subscription {
  let listener = @js.on_announce(handler=(info_json, eth) => {
    // an announcement that does not carry the four required fields is dropped:
    // an event has nowhere to raise to
    guard ProviderInfo::from_json(info_json) is Some(info) else { return }
    handler(info, BrowserProvider::{ eth, })
  })
  // register first, then ask — a wallet answers synchronously
  @js.request_providers()
  @provider.Subscription::new(() => @js.remove_announce_listener(listener))
}

///|
/// Collect the wallets that announce themselves within `timeout_ms`, for
/// drawing a picker with.
///
/// Enumeration has no end (see `on_announce`), so this puts a deadline on it
/// and answers with what arrived: wallets answer the request synchronously, so
/// a short wait is enough in practice and the default is deliberately small.
/// Duplicate announcements are collapsed by `rdns`, keeping the first.
///
/// When nothing announced, this falls back to `globalThis.ethereum` — a single
/// `DiscoveredWallet` with no `info` — so a dapp written against EIP-6963 still
/// works with a wallet that only injects. The injection is read *before* the
/// wait rather than after it: it is there from document start, so a wallet that
/// is not injected when discovery begins is not going to appear because we
/// waited. The array is empty only when there is no wallet at all.
///
/// ```
/// async fn pick() -> Array[@browser.DiscoveredWallet] {
///   @browser.BrowserProvider::discover()
/// }
/// ```
pub async fn BrowserProvider::discover(
  timeout_ms? : Int = 300,
) -> Array[DiscoveredWallet] {
  let found = []
  let seen : Set[String] = Set([])
  let sub = BrowserProvider::on_announce((info, provider) => {
    if seen.add_and_check(info.rdns) {
      found.push(DiscoveredWallet::{ info: Some(info), provider })
    }
  })
  let injected = BrowserProvider::detect()
  // a cancelled wait is still an answer: report the wallets already announced
  @async.sleep(timeout_ms) catch {
    _ => ()
  }
  sub.unsubscribe()
  if found.is_empty() && injected is Some(provider) {
    found.push(DiscoveredWallet::{ info: None, provider })
  }
  found
}
