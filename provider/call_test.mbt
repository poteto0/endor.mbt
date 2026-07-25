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

    assert_eq(
      ret.to_string(),
      "0x00000000000000000000000000000000000000000000000000000000000003e8",
    )
    // the call object and the default block tag reach the node as sent
    assert_eq(
      provider.last_call(),
      Some(
        (
          "eth_call",
          Json::array([
            {
              "to": test_address().to_json(),
              "from": test_address().to_json(),
              "data": Json::string("0x70a08231"),
              "value": Json::string("0x1"),
            },
            Json::string("latest"),
          ]),
        ),
      ),
    )

    // an explicit tag replaces the default
    let ret = @provider.call(provider, req, block=Number(16)) catch {
      e => fail("unexpected error \{e}")
    }

    assert_eq(ret.byte_length(), 32)
    assert_eq(
      provider.last_call(),
      Some(("eth_call", Json::array([req.to_json(), Json::string("0x10")]))),
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

    assert_true(ret.is_empty())
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
      @provider.ProviderError::Rpc(code~, ..) => assert_eq(code, -32603)
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
      @provider.ProviderError::Rpc(code~, ..) => assert_eq(code, 3)
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

    assert_eq(gas, @types.Quantity::new(21000))
    // no block parameter: the estimate is against current state
    assert_eq(
      provider.last_call(),
      Some(("eth_estimateGas", Json::array([req.to_json()]))),
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
      @provider.ProviderError::Rpc(code~, ..) => assert_eq(code, -32603)
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
      @provider.ProviderError::Rpc(code~, ..) => assert_eq(code, 3)
      e => fail("expected an rpc error, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}
