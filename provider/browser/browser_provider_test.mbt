///|
/// Install a fake window.ethereum provider for tests.
extern "js" fn install_mock_ethereum() -> Unit =
  #| () => {
  #|   const listeners = new Map()
  #|   globalThis.ethereum = {
  #|     isMetaMask: true,
  #|     on: (event, listener) => {
  #|       if (!listeners.has(event)) listeners.set(event, [])
  #|       listeners.get(event).push(listener)
  #|     },
  #|     removeListener: (event, listener) => {
  #|       const fns = listeners.get(event) || []
  #|       const at = fns.indexOf(listener)
  #|       if (at >= 0) fns.splice(at, 1)
  #|     },
  #|     // not part of EIP-1193 — how this test plays the wallet
  #|     __emit: (event, payload) => {
  #|       for (const listener of (listeners.get(event) || []).slice()) {
  #|         listener(payload)
  #|       }
  #|     },
  #|     __listenerCount: (event) => (listeners.get(event) || []).length,
  #|     request: async ({ method, params }) => {
  #|       if (method === "eth_requestAccounts") {
  #|         return ["0x1234567890abcdef"]
  #|       }
  #|       if (method === "eth_chainId") {
  #|         return "0x1"
  #|       }
  #|       throw {
  #|         code: 4001,
  #|         message: "User rejected"
  #|       }
  #|       return null
  #|     }
  #|   }
  #| }

///|
/// Remove injected provider after test.
extern "js" fn uninstall_mock_ethereum() -> Unit =
  #| () => {
  #|   delete globalThis.ethereum
  #| }

///|
test "detect browser provider & judge metamask when wallet exists" {
  install_mock_ethereum()

  let provider = @browser.BrowserProvider::detect()

  inspect(provider is Some(_), content="true")

  let provider = @browser.BrowserProvider::require() catch {
    e => fail("expected success, but \{e}")
  }

  inspect(provider.is_metamask(), content="true")

  uninstall_mock_ethereum()
}

