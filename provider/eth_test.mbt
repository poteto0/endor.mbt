///|
/// The account every read test is run against. Parsing it cannot fail, so the
/// tests below spend no lines on the codec they are not exercising.
fn test_address() -> @types.Address {
  @types.Address::from_string("0x52908400098527886E0F7030069857D2E4169EE7") catch {
    e => abort("bad test address: \{e}")
  }
}

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
    let who = test_address()

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
    let who = test_address()

    let wei = @provider.balance(provider, who, block=Number(16)) catch {
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
    let who = test_address()

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
    let who = test_address()
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

///|
async test "can get block number" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_blockNumber",
      response="0x14f1e60".to_json(),
    )

    let n = @provider.block_number(provider) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(n, 21962336)
    assert_eq(provider.last_call(), Some(("eth_blockNumber", Json::array([]))))
  })
}

///|
async test "error invalid block number" {
  @async.with_task_group(_ => {
    // not a hex quantity
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_blockNumber",
      response="invalid".to_json(),
    )

    try @provider.block_number(provider) catch {
      @provider.ProviderError::Rpc(code~, ..) => assert_eq(code, -32603)
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    // a JSON number, not the hex string the RPC promises
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_blockNumber",
      response=Json::number(0),
    )

    try @provider.block_number(provider) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "can get transaction count" {
  @async.with_task_group(_ => {
    let who = test_address()
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionCount",
      response="0x2a".to_json(),
    )

    let nonce = @provider.transaction_count(provider, who) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(nonce, 42)
    // the default block tag reaches the wallet as "latest"
    assert_eq(
      provider.last_call(),
      Some(
        (
          "eth_getTransactionCount",
          Json::array([who.to_json(), Json::string("latest")]),
        ),
      ),
    )

    // an explicit tag replaces it
    let nonce = @provider.transaction_count(provider, who, block=Pending) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(nonce, 42)
    assert_eq(
      provider.last_call(),
      Some(
        (
          "eth_getTransactionCount",
          Json::array([who.to_json(), Json::string("pending")]),
        ),
      ),
    )
  })
}

///|
async test "error invalid transaction count" {
  @async.with_task_group(_ => {
    let who = test_address()
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionCount",
      response="0x10000000000000000".to_json(),
    )

    try @provider.transaction_count(provider, who) catch {
      @provider.ProviderError::Rpc(code~, ..) => assert_eq(code, -32603)
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A wallet-side rejection reaches the caller as-is, not as an internal decode
/// error.
async test "error transaction count rejected by wallet" {
  @async.with_task_group(_ => {
    let who = test_address()
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_getTransactionCount",
      error=@provider.ProviderError::UserRejected,
    )

    try @provider.transaction_count(provider, who) catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "can get gas price" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_gasPrice",
      response="0x3b9aca00".to_json(),
    )

    let price = @provider.gas_price(provider) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(price, @types.Wei::from_bigint(1000000000N))
    assert_eq(provider.last_call(), Some(("eth_gasPrice", Json::array([]))))
  })
}

///|
async test "error invalid gas price" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_gasPrice",
      response=Json::number(0),
    )

    try @provider.gas_price(provider) catch {
      @provider.ProviderError::Rpc(code~, ..) => assert_eq(code, -32603)
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "error gas price rejected by wallet" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_gasPrice",
      error=@provider.ProviderError::Disconnected,
    )

    try @provider.gas_price(provider) catch {
      @provider.ProviderError::Disconnected => ()
      e => fail("expected Disconnected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "can get code" {
  @async.with_task_group(_ => {
    let who = test_address()
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response="0x60806040".to_json(),
    )

    let bytecode = @provider.code(provider, who) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(bytecode.to_string(), "0x60806040")
    assert_eq(
      provider.last_call(),
      Some(
        ("eth_getCode", Json::array([who.to_json(), Json::string("latest")])),
      ),
    )

    // an externally owned account answers with no bytes at all
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response="0x".to_json(),
    )

    let bytecode = @provider.code(provider, who, block=Number(16)) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(bytecode.to_string(), "0x")
    assert_eq(
      provider.last_call(),
      Some(("eth_getCode", Json::array([who.to_json(), Json::string("0x10")]))),
    )
  })
}

///|
async test "error invalid code" {
  @async.with_task_group(_ => {
    let who = test_address()

    // an odd number of hex digits is not a whole number of bytes
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response="0x608".to_json(),
    )

    try @provider.code(provider, who) catch {
      @provider.ProviderError::Rpc(code~, ..) => assert_eq(code, -32603)
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response=Json::number(0),
    )

    try @provider.code(provider, who) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// `is_contract` is `code` with an emptiness test, so it reads the same call
/// and propagates the same errors.
async test "can tell a contract from a wallet" {
  @async.with_task_group(_ => {
    let who = test_address()
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response="0x60806040".to_json(),
    )

    let yes = @provider.is_contract(provider, who) catch {
      e => fail("unexpected error \{e}")
    }

    assert_true(yes)

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response="0x".to_json(),
    )

    let no = @provider.is_contract(provider, who, block=Finalized) catch {
      e => fail("unexpected error \{e}")
    }

    assert_false(no)
    assert_eq(
      provider.last_call(),
      Some(
        ("eth_getCode", Json::array([who.to_json(), Json::string("finalized")])),
      ),
    )
  })
}

///|
async test "error is_contract rejected by wallet" {
  @async.with_task_group(_ => {
    let who = test_address()
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_getCode",
      error=@provider.ProviderError::Unauthorized,
    )

    try @provider.is_contract(provider, who) catch {
      @provider.ProviderError::Unauthorized => ()
      e => fail("expected Unauthorized, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// The block tag is what the caller passed, all the way to the wire.
async test "can get balance at a named block tag" {
  @async.with_task_group(_ => {
    let who = test_address()
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getBalance",
      response="0xff".to_json(),
    )

    let wei = @provider.balance(provider, who, block=Pending) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(wei, @types.Wei::from_int(255))
    assert_eq(
      provider.last_call(),
      Some(
        (
          "eth_getBalance",
          Json::array([who.to_json(), Json::string("pending")]),
        ),
      ),
    )
  })
}
