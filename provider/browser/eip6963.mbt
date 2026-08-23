///|
/// The two halves of the EIP-6963 handshake. The names live here rather than in
/// `ffi/js`, which binds `window` and decides nothing about what is said over
/// it.
let announce_event : String = "eip6963:announceProvider"

///|
let request_event : String = "eip6963:requestProvider"

///|
/// What a wallet says about itself when it announces over
/// [EIP-6963](https://eips.ethereum.org/EIPS/eip-6963).
///
/// Read off the wire and never built by a caller. `rdns` is the stable identity
/// a dapp should key on; `uuid` is fresh per page load. Every field is the
/// wallet's own claim: any installed extension can announce.
pub(all) struct ProviderInfo {
  uuid : String
  name : String
  icon : String
  rdns : String
}

///|
/// Decode an announcement's `info`. All four fields are required by EIP-6963 and
/// three are spelled a particular way, so an announcement breaking either rule
/// is answered with `None`.
///
/// `icon` is what a page puts in an `<img src>`, where a `javascript:` URL would
/// be the wallet reaching into it. Public for a page with its own listener.
pub fn ProviderInfo::from_json(json : Json) -> ProviderInfo? {
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
  guard icon.has_prefix("data:image/") && is_rdns(rdns) && is_uuid_v4(uuid) else {
    return None
  }
  Some(ProviderInfo::{ uuid, name, icon, rdns })
}

///|
/// Whether `rdns` is spelled as a reverse-DNS name: dot-separated labels of
/// letters, digits and hyphens, at least two of them, and not starting with a
/// digit. This says nothing about who owns the name — `io.metamask` is as
/// cheap to announce as anything else — only that a dapp keying on it is
/// keying on something domain-shaped.
fn is_rdns(rdns : StringView) -> Bool {
  let labels = rdns.split(".").collect()
  guard labels.length() >= 2 &&
    // a domain name does not start with a digit
    rdns.iter().take(1).all(c => !c.is_ascii_digit()) else {
    return false
  }
  labels
  .iter()
  .all(label => {
    label.length() > 0 &&
    label
    .iter()
    .all(c => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-')
  })
}

///|
/// Whether `uuid` is spelled as a UUIDv4: `8-4-4-4-12` hex digits, the version
/// nibble `4`, and an RFC 4122 variant. Fresh per page load and no identity in
/// itself, but a dapp that indexes a picker by it wants what the EIP promised.
fn is_uuid_v4(uuid : StringView) -> Bool {
  guard uuid.length() == 36 else { return false }
  guard uuid.unsafe_get(8) == '-' &&
    uuid.unsafe_get(13) == '-' &&
    uuid.unsafe_get(18) == '-' &&
    uuid.unsafe_get(23) == '-' &&
    uuid.unsafe_get(14) == '4' &&
    uuid.unsafe_get(19) is ('8' | '9' | 'a' | 'b' | 'A' | 'B') else {
    return false
  }
  // the version and variant nibbles are read above
  @codec.is_hex_digits(uuid[0:8]) &&
  @codec.is_hex_digits(uuid[9:13]) &&
  @codec.is_hex_digits(uuid[15:18]) &&
  @codec.is_hex_digits(uuid[20:23]) &&
  @codec.is_hex_digits(uuid[24:36])
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
/// **Enumeration never finishes**: wallets announce at load and again whenever
/// anyone asks, so the answer is a stream and the same `rdns` may arrive twice.
/// Use `discover` for a list to draw a picker from.
///
/// ```
/// fn watch() -> @provider.Subscription {
///   @browser.BrowserProvider::on_announce((info, _) => println(info.name))
/// }
/// ```
pub fn BrowserProvider::on_announce(
  handler : (ProviderInfo, BrowserProvider) -> Unit,
) -> @provider.Subscription {
  let listener = @js.on_window_event(event=announce_event, handler=(detail, eth) => {
    // an announcement that does not carry the four required fields is dropped:
    // an event has nowhere to raise to
    guard detail is Object(obj) &&
      obj.get("info") is Some(info_json) &&
      ProviderInfo::from_json(info_json) is Some(info) else {
      return
    }
    handler(info, BrowserProvider::over(eth))
  })
  // register first, then ask — a wallet answers synchronously
  @js.dispatch_window_event(event=request_event)
  @provider.Subscription::new(() => {
    @js.remove_window_listener(event=announce_event, listener~)
  })
}

///|
/// Collect the wallets that announce themselves within `timeout_ms`, for drawing
/// a picker with. Duplicates are collapsed by `rdns`, keeping the first.
///
/// When nothing announced, this falls back to `globalThis.ethereum`, read
/// *before* the wait — it is there from document start. The array is empty only
/// when there is no wallet at all, and a host with no `window` skips the wait.
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
  // a host with no `window` has nobody to answer with: waiting out the deadline
  // there would only delay the fallback
  if @js.has_window_events() {
    // a cancelled wait is still an answer: report the wallets already announced
    @async.sleep(timeout_ms) catch {
      _ => ()
    }
  }
  sub.unsubscribe()
  if found.is_empty() && injected is Some(provider) {
    found.push(DiscoveredWallet::{ info: None, provider })
  }
  found
}
