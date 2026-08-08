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

    inspect(result.stringify(), content="\"0x1\"")

    let calls = provider.calls()
    inspect(calls.length(), content="1")

    match calls[0] {
      (eth_method, params) => {
        inspect(eth_method, content="eth_chainId")
        inspect(params.stringify(), content="[]")
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
      @provider.InvalidConfig(_) => ()
      e => fail("expected a missing-response error, but not \{e}")
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

    inspect(provider.calls().length(), content="2")

    match provider.calls()[0] {
      (eth_method, _) => inspect(eth_method, content="eth_chainId")
    }

    match provider.calls()[1] {
      (eth_method, _) => inspect(eth_method, content="eth_accounts")
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
        inspect(eth_method, content="eth_chainId")
        inspect(params.stringify(), content="[]")
      }
      None => fail("expected last call")
    }
  })
}
