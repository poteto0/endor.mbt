///|
async test "mock provider returns canned response" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_chainId",
      response="0x1".to_json(),
    )

    let result = provider.request(
      method_name="eth_chainId",
      params=Json::array([]),
    ) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(result, "0x1".to_json())

    let calls = provider.calls()
    assert_eq(calls.length(), 1)

    match calls[0] {
      (eth_method, params) => {
        assert_eq(eth_method, "eth_chainId")
        assert_eq(params, Json::array([]))
      }
    }
  })
}

///|
async test "mock provider errors for unknown method" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new()

    try
      provider.request(method_name="eth_unknown", params=Json::array([]))
    catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected rpc error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "mock provider returns registered error" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_requestAccounts",
      error=@provider.ProviderError::UserRejected,
    )

    try
      provider.request(
        method_name="eth_requestAccounts",
        params=Json::array([]),
      )
    catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected user rejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "mock provider records calls in order" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new()
      .on(method_name="eth_chainId", response="0x1".to_json())
      .on(method_name="eth_accounts", response=Json::array([]))

    let _ = provider.request(method_name="eth_chainId", params=Json::array([])) catch {
      e => fail("unexpected error \{e}")
    }

    let _ = provider.request(method_name="eth_accounts", params=Json::array([])) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(provider.calls().length(), 2)

    match provider.calls()[0] {
      (eth_method, _) => assert_eq(eth_method, "eth_chainId")
    }

    match provider.calls()[1] {
      (eth_method, _) => assert_eq(eth_method, "eth_accounts")
    }
  })
}

///|
async test "mock provider returns last call" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_chainId",
      response="0x1".to_json(),
    )

    let before = provider.last_call()
    match before {
      None => ()
      Some(_) => fail("expected no last call")
    }

    let _ = provider.request(method_name="eth_chainId", params=Json::array([])) catch {
      e => fail("unexpected error \{e}")
    }

    match provider.last_call() {
      Some((eth_method, params)) => {
        assert_eq(eth_method, "eth_chainId")
        assert_eq(params, Json::array([]))
      }
      None => fail("expected last call")
    }
  })
}
