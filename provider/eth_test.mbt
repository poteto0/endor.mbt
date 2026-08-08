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

  inspect(accounts.length(), content="3")
}

///|
async test "require first account" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_requestAccounts",
      response=Json::array([
        "0x52908400098527886E0F7030069857D2E4169EE7".to_json(),
      ]),
    )

    let acc = @provider.require_account(provider) catch {
      e => fail("unexpected error \{e}")
    }

    inspect(acc, content="0x52908400098527886E0F7030069857D2E4169EE7")
  })

  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_requestAccounts",
      response=Json::array([]),
    )

    try ignore(@provider.require_account(provider)) catch {
      _ => ()
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "error invalid accounts" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_requestAccounts",
      response="0x52908400098527886E0F7030069857D2E4169EE7".to_json(),
    )

    try @provider.request_accounts(provider) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_requestAccounts",
      response=Json::array(["invalid".to_json()]),
    )

    try @provider.request_accounts(provider) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
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

  inspect(chain_ids.length(), content="2")
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

  inspect(accounts.length(), content="2")
}

///|
async test "error invalid accounts response" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_accounts",
      response="invalid".to_json(),
    )

    try @provider.accounts(provider) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_accounts",
      response=Json::array(["invalid".to_json()]),
    )

    try @provider.accounts(provider) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
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
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_getBalance",
        #|    Array(
        #|      [
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|        String("latest"),
        #|      ],
        #|    ),
        #|  ),
        #|)
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

  inspect(balances.length(), content="2")
  inspect(balances[0], content="Wei(2000000000000000000)")
  inspect(balances[1], content="Wei(0)")
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

    inspect(wei, content="Wei(255)")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_getBalance",
        #|    Array([String("0x52908400098527886e0f7030069857d2e4169ee7"), String("0x10")]),
        #|  ),
        #|)
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
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    // a JSON number, not the hex string the RPC promises
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getBalance",
      response=Json::number(0),
    )

    try @provider.balance(provider, who) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
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
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
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

    inspect(n, content="21962336")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(("eth_blockNumber", Array([])))
      ),
    )
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
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    // a JSON number, not the hex string the RPC promises
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_blockNumber",
      response=Json::number(0),
    )

    try @provider.block_number(provider) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
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

    inspect(nonce, content="42")
    // the default block tag reaches the wallet as "latest"
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_getTransactionCount",
        #|    Array(
        #|      [
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|        String("latest"),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )

    // an explicit tag replaces it
    let nonce = @provider.transaction_count(provider, who, block=Pending) catch {
      e => fail("unexpected error \{e}")
    }

    inspect(nonce, content="42")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_getTransactionCount",
        #|    Array(
        #|      [
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|        String("pending"),
        #|      ],
        #|    ),
        #|  ),
        #|)
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
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
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

    inspect(price, content="Wei(1000000000)")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(("eth_gasPrice", Array([])))
      ),
    )
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
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
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

    inspect(bytecode.to_string(), content="0x60806040")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_getCode",
        #|    Array(
        #|      [
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|        String("latest"),
        #|      ],
        #|    ),
        #|  ),
        #|)
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

    inspect(bytecode.to_string(), content="0x")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_getCode",
        #|    Array([String("0x52908400098527886e0f7030069857d2e4169ee7"), String("0x10")]),
        #|  ),
        #|)
      ),
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
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response=Json::number(0),
    )

    try @provider.code(provider, who) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
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

    inspect(yes, content="true")

    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response="0x".to_json(),
    )

    let no = @provider.is_contract(provider, who, block=Finalized) catch {
      e => fail("unexpected error \{e}")
    }

    inspect(no, content="false")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_getCode",
        #|    Array(
        #|      [
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|        String("finalized"),
        #|      ],
        #|    ),
        #|  ),
        #|)
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

    inspect(wei, content="Wei(255)")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_getBalance",
        #|    Array(
        #|      [
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|        String("pending"),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
/// A call to `test_address()` carrying calldata, which is the shape every test
/// below sends.
fn call_request() -> @types.CallRequest {
  let data = @types.Hex::from_string("0x70a08231") catch {
    e => abort("bad test calldata: \{e}")
  }
  @types.CallRequest::new(test_address(), data~)
}

