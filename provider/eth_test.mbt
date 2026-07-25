///|
async test "can get accounts" {
  let accounts = []
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_requestAccounts",
      response=Json::array([
        "0x52908400098527886E0F7030069857D2E4169EE7".to_json(),
      ]),
    )

    let acc = @provider.request_accounts(provider) catch {
      e => fail("unexpected error \{e}")
    }

    for a in acc {
      accounts.push(a)
    }

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_requestAccounts",
      response=Json::array([
        "0x52908400098527886E0F7030069857D2E4169EE7".to_json(),
        "0x52908400098527886E0F7030069857D2E4169EE8".to_json(),
      ]),
    )

    let acc = @provider.request_accounts(provider) catch {
      e => fail("unexpected error \{e}")
    }

    for a in acc {
      accounts.push(a)
    }
  })

  assert_eq(accounts.length(), 3)
}

///|
async test "error invalid accounts" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_requestAccounts",
      response="0x52908400098527886E0F7030069857D2E4169EE7".to_json(),
    )

    try @provider.request_accounts(provider) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_requestAccounts",
      response=Json::array(["invalid".to_json()]),
    )

    try @provider.request_accounts(provider) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "can get chain id" {
  let chain_ids = []

  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_chainId",
      response="0x1".to_json(),
    )

    let id = @provider.chain_id(provider) catch {
      e => fail("unexpected error \{e}")
    }

    chain_ids.push(id)

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_chainId",
      response="0x89".to_json(),
    )

    let id = @provider.chain_id(provider) catch {
      e => fail("unexpected error \{e}")
    }

    chain_ids.push(id)
  })

  assert_eq(chain_ids.length(), 2)
}

///|
async test "can get accounts without prompt" {
  let accounts = []

  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_accounts",
      response=Json::array([]),
    )

    let acc = @provider.accounts(provider) catch {
      e => fail("unexpected error \{e}")
    }

    for a in acc {
      accounts.push(a)
    }

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_accounts",
      response=Json::array([
        "0x52908400098527886E0F7030069857D2E4169EE7".to_json(),
        "0x52908400098527886E0F7030069857D2E4169EE8".to_json(),
      ]),
    )

    let acc = @provider.accounts(provider) catch {
      e => fail("unexpected error \{e}")
    }

    for a in acc {
      accounts.push(a)
    }
  })

  assert_eq(accounts.length(), 2)
}

///|
async test "error invalid accounts response" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_accounts",
      response="invalid".to_json(),
    )

    try @provider.accounts(provider) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_accounts",
      response=Json::array(["invalid".to_json()]),
    )

    try @provider.accounts(provider) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "can get balance" {
  let balances = []

  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getBalance",
      response="0x1bc16d674ec80000".to_json(),
    )
    let who = @types.Address::from_string(
      "0x52908400098527886E0F7030069857D2E4169EE7",
    ) catch {
      e => fail("unexpected error \{e}")
    }

    let wei = @provider.balance(provider, who) catch {
      e => fail("unexpected error \{e}")
    }

    balances.push(wei)

    // the address and the default block tag reach the wallet as sent
    assert_eq(
      provider.last_call(),
      Some(
        ("eth_getBalance", Json::array([who.to_json(), Json::string("latest")])),
      ),
    )

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getBalance",
      response="0x0".to_json(),
    )

    let wei = @provider.balance(provider, who) catch {
      e => fail("unexpected error \{e}")
    }

    balances.push(wei)
  })

  assert_eq(balances.length(), 2)
  assert_eq(balances[0], @types.Wei::from_bigint(2000000000000000000N))
  assert_eq(balances[1], @types.Wei::zero())
}

///|
async test "can get balance at an explicit block" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getBalance",
      response="0xff".to_json(),
    )
    let who = @types.Address::from_string(
      "0x52908400098527886E0F7030069857D2E4169EE7",
    ) catch {
      e => fail("unexpected error \{e}")
    }

    let wei = @provider.balance(provider, who, block="0x10") catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(wei, @types.Wei::from_int(255))
    assert_eq(
      provider.last_call(),
      Some(
        ("eth_getBalance", Json::array([who.to_json(), Json::string("0x10")])),
      ),
    )
  })
}

///|
async test "error invalid balance" {
  @async.with_task_group(_ => {
    let who = @types.Address::from_string(
      "0x52908400098527886E0F7030069857D2E4169EE7",
    ) catch {
      e => fail("unexpected error \{e}")
    }

    // not a hex quantity
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getBalance",
      response="invalid".to_json(),
    )

    try @provider.balance(provider, who) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    // a JSON number, not the hex string the RPC promises
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getBalance",
      response=Json::number(0),
    )

    try @provider.balance(provider, who) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A wallet-side rejection reaches the caller as-is, not as an internal decode
/// error.
async test "error balance rejected by wallet" {
  @async.with_task_group(_ => {
    let who = @types.Address::from_string(
      "0x52908400098527886E0F7030069857D2E4169EE7",
    ) catch {
      e => fail("unexpected error \{e}")
    }
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_getBalance",
      error=@provider.ProviderError::Unauthorized,
    )

    try @provider.balance(provider, who) catch {
      @provider.ProviderError::Unauthorized => ()
      e => fail("expected Unauthorized, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "error invalid chain id" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_chainId",
      response="invalid".to_json(),
    )

    try @provider.chain_id(provider) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}
