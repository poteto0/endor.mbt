///|
/// A latest block, carrying only the field the fee helpers read out of it.
/// Everything else is what `Block::from_json` insists on having.
fn a_block_with_base_fee(base_fee : String?) -> Json {
  let block = {
    "number": "0x1b4".to_json(),
    "hash": A_BLOCK.to_json(),
    "parentHash": A_BLOCK.to_json(),
    "timestamp": "0x5".to_json(),
    "miner": "0x52908400098527886e0f7030069857d2e4169ee7".to_json(),
    "gasLimit": "0x1c9c380".to_json(),
    "gasUsed": "0x5208".to_json(),
    "transactions": Json::array([]),
  }
  if base_fee is Some(fee) {
    block["baseFeePerGas"] = fee.to_json()
  }
  Json::object(block)
}

///|
async test "the suggested tip comes back as the wei it is" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_maxPriorityFeePerGas",
      response="0x3b9aca00".to_json(),
    )
    let tip = @provider.max_priority_fee_per_gas(provider) catch {
      e => fail("unexpected error \{e}")
    }
    guard tip is Some(tip) else { fail("expected a tip") }
    inspect(tip.to_gwei(), content="1")
  })
}

///|
/// The method is a geth extension, not a standardized one, so a node is allowed
/// not to have it. That is an absent answer rather than a failure — the whole
/// reason the return type is an option.
async test "a node that does not implement the tip method answers None" {
  @async.with_task_group(_ => {
    for
      error in [
        @provider.ProviderError::Rpc(code=-32601, message="method not found"),
        @provider.ProviderError::UnsupportedMethod,
      ] {
      let provider = @provider.MockProvider::new().on_error(
        method_name="eth_maxPriorityFeePerGas",
        error~,
      )
      let tip = @provider.max_priority_fee_per_gas(provider) catch {
        e => fail("unexpected error \{e}")
      }
      assert_true(tip is None)
    }
  })
}

///|
/// Every other failure is still a failure: a wallet the user said no to has not
/// told us the method is missing.
async test "a tip request the user rejected still raises" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on_error(
      method_name="eth_maxPriorityFeePerGas",
      error=UserRejected,
    )
    try @provider.max_priority_fee_per_gas(provider) catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected a rejection to propagate")
    }
  })
}

///|
async test "a fee history is asked for as count, block and percentiles" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_feeHistory",
      response={
        "oldestBlock": "0x10".to_json(),
        "baseFeePerGas": Json::array(["0x7".to_json(), "0x8".to_json()]),
        "gasUsedRatio": Json::array([Json::number(0.5)]),
        "reward": Json::array([Json::array(["0x1".to_json()])]),
      },
    )
    let history = @provider.fee_history(
      provider,
      block_count=1,
      newest_block=Number(436),
      reward_percentiles=[20.0, 80.0],
    ) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(history.oldest_block, content="16")
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_feeHistory")
    inspect(params.stringify(), content="[\"0x1\",\"0x1b4\",[20,80]]")
  })
}

///|
/// Percentiles the node would refuse are refused here instead, so the message
/// names the argument the caller wrote rather than a parameter index.
async test "percentiles out of order or out of range are refused" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
    for percentiles in [[80.0, 20.0], [101.0], [-1.0]] {
      try
        @provider.fee_history(
          provider,
          block_count=1,
          reward_percentiles=percentiles,
        )
      catch {
        @provider.ProviderError::Rpc(message~, ..) =>
          assert_true(message.has_prefix("fee_history: reward_percentiles"))
        e => fail("expected an argument error, but not \{e}")
      } noraise {
        _ => fail("expected these percentiles to be rejected")
      }
    }
    // and nothing was sent to the node
    assert_true(provider.calls().is_empty())
  })
}

///|
async test "a fee history of no blocks at all is refused" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
    try @provider.fee_history(provider, block_count=0) catch {
      @provider.ProviderError::Rpc(message~, ..) =>
        assert_true(message.has_prefix("fee_history: block_count"))
      e => fail("expected an argument error, but not \{e}")
    } noraise {
      _ => fail("expected a zero block count to be rejected")
    }
  })
}