///|
async test "can call" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response="0x00000000000000000000000000000000000000000000000000000000000003e8".to_json(),
    )
    // every field the caller filled in, so the whole call object is pinned
    let req = @types.CallRequest::new(
      test_address(),
      from=test_address(),
      data=@types.Hex::from_string("0x70a08231") catch {
        e => abort("bad test calldata: \{e}")
      },
      value=@types.Wei::from_int(1),
    )

    let ret = @provider.call(provider, req) catch {
      e => fail("unexpected error \{e}")
    }

    inspect(
      ret.to_string(),
      content="0x00000000000000000000000000000000000000000000000000000000000003e8",
    )
    // the call object and the default block tag reach the node as sent
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_call",
        #|    Array(
        #|      [
        #|        Object(
        #|          {
        #|            "to": String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|            "from": String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|            "data": String("0x70a08231"),
        #|            "value": String("0x1"),
        #|          },
        #|        ),
        #|        String("latest"),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )

    // an explicit tag replaces the default
    let ret = @provider.call(provider, req, block=Number(16)) catch {
      e => fail("unexpected error \{e}")
    }

    inspect(ret.byte_length(), content="32")
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_call",
        #|    Array(
        #|      [
        #|        Object(
        #|          {
        #|            "to": String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|            "from": String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|            "data": String("0x70a08231"),
        #|            "value": String("0x1"),
        #|          },
        #|        ),
        #|        String("0x10"),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
/// A view function returning nothing answers with no bytes at all, which is a
/// valid `Hex`, not an error.
async test "can call with an empty answer" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response="0x".to_json(),
    )

    let ret = @provider.call(provider, call_request()) catch {
      e => fail("unexpected error \{e}")
    }

    inspect(ret.is_empty(), content="true")
  })
}

///|
async test "error invalid call result" {
  @async.with_task_group(_ => {
    // an odd number of hex digits is not a whole number of bytes
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response="0x3e8".to_json(),
    )

    try @provider.call(provider, call_request()) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    // a JSON number, not the hex string the RPC promises
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response=Json::number(0),
    )

    try @provider.call(provider, call_request()) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A revert is answered by the node as an error, so it reaches the caller as the
/// `ProviderError` it mapped to — not as an internal decode error.
async test "error call reverted" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_call",
      error=@provider.ProviderError::Rpc(code=3, message="execution reverted"),
    )

    try @provider.call(provider, call_request()) catch {
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="3")
      e => fail("expected an rpc error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "can estimate gas" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_estimateGas",
      response="0x5208".to_json(),
    )
    let req = call_request()

    let gas = @provider.estimate_gas(provider, req) catch {
      e => fail("unexpected error \{e}")
    }

    inspect(gas, content="Quantity(21000)")
    // no block parameter: the estimate is against current state
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_estimateGas",
        #|    Array(
        #|      [
        #|        Object(
        #|          {
        #|            "to": String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|            "data": String("0x70a08231"),
        #|          },
        #|        ),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
