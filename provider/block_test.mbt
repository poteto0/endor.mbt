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
      @provider.ProviderError::Rpc(code~, message~) => {
        inspect(code, content="-32603")
        assert_true(message.contains("eth_getBlockByNumber"))
      }
      e => fail("expected an internal error, but not \{e}")
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