///|
test "detect none when wallet doesn't exists" {
  let provider = @browser.BrowserProvider::detect()

  inspect(provider is Some(_), content="false")

  let _ = try @browser.BrowserProvider::require() catch {
    @provider.NotInstalled(_) => ()
    e => fail("expected not installed, but \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
async test "request returns accounts" {
  install_mock_ethereum()

  let provider = match @browser.BrowserProvider::detect() {
    Some(p) => p
    None => fail("expected provider")
  }

  let mut result = "".to_json()
  @async.with_task_group(_ => {
    result = provider.request(
      method_name="eth_requestAccounts",
      params=Json::array([]),
    ) catch {
      e => fail("expected success, but \{e}")
    }
  })

  debug_inspect(result, content="Array([String(\"0x1234567890abcdef\")])")

  uninstall_mock_ethereum()
}

///|
async test "request returns chain id" {
  install_mock_ethereum()

  let provider = @browser.BrowserProvider::require() catch {
    e => fail("expected provider, but \{e}")
  }

  let mut result = "".to_json()
  @async.with_task_group(_ => {
    result = provider.request(method_name="eth_chainId", params=Json::array([])) catch {
      e => fail("expected success, but \{e}")
    }
  })

  debug_inspect(result, content="String(\"0x1\")")

  uninstall_mock_ethereum()
}

///|
async test "request maps provider error" {
  install_mock_ethereum()

  let provider = @browser.BrowserProvider::require() catch {
    e => fail("expected provider, but \{e}")
  }

  @async.with_task_group(_ => {
    let _ = try
      provider.request(
        method_name="eth_sendTransaction",
        params=Json::array([]),
      )
    catch {
      @provider.ProviderError::UserRejected(_) => ()
      e => fail("unexpected error: \{e}")
    } noraise {
      _ => fail("expected error, but success")
    }
  })

  uninstall_mock_ethereum()
}

///|
/// Play the wallet: fire `event` at whatever the fake `ethereum.on` registered.
/// The payload is written as JSON so the test spells it in one place.
extern "js" fn emit_mock_event(event : String, payload_json : String) -> Unit =
  #| (event, payload) => globalThis.ethereum.__emit(event, JSON.parse(payload))

///|
/// How many listeners the fake wallet currently holds for `event` — what proves
/// `unsubscribe` really reached `removeListener` rather than only muting the
/// MoonBit side.
extern "js" fn mock_listener_count(event : String) -> Int =
  #| (event) => globalThis.ethereum.__listenerCount(event)

///|
/// A wallet exposing only `request`: no `on`, no `removeListener`.
extern "js" fn install_eventless_ethereum() -> Unit =
  #| () => {
  #|   globalThis.ethereum = { isMetaMask: false, request: async () => null }
  #| }

///|
test "subscribe, emit and unsubscribe round trip through the injected wallet" {
  install_mock_ethereum()
  let wallet = @browser.BrowserProvider::require() catch {
    e => fail("expected provider, but \{e}")
  }
  inspect(wallet.has_events(), content="true")
  let seen = []
  let sub = @provider.on_accounts_changed(wallet, accounts => {
    seen.push(accounts.length())
  })
  inspect(mock_listener_count("accountsChanged"), content="1")
  emit_mock_event(
    "accountsChanged", "[\"0x1111111111111111111111111111111111111111\"]",
  )
  inspect(seen.length(), content="1")
  inspect(seen[0], content="1")
  sub.unsubscribe()
  inspect(mock_listener_count("accountsChanged"), content="0")
  emit_mock_event("accountsChanged", "[]")
  inspect(seen.length(), content="1")
  // cancelling twice must neither fail nor touch anyone else's listener
  sub.unsubscribe()
  uninstall_mock_ethereum()
}

///|
/// The other payload shape an event carries across the boundary: an object,
/// rather than the array `accountsChanged` sends. What each payload decodes
/// *into* is the provider layer's business and is tested there.
test "an object payload crosses the boundary" {
  install_mock_ethereum()
  let wallet = @browser.BrowserProvider::require() catch {
    e => fail("expected provider, but \{e}")
  }
  let errors = []
  let sub = @provider.on_disconnect(wallet, error => errors.push(error))
  emit_mock_event("disconnect", "{\"code\":4900,\"message\":\"gone\"}")
  inspect(errors[0], content="Disconnected")
  sub.unsubscribe()
  uninstall_mock_ethereum()
}

///|
test "subscribing to a wallet with no event API is inert, not fatal" {
  install_eventless_ethereum()
  let wallet = @browser.BrowserProvider::require() catch {
    e => fail("expected provider, but \{e}")
  }
  inspect(wallet.has_events(), content="false")
  let seen = []
  let sub = @provider.on_chain_changed(wallet, chain => seen.push(chain))
  sub.unsubscribe()
  inspect(seen.length(), content="0")
  uninstall_mock_ethereum()
}

///|
/// The event snippet from `README.md`, kept compiling: `moon test` does not
/// build markdown, so the README's example only stays honest by being mirrored
/// here.
fn watch(wallet : @browser.BrowserProvider) -> @provider.Subscription {
  // accountsChanged: the user switched account, or revoked the dapp's access
  let sub = @provider.on_accounts_changed(wallet, accounts => {
    match accounts.get(0) {
      Some(addr) => println("now \{addr}") // most recently selected first
      None => println("disconnected") // an empty array ⇒ permission revoked
    }
  })
  // chainChanged: everything read from the old chain is about another one now
  let _ = @provider.on_chain_changed(wallet, chain => {
    println("chain \{chain.to_hex()}")
  })
  // disconnect: a ProviderRpcError, mapped like any other wallet-side failure
  let _ = @provider.on_disconnect(wallet, error => println("gone: \{error}"))
  sub // `sub.unsubscribe()` stops that one handler; calling it twice is safe
}

///|
test "readme example compiles" {
  install_mock_ethereum()
  let wallet = @browser.BrowserProvider::require() catch {
    e => fail("expected provider, but \{e}")
  }
  watch(wallet).unsubscribe()
  uninstall_mock_ethereum()
}

///|
/// A wallet that only ever fails, counting the attempts. `-32005` is the node
/// behind it saying it is busy — retryable, unlike the `4001` the other fake
/// answers with.
extern "js" fn install_busy_ethereum() -> Unit =
  #| () => {
  #|   globalThis.__busyCalls = 0
  #|   globalThis.ethereum = {
  #|     request: async () => {
  #|       globalThis.__busyCalls += 1
  #|       throw { code: -32005, message: "limit exceeded" }
  #|     }
  #|   }
  #| }

///|
extern "js" fn busy_ethereum_calls() -> Int =
  #| () => globalThis.__busyCalls

///|
async test "a wallet retries on the policy it was given" {
  for
    case in [
      (@provider.RetryPolicy::none(), 1),
      (@provider.RetryPolicy::new(strategy=Immediate, max_retry=2), 3),
    ] {
    let (policy, expected) = case
    install_busy_ethereum()
    let wallet = (@browser.BrowserProvider::require() catch {
      e => fail("expected provider, but \{e}")
    }).with_retry(policy)
    @async.with_task_group(_ => {
      let _ = try
        wallet.request(method_name="eth_chainId", params=Json::array([]))
      catch {
        _ => ()
      } noraise {
        _ => fail("expected the busy wallet to raise")
      }
    })
    assert_eq(busy_ethereum_calls(), expected)
    uninstall_mock_ethereum()
  }
}
