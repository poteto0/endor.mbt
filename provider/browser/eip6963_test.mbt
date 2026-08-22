///|
/// A `window` to announce on. Node has no `addEventListener`, so the test puts
/// the smallest one that EIP-6963 needs *underneath* the SDK — the same licence
/// the fake `globalThis.ethereum` above runs on.
extern "js" fn install_window_events() -> Unit =
  #| () => {
  #|   const listeners = new Map()
  #|   globalThis.addEventListener = (event, fn) => {
  #|     if (!listeners.has(event)) listeners.set(event, [])
  #|     listeners.get(event).push(fn)
  #|   }
  #|   globalThis.removeEventListener = (event, fn) => {
  #|     const fns = listeners.get(event) || []
  #|     const at = fns.indexOf(fn)
  #|     if (at >= 0) fns.splice(at, 1)
  #|   }
  #|   globalThis.dispatchEvent = (event) => {
  #|     for (const fn of (listeners.get(event.type) || []).slice()) fn(event)
  #|     return true
  #|   }
  #| }

///|
extern "js" fn uninstall_window_events() -> Unit =
  #| () => {
  #|   delete globalThis.addEventListener
  #|   delete globalThis.removeEventListener
  #|   delete globalThis.dispatchEvent
  #| }

///|
/// Play the wallets: each answers `eth_chainId` with its own value, so a test
/// can tell *which* provider object came back with an announcement rather than
/// only that one did.
///
/// `info_json` is a JSON array of the `info` objects to announce, spelled by
/// the test so a malformed one can be spelled too. Each announces once per
/// `eip6963:requestProvider`, which is what the EIP asks of a wallet.
extern "js" fn install_announcing_wallets(info_json : String) -> Unit =
  #| (infoJson) => {
  #|   const infos = JSON.parse(infoJson)
  #|   globalThis.addEventListener('eip6963:requestProvider', () => {
  #|     infos.forEach((info, at) => {
  #|       const provider = {
  #|         request: async ({ method }) =>
  #|           method === 'eth_chainId' ? '0x' + (at + 1) : null
  #|       }
  #|       globalThis.dispatchEvent(
  #|         new CustomEvent('eip6963:announceProvider', {
  #|           detail: { info, provider }
  #|         })
  #|       )
  #|     })
  #|   })
  #| }

///|
/// The same wallets, but announcing the kind of provider object a real
/// extension has: one that holds itself, and one whose properties run code that
/// throws. Neither can be serialised, and neither has to be — the provider
/// crosses as a handle.
extern "js" fn install_unserialisable_wallets(info_json : String) -> Unit =
  #| (infoJson) => {
  #|   const infos = JSON.parse(infoJson)
  #|   globalThis.addEventListener('eip6963:requestProvider', () => {
  #|     infos.forEach((info, at) => {
  #|       const provider = {
  #|         request: async ({ method }) =>
  #|           method === 'eth_chainId' ? '0x' + (at + 1) : null
  #|       }
  #|       if (at % 2 === 0) {
  #|         provider._events = { self: provider }
  #|       } else {
  #|         Object.defineProperty(provider, 'state', {
  #|           enumerable: true,
  #|           get: () => { throw new Error('not yours to read') }
  #|         })
  #|       }
  #|       globalThis.dispatchEvent(
  #|         new CustomEvent('eip6963:announceProvider', {
  #|           detail: { info, provider }
  #|         })
  #|       )
  #|     })
  #|   })
  #| }

///|
/// The `info` two well-behaved wallets announce.
let two_wallets : String =
  #|[{"uuid":"11111111-1111-4111-8111-111111111111","name":"Wallet A","icon":"data:image/svg+xml,A","rdns":"com.example.a"},
  #| {"uuid":"22222222-2222-4222-9222-222222222222","name":"Wallet B","icon":"data:image/svg+xml,B","rdns":"com.example.b"}]

///|
test "on_announce delivers every announcement and unsubscribe stops it" {
  install_window_events()
  install_announcing_wallets(two_wallets)
  let seen = []
  let sub = @browser.BrowserProvider::on_announce((info, _) => {
    seen.push(info.rdns)
  })
  // `on_announce` asked once on the way in
  inspect(seen.join(","), content="com.example.a,com.example.b")

  // asking again re-announces: enumeration has no end, and nothing is deduped
  // at this level
  @js.dispatch_window_event(event="eip6963:requestProvider")
  inspect(seen.length(), content="4")
  sub.unsubscribe()
  @js.dispatch_window_event(event="eip6963:requestProvider")
  inspect(seen.length(), content="4")
  uninstall_window_events()
}

///|
test "an announcement missing a required field is dropped" {
  install_window_events()
  let infos =
    #|[{"uuid":"11111111-1111-4111-8111-111111111111","name":"Wallet A","icon":"data:image/png;base64,AA","rdns":"com.example.a"},
    #| {"uuid":"22222222-2222-4222-9222-222222222222","name":"Wallet B","icon":"data:image/png;base64,AA"},
    #| {"uuid":"33333333-3333-4333-a333-333333333333","name":"","icon":"data:image/png;base64,AA","rdns":"com.example.c"},
    #| "not an object"]
  install_announcing_wallets(infos)
  let seen = []
  @browser.BrowserProvider::on_announce((info, _) => seen.push(info.rdns)).unsubscribe()
  inspect(seen.join(","), content="com.example.a")
  uninstall_window_events()
}