///|
/// The ordinary case: a London chain whose node answers both questions.
/// `2 * 0x64 + 0xa` is `0xd2`.
async test "an estimate on a 1559 chain is the base fee doubled plus the tip" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
      .on(
        method_name="eth_getBlockByNumber",
        response=a_block_with_base_fee(Some("0x64")),
      )
      .on(method_name="eth_maxPriorityFeePerGas", response="0xa".to_json())
    let fee = @provider.estimate_fees(provider) catch {
      e => fail("unexpected error \{e}")
    }
    guard fee is Eip1559(max_fee_per_gas=cap, max_priority_fee_per_gas=tip) else {
      fail("expected a 1559 fee, got \{fee}")
    }
    inspect(cap.to_hex(), content="0xd2")
    inspect(tip.to_hex(), content="0xa")
  })
}

///|
/// Without `eth_maxPriorityFeePerGas` the tip is what `eth_gasPrice` carries
/// above the base fee, since that is how the suggested price was built.
async test "an estimate without the tip method takes the tip out of the price" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
      .on(
        method_name="eth_getBlockByNumber",
        response=a_block_with_base_fee(Some("0x64")),
      )
      .on_error(
        method_name="eth_maxPriorityFeePerGas",
        error=Rpc(code=-32601, message="method not found"),
      )
      .on(method_name="eth_gasPrice", response="0x6e".to_json())
    let fee = @provider.estimate_fees(provider) catch {
      e => fail("unexpected error \{e}")
    }
    guard fee is Eip1559(max_fee_per_gas=cap, max_priority_fee_per_gas=tip) else {
      fail("expected a 1559 fee, got \{fee}")
    }
    // 0x6e - 0x64 = 0xa, and the cap is 2 * 0x64 + 0xa
    inspect(tip.to_hex(), content="0xa")
    inspect(cap.to_hex(), content="0xd2")
  })
}

///|
/// A price below the base fee means the base fee rose since the node last
/// answered. The difference is floored rather than wrapped around, which for an
/// unsigned quantity is the difference between no tip and an impossible one.
async test "a price below the base fee floors the tip at zero" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
      .on(
        method_name="eth_getBlockByNumber",
        response=a_block_with_base_fee(Some("0x64")),
      )
      .on_error(method_name="eth_maxPriorityFeePerGas", error=UnsupportedMethod)
      .on(method_name="eth_gasPrice", response="0xa".to_json())
    let fee = @provider.estimate_fees(provider) catch {
      e => fail("unexpected error \{e}")
    }
    guard fee is Eip1559(max_fee_per_gas=cap, max_priority_fee_per_gas=tip) else {
      fail("expected a 1559 fee, got \{fee}")
    }
    inspect(tip.to_hex(), content="0x0")
    inspect(cap.to_hex(), content="0xc8")
  })
}

///|
/// A chain that never forked to London has no base fee, and some chains report
/// one that is always zero. Neither has a market to price into, so both get the
/// legacy fee they can actually use.
async test "a chain with no live base fee is priced as legacy" {
  @async.with_task_group(_ => {
    for base_fee in [None, Some("0x0")] {
      let provider = @provider.MockProvider::new()
        .on(
          method_name="eth_getBlockByNumber",
          response=a_block_with_base_fee(base_fee),
        )
        .on(method_name="eth_gasPrice", response="0x4a817c800".to_json())
      let fee = @provider.estimate_fees(provider) catch {
        e => fail("unexpected error \{e}")
      }
      guard fee is Legacy(gas_price~) else {
        fail("expected a legacy fee, got \{fee}")
      }
      inspect(gas_price.to_gwei(), content="20")
      // the tip method is never reached: there is nothing to add it to
      for call in provider.calls() {
        assert_true(call.0 != "eth_maxPriorityFeePerGas")
      }
    }
  })
}
