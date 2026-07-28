///|
/// The account every read test is run against. Parsing it cannot fail, so the
/// tests below spend no lines on the codec they are not exercising.
fn test_address() -> @types.Address {
  @types.Address::from_string("0x52908400098527886E0F7030069857D2E4169EE7") catch {
    e => abort("bad test address: \{e}")
  }
}

///|
async test "can call contract" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response="0x00000000000000000000000000000000000000000000000000000000000003e8".to_json(),
    )

    let contract = @contract.Contract::new(test_address())

    let ret = @contract.Contract::call(
      contract,
      provider,
      name="test",
      inputs=[],
      args=[],
      outputs=[Uint(256)],
    ) catch {
      e => fail("unexpected error \{e}")
    }

    debug_inspect(ret, content="[Uint(1000)]")

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
        #|            "data": String("0xf8a8fd6d"),
        #|          },
        #|        ),
        #|        String("latest"),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
async test "error on invalid contract call result" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_call",
      // odd hex
      response="0x3e8".to_json(),
    )

    let contract = @contract.Contract::new(test_address())

    try
      @contract.Contract::call(
        contract,
        provider,
        name="test",
        inputs=[],
        args=[],
        outputs=[Uint(256)],
      )
    catch {
      @contract.ContractError::Rpc(_) => ()
      e => fail("expected provider error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "transfer sends calldata to the token" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_sendTransaction",
      response=Json::string(
        "0x00000000000000000000000000000000000000000000000000000000000000ff",
      ),
    )

    let contract = @contract.Contract::new(test_address())

    let hash = @contract.Contract::send(
      contract,
      provider,
      from=test_address(),
      name="test",
      inputs=[],
    ) catch {
      e => fail("unexpected error: \{e}")
    }

    inspect(
      hash,
      content="0x00000000000000000000000000000000000000000000000000000000000000ff",
    )

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
        #|            "data": String("0xf8a8fd6d"),
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