async test "error invalid gas estimate" {
  @async.with_task_group(_ => {
    // a value too large for the 64 bits a gas amount fits in
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_estimateGas",
      response="0x10000000000000000".to_json(),
    )

    try @provider.estimate_gas(provider, call_request()) catch {
      @provider.Decode(..) => ()
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// Estimating a call the node cannot execute fails, which is what makes this a
/// cheap pre-flight check before asking the user to sign.
async test "error gas estimate reverted" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_estimateGas",
      error=@provider.ProviderError::Rpc(code=3, message="execution reverted"),
    )

    try @provider.estimate_gas(provider, call_request()) catch {
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="3")
      e => fail("expected an rpc error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A transaction from `test_address()` to itself, which is the shape the
/// send tests below broadcast.
fn transaction_request() -> @types.TransactionRequest {
  @types.TransactionRequest::new(
    test_address(),
    to=test_address(),
    value=@types.Wei::from_int(1000),
  )
}

///|
const TX_HASH : String = "0x88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a713944b"

///|
async test "can send a transaction" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_sendTransaction",
      response=TX_HASH.to_json(),
    )
    let req = transaction_request()

    let hash = @provider.send_transaction(provider, req) catch {
      e => fail("unexpected error \{e}")
    }

    inspect(hash.to_string(), content=TX_HASH)
    // one params element, the transaction object itself
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_sendTransaction",
        #|    Array(
        #|      [
        #|        Object(
        #|          {
        #|            "from": String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|            "to": String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|            "value": String("0x3e8"),
        #|          },
        #|        ),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
/// Declining the wallet prompt is the expected outcome of a send, not an
/// exceptional one: it has to arrive as `UserRejected` rather than as a
/// generic RPC error, so callers can tell "the user said no" from "the node
/// said no".
async test "error send rejected by the user" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_sendTransaction",
      error=@provider.ProviderError::from_code(4001, "user rejected"),
    )

    try @provider.send_transaction(provider, transaction_request()) catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A wallet answering with something that is not a 32-byte hash surfaces as
/// `Decode`, naming the method that answered, rather than as a `TxHash` nobody
/// can use.
async test "error send answered with a malformed hash" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_sendTransaction",
      response="0xdeadbeef".to_json(),
    )

    try @provider.send_transaction(provider, transaction_request()) catch {
      @provider.Decode(method_name~, ..) =>
        inspect(method_name, content="eth_sendTransaction")
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// The EIP-712 document a `Permit` is signed as, trimmed to the fields every
/// typed-data signature carries. What the document may and may not say is
/// covered in `types/`; here it is only a payload the RPC layer has to
/// serialize and pass through unchanged.
fn permit_typed_data() -> @eip712.TypedData {
  @eip712.TypedData::new(
    @eip712.TypedDataDomain::new(
      name="Endor",
      chain_id=@types.ChainId::mainnet(),
    ),
    primary_type="Permit",
    types={
      "Permit": [
        @eip712.TypedDataField::new("holder", "address"),
        @eip712.TypedDataField::new("value", "uint256"),
      ],
    },
    message={
      "holder": "0x52908400098527886e0f7030069857d2e4169ee7",
      "value": Json::number(1),
    },
  ) catch {
    e => abort("bad test document: \{e}")
  }
}

///|
async test "can sign typed data" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_signTypedData_v4",
      response=Json::string("0x" + "cd".repeat(65)),
    )
    let signature = @provider.sign_typed_data(
      provider,
      test_address(),
      permit_typed_data(),
    ) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(signature.byte_length(), content="65")

    // the account first, and the document serialized: v4 takes a string
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_signTypedData_v4",
        #|    Array(
        #|      [
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|        String("{\"types\":{\"EIP712Domain\":[{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"chainId\",\"type\":\"uint256\"}],\"Permit\":[{\"name\":\"holder\",\"type\":\"address\"},{\"name\":\"value\",\"type\":\"uint256\"}]},\"primaryType\":\"Permit\",\"domain\":{\"name\":\"Endor\",\"chainId\":1},\"message\":{\"holder\":\"0x52908400098527886e0f7030069857d2e4169ee7\",\"value\":1}}"),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
async test "error sign typed data rejected by user" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_signTypedData_v4",
      error=@provider.ProviderError::UserRejected,
    )
    try
      @provider.sign_typed_data(provider, test_address(), permit_typed_data())
    catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A wallet that does not know `eth_signTypedData_v4` at all answers 4200, and
