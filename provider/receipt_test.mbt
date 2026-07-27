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
      @provider.ProviderError::Rpc(code~, ..) => inspect(code, content="-32603")
      e => fail("expected an internal error, but not \{e}")
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
        @provider.ProviderError::Rpc(message~, ..) =>
          assert_true(message.contains("confirmations must be at least 1"))
        e => fail("expected an internal error, but not \{e}")
      } noraise {
        _ => fail("expected confirmations=\{bad} to be rejected")
      }
    }
    // and nothing was asked of the node on the way out
    assert_true(provider.calls().is_empty())
  })
}