///|
/// An announcement is whatever an installed extension felt like sending, so
/// the fields EIP-6963 spells out are read as spelled or not at all — an
/// `icon` that is not a data URI is the one that reaches a dapp's `<img src>`.
test "an announcement whose fields break the EIP-6963 spelling is dropped" {
  let ok_uuid = "11111111-1111-4111-8111-111111111111"
  let ok_icon = "data:image/png;base64,AA"
  let ok_rdns = "com.example.a"
  fn info(uuid : String, icon : String, rdns : String) {
    @browser.ProviderInfo::from_json(
      { "uuid": uuid, "name": "Wallet A", "icon": icon, "rdns": rdns }.to_json(),
    )
  }

  assert_true(info(ok_uuid, ok_icon, ok_rdns) is Some(_))

  // `icon`: anything but a data URI is the wallet reaching into the page
  assert_true(info(ok_uuid, "javascript:alert(1)", ok_rdns) is None)
  assert_true(info(ok_uuid, "https://example.com/a.png", ok_rdns) is None)
  assert_true(info(ok_uuid, "data:text/html,<script>", ok_rdns) is None)

  // `rdns`: domain-shaped, and a bare label is not
  assert_true(info(ok_uuid, ok_icon, "metamask") is None)
  assert_true(info(ok_uuid, ok_icon, "com..example") is None)
  assert_true(info(ok_uuid, ok_icon, "com.exa mple.a") is None)
  assert_true(info(ok_uuid, ok_icon, "1com.example") is None)
  assert_true(info(ok_uuid, ok_icon, "io.metamask") is Some(_))

  // `uuid`: a UUIDv4, version nibble and variant included
  assert_true(info("uuid-a", ok_icon, ok_rdns) is None)
  assert_true(
    info("11111111-1111-1111-8111-111111111111", ok_icon, ok_rdns) is None,
  )
  assert_true(
    info("11111111-1111-4111-1111-111111111111", ok_icon, ok_rdns) is None,
  )
  assert_true(
    info("1111111111114111811111111111111z", ok_icon, ok_rdns) is None,
  )
  assert_true(
    info("11111111-1111-4111-A111-111111111111", ok_icon, ok_rdns) is Some(_),
  )
}

///|
/// A wallet is not dropped for having a provider object that cannot be turned
/// into JSON — which is most of them.
test "an announcement carrying an unserialisable provider is delivered" {
  install_window_events()
  install_unserialisable_wallets(two_wallets)
  let seen = []
  @browser.BrowserProvider::on_announce((info, _) => seen.push(info.rdns)).unsubscribe()
  inspect(seen.join(","), content="com.example.a,com.example.b")
  uninstall_window_events()
}

///|
/// Run `setup` and `discover` with no await between them: `globalThis` is
/// shared with every other test in this package, and only a stretch with no
/// suspension point in it belongs to one test alone.
async fn discovered(setup : () -> Unit) -> Array[@browser.DiscoveredWallet] {
  let mut found = []
  @async.with_task_group(_ => {
    setup()
    found = @browser.BrowserProvider::discover(timeout_ms=1)
  })
  found
}

///|
async test "discover collects the announced wallets, deduped by rdns" {
  let found = discovered(() => {
    install_window_events()
    install_announcing_wallets(two_wallets)
    // two rounds of announcements reach the same collector; `discover` asks
    // once itself, and this ask makes every wallet announce twice
    @js.dispatch_window_event(event="eip6963:requestProvider")
  })
  inspect(found.length(), content="2")
  inspect(
    found.map(w => w.info.unwrap().name).join(","),
    content="Wallet A,Wallet B",
  )

  // the provider handed back is the announcing wallet's own object, not
  // `globalThis.ethereum` — which is not even installed here
  let mut chain = "".to_json()
  @async.with_task_group(_ => {
    chain = found[1].provider.request(
      method_name="eth_chainId",
      params=Json::array([]),
    ) catch {
      e => fail("expected success, but \{e}")
    }
  })
  debug_inspect(chain, content="String(\"0x2\")")
  uninstall_window_events()
}

///|
async test "discover falls back to the injected wallet when nothing announces" {
  let found = discovered(() => {
    install_window_events()
    install_mock_ethereum()
  })
  inspect(found.length(), content="1")
  inspect(found[0].info is None, content="true")
  inspect(found[0].provider.is_metamask(), content="true")
  uninstall_mock_ethereum()
  uninstall_window_events()
}

///|
async test "discover answers empty when there is no wallet at all" {
  let found = discovered(() => {
    install_window_events()
    uninstall_mock_ethereum()
  })
  inspect(found.is_empty(), content="true")
  uninstall_window_events()
}

///|
/// A host with no `window` — a node runtime, a worker — must not take the page
/// down: nothing registers, nothing announces, and unsubscribing is still safe.
async test "discover on a host with no window falls back and does not raise" {
  let found = discovered(() => {
    uninstall_window_events()
    install_mock_ethereum()
  })
  inspect(found.length(), content="1")
  inspect(found[0].info is None, content="true")
  uninstall_mock_ethereum()
}