/// that too propagates untouched.
async test "error sign typed data unsupported by the wallet" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_signTypedData_v4",
      error=@provider.ProviderError::UnsupportedMethod,
    )
    try
      @provider.sign_typed_data(provider, test_address(), permit_typed_data())
    catch {
      @provider.ProviderError::UnsupportedMethod => ()
      e => fail("expected UnsupportedMethod, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// The EIP-1967 implementation slot, the one storage read that has a standard
/// address behind it.
const IMPL_SLOT : String = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

///|
/// The three parameters go out in the order the RPC names them — account, slot,
/// block — and the word comes back untouched, since nothing here knows what a
/// slot holds.
async test "storage is read at a slot and a block" {
  @async.with_task_group(_ => {
    let word = "0x000000000000000000000000ce4a1e86a5c47cd677338f53da22a91d85e5b5b1"
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getStorageAt",
      response=word.to_json(),
    )
    let slot = @types.Hex::from_string(IMPL_SLOT) catch {
      e => fail("bad test slot: \{e}")
    }
    let read = @provider.storage_at(provider, test_address(), slot) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(read, content=word)
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_getStorageAt")
    inspect(
      params.stringify(),
      content="[\"0x52908400098527886e0f7030069857d2e4169ee7\",\"\{IMPL_SLOT}\",\"latest\"]",
    )
    let _ = @provider.storage_at(
      provider,
      test_address(),
      slot,
      block=Number(436),
    ) catch {
      e => fail("unexpected error \{e}")
    }
    guard provider.last_call() is Some((_, params)) else {
      fail("expected a call")
    }
    assert_true(params.stringify().has_suffix("\"0x1b4\"]"))
  })
}

///|
/// A slot nobody ever wrote is thirty-two zero bytes, not an absence — so it
/// decodes like any other word.
async test "an unwritten slot reads as zero" {
  @async.with_task_group(_ => {
    let zero = "0x0000000000000000000000000000000000000000000000000000000000000000"
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_getStorageAt",
      response=zero.to_json(),
    )
    let slot = @types.Hex::from_string("0x00") catch {
      e => fail("bad test slot: \{e}")
    }
    let read = @provider.storage_at(provider, test_address(), slot) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(read.byte_length(), content="32")
    inspect(read, content=zero)
  })
}

///|
/// Nothing about this call goes through a wallet: the transaction arrives
/// signed, and all the SDK does is hand it over and read the hash back.
async test "a signed transaction is broadcast raw" {
  @async.with_task_group(_ => {
    let raw = "0x02f8710182031184773594008504a817c80082520894"
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_sendRawTransaction",
      response=TX_HASH.to_json(),
    )
    let signed = @types.Hex::from_string(raw) catch {
      e => fail("bad test payload: \{e}")
    }
    let hash = @provider.send_raw_transaction(provider, signed) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(hash, content=TX_HASH)
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_sendRawTransaction")
    inspect(params.stringify(), content="[\"\{raw}\"]")
  })
}

///|
/// A raw transaction the node refuses — a bad signature, a nonce already used,
/// a fee below the minimum — is the node's error and propagates untouched.
async test "error a raw transaction the node rejects" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_sendRawTransaction",
      error=@provider.ProviderError::Rpc(code=-32000, message="nonce too low"),
    )
    let signed = @types.Hex::from_string("0x02f871") catch {
      e => fail("bad test payload: \{e}")
    }
    try @provider.send_raw_transaction(provider, signed) catch {
      @provider.ProviderError::Rpc(code~, message~) => {
        inspect(code, content="-32000")
        inspect(message, content="nonce too low")
      }
      e => fail("expected an rpc error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A block header as a node answers it when asked for transaction hashes.
fn a_block() -> Json {
  {
    "number": "0x1b4".to_json(),
    "hash": A_BLOCK.to_json(),
    "parentHash": A_BLOCK.to_json(),
    "timestamp": "0x687fbc00".to_json(),
    "miner": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266".to_json(),
    "gasLimit": "0x1c9c380".to_json(),
    "gasUsed": "0x5208".to_json(),
    "baseFeePerGas": "0x3b9aca00".to_json(),
    "transactions": Json::array([TX_HASH.to_json()]),
  }
}

///|
/// The `false` is the SDK asking for transaction hashes rather than full
/// objects, which is what `Block::transactions` is typed for.
async test "a block is read at a tag, asking for hashes" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getBlockByNumber",
      response=a_block(),
    )
    let block = @provider.block_by_number(provider) catch {
      e => fail("unexpected error \{e}")
    }
    guard block is Some(block) else { fail("expected a block") }
    inspect(block.transactions[0], content=TX_HASH)
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_getBlockByNumber")
    inspect(params.stringify(), content="[\"latest\",false]")
    let _ = @provider.block_by_number(provider, block=Number(436)) catch {
      e => fail("unexpected error \{e}")
    }
    guard provider.last_call() is Some((_, params)) else {
      fail("expected a call")
    }
    inspect(params.stringify(), content="[\"0x1b4\",false]")
  })
}

