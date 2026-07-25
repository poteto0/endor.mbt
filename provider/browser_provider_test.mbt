///|
/// Install a fake window.ethereum provider for tests.
extern "js" fn install_mock_ethereum() -> Unit =
  #| () => {
  #|   globalThis.ethereum = {
  #|     isMetaMask: true,
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

  let provider = @provider.BrowserProvider::detect()

  inspect(provider is Some(_), content="true")

  let provider = @provider.BrowserProvider::require() catch {
    e => fail("expected success, but \{e}")
  }

  inspect(provider.is_metamask(), content="true")

  uninstall_mock_ethereum()
}

///|
test "detect none when wallet doesn't exists" {
  let provider = @provider.BrowserProvider::detect()

  inspect(provider is Some(_), content="false")

  let _ = try @provider.BrowserProvider::require() catch {
    @provider.NotInstalled(_) => ()
    e => fail("expected not installed, but \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
async test "request returns accounts" {
  install_mock_ethereum()

  let provider = match @provider.BrowserProvider::detect() {
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

  let provider = @provider.BrowserProvider::require() catch {
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

  let provider = @provider.BrowserProvider::require() catch {
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
