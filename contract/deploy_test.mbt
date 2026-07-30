///|
/// Creation code short enough to read in an assertion: the answer contract's
/// runtime, which nothing here actually runs.
const CODE : String = "0x602a60005260206000f3"

///|
fn creation_code() -> @types.Hex {
  @types.Hex::from_string(CODE) catch {
    e => abort("bad creation code: \{e}")
  }
}

///|
/// The hash the mocked `eth_sendTransaction` answers with.
const DEPLOY_HASH : String = "0x00000000000000000000000000000000000000000000000000000000000000ff"

///|
/// A receipt of a deployment, as a node answers it: no `to`, and the address
/// the code was mined to in `contractAddress`.
fn deploy_receipt(
  status? : String = "0x1",
  contract_address? : Json = "0x8617e340b3d01fa5f11f306f4090fd50e238070d".to_json(),
) -> Json {
  {
    "transactionHash": DEPLOY_HASH.to_json(),
    "transactionIndex": "0x0".to_json(),
    "blockHash": "0xb6de5c3c1b70d24de3ea4eb90a6c9f1f5eb1d0e6a5e3b3f1b7e0c0b9a8d7c6e5".to_json(),
    "blockNumber": "0x1b4".to_json(),
    "from": "0x52908400098527886e0f7030069857d2e4169ee7".to_json(),
    "to": Json::null(),
    "contractAddress": contract_address,
    "cumulativeGasUsed": "0x5208".to_json(),
    "gasUsed": "0x5208".to_json(),
    "effectiveGasPrice": "0x3b9aca00".to_json(),
    "status": status.to_json(),
    "logs": Json::array([]),
  }
}

///|
/// A provider that accepts a deployment and answers `receipt` for it.
fn deploying_provider(
  receipt? : Json = deploy_receipt(),
) -> @provider.MockProvider {
  @provider.MockProvider::new()
  .on(method_name="eth_sendTransaction", response=DEPLOY_HASH.to_json())
  .on(method_name="eth_getTransactionReceipt", response=receipt)
}

///|
test "a constructor taking nothing leaves the creation code alone" {
  let data = @contract.deployment_data(bytecode=creation_code()) catch {
    e => fail("unexpected error: \{e}")
  }
  inspect(data, content=CODE)
}

///|
test "constructor arguments are encoded behind the creation code" {
  let data = @contract.deployment_data(
    bytecode=creation_code(),
    inputs=[Uint(256), Address],
    args=[Uint(1000N), Address(test_address())],
  ) catch {
    e => fail("unexpected error: \{e}")
  }
  inspect(
    data,
    content=CODE +
      "00000000000000000000000000000000000000000000000000000000000003e8" +
      "00000000000000000000000052908400098527886e0f7030069857d2e4169ee7",
  )
}

///|
test "arguments that do not match the constructor are the ABI's error" {
  try
    @contract.deployment_data(bytecode=creation_code(), inputs=[Uint(256)])
  catch {
    @contract.ContractError::Abi(_) => ()
    e => fail("expected an ABI error, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
async test "a deployment is a transaction with no recipient" {
  @async.with_task_group(_ => {
    let provider = deploying_provider()
    let hash = @contract.send_deployment(
      provider,
      from=test_address(),
      bytecode=creation_code(),
      inputs=[Uint(256)],
      args=[Uint(1000N)],
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(hash, content=DEPLOY_HASH)
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
        #|            "data": String("0x602a60005260206000f300000000000000000000000000000000000000000000000000000000000003e8"),
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
async test "deploying answers with the contract the receipt located" {
  @async.with_task_group(_ => {
    let deployed = @contract.deploy(
      deploying_provider(),
      from=test_address(),
      bytecode=creation_code(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      deployed.address(),
      content=(
        #|0x8617E340B3D01FA5F11F306F4090FD50E238070D
      ),
    )
  })
}

///|
/// A constructor that reverts still has a receipt, so the wait returns
/// normally and the status is the only thing saying nothing was deployed.
async test "a reverted deployment is not a deployment" {
  @async.with_task_group(_ => {
    try
      @contract.deploy(
        deploying_provider(receipt=deploy_receipt(status="0x0")),
        from=test_address(),
        bytecode=creation_code(),
      )
    catch {
      @contract.ContractError::Deployment(_) => ()
      e => fail("expected a deployment error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// The other half: a receipt that succeeded and still names no address is a
/// node answering something the SDK cannot use, not a contract at address
/// zero.
async test "a receipt with no contractAddress is not a deployment either" {
  @async.with_task_group(_ => {
    try
      @contract.deploy(
        deploying_provider(
          receipt=deploy_receipt(contract_address=Json::null()),
        ),
        from=test_address(),
        bytecode=creation_code(),
      )
    catch {
      @contract.ContractError::Deployment(_) => ()
      e => fail("expected a deployment error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "the wallet declining a deployment is the wallet's error" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on_error(
      method_name="eth_sendTransaction",
      error=UserRejected,
    )
    try
      @contract.deploy(provider, from=test_address(), bytecode=creation_code())
    catch {
      @contract.ContractError::Rpc(UserRejected) => ()
      e => fail("expected a rejection, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}