///|
async test "a block is read by hash" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getBlockByHash",
      response=a_block(),
    )
    let hash = @types.BlockHash::from_string(A_BLOCK) catch {
      e => fail("bad test hash: \{e}")
    }
    let block = @provider.block_by_hash(provider, hash) catch {
      e => fail("unexpected error \{e}")
    }
    guard block is Some(block) else { fail("expected a block") }
    guard block.number is Some(number) else { fail("expected a block number") }
    inspect(number, content="436")
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_getBlockByHash")
    inspect(params.stringify(), content="[\"\{A_BLOCK}\",false]")
  })
}

///|
/// A height past the head, or a hash from another chain, is answered with
/// `null` rather than an error — so it reads as `None`, not as a failure.
async test "a block the node does not know reads as none" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
      .on(method_name="eth_getBlockByNumber", response=Json::null())
      .on(method_name="eth_getBlockByHash", response=Json::null())
    let hash = @types.BlockHash::from_string(A_BLOCK) catch {
      e => fail("bad test hash: \{e}")
    }
    let by_number = @provider.block_by_number(
      provider,
      block=Number(999_999_999),
    ) catch {
      e => fail("unexpected error \{e}")
    }
    assert_true(by_number is None)
    let by_hash = @provider.block_by_hash(provider, hash) catch {
      e => fail("unexpected error \{e}")
    }
    assert_true(by_hash is None)
  })
}

///|
async test "a malformed block is the SDK's own error" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getBlockByNumber",
      response=Json::empty_object(),
    )
    try @provider.block_by_number(provider) catch {
      @provider.Decode(method_name~, ..) =>
        inspect(method_name, content="eth_getBlockByNumber")
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected a malformed block to be rejected")
    }
  })
}

///|
/// The cheap form of the same question `block_by_number` answers: the node is
/// asked for the count alone, so only the block parameter goes out.
async test "a block's transaction count is read by number and by hash" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
      .on(
        method_name="eth_getBlockTransactionCountByNumber",
        response="0x2a".to_json(),
      )
      .on(
        method_name="eth_getBlockTransactionCountByHash",
        response="0x1".to_json(),
      )
    let by_number = @provider.block_transaction_count_by_number(provider) catch {
      e => fail("unexpected error \{e}")
    }
    assert_eq(by_number, Some(42UL))
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_getBlockTransactionCountByNumber")
    inspect(params.stringify(), content="[\"latest\"]")
    let hash = @types.BlockHash::from_string(A_BLOCK) catch {
      e => fail("bad test hash: \{e}")
    }
    let by_hash = @provider.block_transaction_count_by_hash(provider, hash) catch {
      e => fail("unexpected error \{e}")
    }
    assert_eq(by_hash, Some(1UL))
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_getBlockTransactionCountByHash")
    inspect(params.stringify(), content="[\"\{A_BLOCK}\"]")
  })
}

///|
/// Absence is reported the same way it is for the block itself: a node that
/// does not have the block answers `null`, and that is `None` rather than 0 —
/// which is a real count, and a different fact.
async test "the count of a block the node does not know reads as none" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
      .on(
        method_name="eth_getBlockTransactionCountByNumber",
        response=Json::null(),
      )
      .on(
        method_name="eth_getBlockTransactionCountByHash",
        response=Json::null(),
      )
    let hash = @types.BlockHash::from_string(A_BLOCK) catch {
      e => fail("bad test hash: \{e}")
    }
    let by_number = @provider.block_transaction_count_by_number(
      provider,
      block=Number(999_999_999),
    ) catch {
      e => fail("unexpected error \{e}")
    }
    assert_true(by_number is None)
    let by_hash = @provider.block_transaction_count_by_hash(provider, hash) catch {
      e => fail("unexpected error \{e}")
    }
    assert_true(by_hash is None)
  })
}

///|
const A_BLOCK : String = "0xb6de5c3c1b70d24de3ea4eb90a6c9f1f5eb1d0e6a5e3b3f1b7e0c0b9a8d7c6e5"

///|
fn test_tx_hash() -> @types.TxHash {
  @types.TxHash::from_string(TX_HASH) catch {
    e => abort("bad test hash: \{e}")
  }
}

