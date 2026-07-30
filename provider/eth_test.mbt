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

    inspect(
      acc.to_checksum_string(),
      content="0x52908400098527886E0F7030069857D2E4169EE7",
    )
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
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="-32603")
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
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="-32603")
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
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="-32603")
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
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="-32603")
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
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="-32603")
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    // a JSON number, not the hex string the RPC promises
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response=Json::number(0),
    )

    try @provider.call(provider, call_request()) catch {
      @provider.ProviderError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
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
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="-32603")
      e => fail("expected provider error, but not \{e}")
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
/// A wallet answering with something that is not a 32-byte hash is the SDK's
/// own problem, so it surfaces as an internal error rather than as a `TxHash`
/// nobody can use.
async test "error send answered with a malformed hash" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_sendTransaction",
      response="0xdeadbeef".to_json(),
    )

    try @provider.send_transaction(provider, transaction_request()) catch {
      @provider.ProviderError::Rpc(code~, message~) => {
        inspect(code, content="-32603")
        inspect(message.contains("eth_sendTransaction"), content="true")
      }
      e => fail("expected an internal error, but not \{e}")
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

    // the account comes first, and the document reaches the wallet serialized
    // — v4 takes a string, not a nested object
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