///|
/// A receipt mined into block `0x1b4`, as a node would answer it.
fn a_receipt() -> Json {
  {
    "transactionHash": TX_HASH.to_json(),
    "transactionIndex": "0x0".to_json(),
    "blockHash": A_BLOCK.to_json(),
    "blockNumber": "0x1b4".to_json(),
    "from": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266".to_json(),
    "to": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8".to_json(),
    "contractAddress": Json::null(),
    "cumulativeGasUsed": "0x5208".to_json(),
    "gasUsed": "0x5208".to_json(),
    "effectiveGasPrice": "0x3b9aca00".to_json(),
    "status": "0x1".to_json(),
    "logs": Json::array([]),
  }
}

///|
/// The same transaction as `a_receipt()`, as `eth_getTransactionByHash`
/// reports it: still pending, so the three fields that would place it in a
/// block are `null`.
fn a_pending_transaction() -> Json {
  {
    "hash": TX_HASH.to_json(),
    "blockHash": Json::null(),
    "blockNumber": Json::null(),
    "transactionIndex": Json::null(),
    "from": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266".to_json(),
    "to": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8".to_json(),
    "nonce": "0x7".to_json(),
    "value": "0xde0b6b3a7640000".to_json(),
    "input": "0x".to_json(),
    "gas": "0x5208".to_json(),
    "maxFeePerGas": "0x77359400".to_json(),
    "maxPriorityFeePerGas": "0x3b9aca00".to_json(),
  }
}

///|
/// The state `transaction_receipt` cannot report at all. Which fields decode
/// into what is `types`' business; what this asserts is that the read reaches
/// the right method and that a pending transaction comes back as one.
async test "a transaction is readable while it is still pending" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionByHash",
      response=a_pending_transaction(),
    )
    let tx = @provider.transaction_by_hash(provider, test_tx_hash()) catch {
      e => fail("unexpected error \{e}")
    }
    guard tx is Some(tx) else { fail("expected a transaction") }
    inspect(tx.inclusion, content="Pending")
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_getTransactionByHash")
    inspect(params.stringify(), content="[\"\{TX_HASH}\"]")
  })
}

///|
/// A hash the node has never seen is `null`, and that is not the same fact as
/// a transaction it is holding in its mempool.
async test "an unknown hash reads as no transaction at all" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionByHash",
      response=Json::null(),
    )
    let tx = @provider.transaction_by_hash(provider, test_tx_hash()) catch {
      e => fail("unexpected error \{e}")
    }
    assert_true(tx is None)
  })
}

///|
async test "a malformed transaction is the SDK's own error" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionByHash",
      response=Json::array([]),
    )
    try @provider.transaction_by_hash(provider, test_tx_hash()) catch {
      @provider.Decode(method_name~, ..) =>
        inspect(method_name, content="eth_getTransactionByHash")
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected a malformed transaction to be rejected")
    }
  })
}

///|
async test "a mined transaction has a receipt, asked for by hash" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionReceipt",
      response=a_receipt(),
    )
    let receipt = @provider.transaction_receipt(provider, test_tx_hash()) catch {
      e => fail("unexpected error \{e}")
    }
    guard receipt is Some(receipt) else { fail("expected a receipt") }
    inspect(receipt.block_number, content="436")
    inspect(receipt.status, content="Success")
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_getTransactionReceipt")
    inspect(params.stringify(), content="[\"\{TX_HASH}\"]")
  })
}

///|
/// The `null` a node answers for a transaction it has not mined is not an
/// error: it is the absence a caller polls through.
async test "an unmined transaction reads as no receipt at all" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionReceipt",
      response=Json::null(),
    )
    let receipt = @provider.transaction_receipt(provider, test_tx_hash()) catch {
      e => fail("unexpected error \{e}")
    }
    assert_true(receipt is None)
  })
}

///|
async test "a malformed receipt is the SDK's own error" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionReceipt",
      response=Json::array([]),
    )
    try @provider.transaction_receipt(provider, test_tx_hash()) catch {
      @provider.Decode(method_name~, ..) =>
        inspect(method_name, content="eth_getTransactionReceipt")
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected a malformed receipt to be rejected")
    }
  })
}

///|
/// The point of the wait: the first polls find nothing and the answer arrives
/// on a later one.
async test "waiting polls until the transaction is mined" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on_sequence(
      method_name="eth_getTransactionReceipt",
      answers=[
        Answers(Json::null()),
        Answers(Json::null()),
        Answers(a_receipt()),
      ],
    )
    let receipt = @provider.wait_for_receipt(
      provider,
      test_tx_hash(),
      timeout=2_000,
      poll_interval=1,
    ) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(receipt.block_number, content="436")
    inspect(provider.calls().length(), content="3")
  })
}

///|
/// One confirmation is the receipt's own block, so the default wait asks the
/// node nothing beyond the receipt itself.
async test "a single confirmation needs no block number" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionReceipt",
      response=a_receipt(),
    )
    let _ = @provider.wait_for_receipt(provider, test_tx_hash()) catch {
      e => fail("unexpected error \{e}")
    }
    for call in provider.calls() {
      assert_eq(call.0, "eth_getTransactionReceipt")
    }
  })
}

///|
/// More than one confirmation is a question about the head, and it is answered
/// by waiting for the chain to move past the receipt's block.
async test "further confirmations wait for the head to advance" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
      .on(method_name="eth_getTransactionReceipt", response=a_receipt())
      .on_sequence(
        method_name="eth_blockNumber",
        // the receipt is in 0x1b4: one, then two, then the three asked for
        answers=[
          Answers("0x1b4".to_json()),
          Answers("0x1b5".to_json()),
          Answers("0x1b6".to_json()),
        ],
      )
    let receipt = @provider.wait_for_receipt(
      provider,
      test_tx_hash(),
      confirmations=3,
      timeout=2_000,
      poll_interval=1,
    ) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(receipt.block_number, content="436")
    inspect(
      provider.calls().filter(call => call.0 == "eth_blockNumber").length(),
      content="3",
    )
  })
}

///|
/// The distinction the wait exists to make: "no receipt yet" is `None`, and
/// "no receipt for as long as you allowed" is an error of its own.
async test "a wait that runs out of time raises Timeout, not a wallet error" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionReceipt",
      response=Json::null(),
    )
    try
      @provider.wait_for_receipt(
        provider,
        test_tx_hash(),
        timeout=20,
        poll_interval=1,
      )
    catch {
      @provider.ProviderError::Timeout(msg) =>
        assert_true(msg.contains("was not mined"))
      e => fail("expected Timeout, but not \{e}")
    } noraise {
      _ => fail("expected the wait to time out")
    }
  })
}

///|
/// A wallet-side failure is not something to keep polling through: it comes
/// straight back out of the wait.
async test "an error from the node ends the wait immediately" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on_error(
      method_name="eth_getTransactionReceipt",
      error=Unauthorized,
    )
    try
      @provider.wait_for_receipt(
        provider,
        test_tx_hash(),
        timeout=2_000,
        poll_interval=1,
      )
    catch {
      @provider.ProviderError::Unauthorized => ()
      e => fail("expected Unauthorized, but not \{e}")
    } noraise {
      _ => fail("expected the wallet error to propagate")
    }
    inspect(provider.calls().length(), content="1")
  })
}

///|
/// A reverted transaction is mined, so the wait succeeds and the caller reads
/// the outcome off the receipt rather than out of an error.
async test "a reverted transaction still returns a receipt" {
  @async.with_task_group(_ => {
    let reverted = a_receipt()
    guard reverted is Object(fields) else { fail("expected an object") }
    fields["status"] = "0x0".to_json()
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionReceipt",
      response=reverted,
    )
    let receipt = @provider.wait_for_receipt(provider, test_tx_hash()) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(receipt.status, content="Reverted")
  })
}

///|
/// Asking for no confirmations is a caller bug rather than a weaker wait, so
/// it is reported instead of being quietly read as one.
async test "a wait for fewer than one confirmation is rejected" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getTransactionReceipt",
      response=a_receipt(),
    )
    for bad in [0, -1] {
      try
        @provider.wait_for_receipt(provider, test_tx_hash(), confirmations=bad)
      catch {
        @provider.InvalidConfig(message) =>
          assert_true(message.contains("confirmations must be at least 1"))
        e => fail("expected a configuration error, but not \{e}")
      } noraise {
        _ => fail("expected confirmations=\{bad} to be rejected")
      }
    }
    // and nothing was asked of the node on the way out
    assert_true(provider.calls().is_empty())
  })
}
