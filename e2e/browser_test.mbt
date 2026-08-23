///|
/// Every test here runs the real `BrowserProvider` against a live Anvil node
/// and skips when `ENDOR_E2E_RPC_URL` is unset. What a `MockProvider` cannot
/// tell us is whether the wire format the SDK emits is the one a node accepts —
/// so the assertions deliberately stay close to what Anvil guarantees about a
/// fresh chain, and the point is that the request went out and decoded.

///|
async test "wallet is detected and answers as the injected provider" {
  @anvil.on(provider => {
    inspect(provider.is_metamask(), content="true")
    let accounts = @provider.request_accounts(provider)
    inspect(accounts.length(), content="10")
    inspect(accounts[0], content="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
    inspect(accounts[1], content="0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
    assert_eq(@provider.accounts(provider), accounts)
  })
}

///|
async test "chain id is anvil's" {
  @anvil.on(provider => {
    inspect(@provider.chain_id(provider), content="ChainId(31337)")
  })
}

///|
async test "dev accounts are funded" {
  @anvil.on(provider => {
    // anvil funds each dev account with 10000 ETH
    let balance = @provider.balance(provider, @anvil.dev_account())
    inspect(balance.to_bigint() > 0N, content="true")
  })
}

///|
async test "mining advances the block number" {
  @anvil.on(provider => {
    let before = @provider.block_number(provider)
    let _ = provider.request(method_name="evm_mine", params=Json::array([]))
    inspect(@provider.block_number(provider) > before, content="true")
  })
}

///|
async test "nonce grows with each transaction from the account" {
  @anvil.on(provider => {
    let before = @provider.transaction_count(provider, @anvil.dev_account())
    let _ = @anvil.deploy_answer_contract(provider)
    // strictly greater, not `before + 1`: the tests share one chain
    inspect(
      @provider.transaction_count(provider, @anvil.dev_account()) > before,
      content="true",
    )
  })
}

///|
async test "gas price is reported" {
  @anvil.on(provider => {
    let price = @provider.gas_price(provider)
    inspect(price.to_bigint() > 0N, content="true")
  })
}

///|
/// The 1559 material, against a node that really answers it. A mock proves the
/// params the SDK sends; only a node proves it accepts them — `eth_feeHistory`
/// above all, whose three parameters are the least uniform request in the SDK
/// (a count, a block and an array of *numbers* rather than quantities).
async test "the 1559 fee material comes back from a node" {
  @anvil.on(provider => {
    // Anvil implements the tip method, so this is `Some`; no node can prove the
    // `None` case
    guard @provider.max_priority_fee_per_gas(provider) is Some(_) else {
      fail("expected anvil to suggest a tip")
    }
    let history = @provider.fee_history(provider, block_count=1, reward_percentiles=[
      20.0, 80.0,
    ])
    // one block asked for, so two base fees: the block's, and the next one's
    inspect(history.base_fee_per_gas.length(), content="2")
    inspect(history.gas_used_ratio.length(), content="1")
    guard history.reward is Some(reward) else {
      fail("expected the percentiles asked for to be answered")
    }
    inspect(reward[0].length(), content="2")
    // composed: anvil is a London chain, so the estimate is a 1559 fee
    guard @provider.estimate_fees(provider)
      is Eip1559(max_fee_per_gas=cap, max_priority_fee_per_gas=tip) else {
      fail("expected a 1559 fee from a London chain")
    }
    inspect(cap.to_bigint() >= tip.to_bigint(), content="true")
  })
}

///|
async test "code distinguishes an account from a contract" {
  @anvil.on(provider => {
    inspect(
      @provider.code(provider, @anvil.dev_account()).is_empty(),
      content="true",
    )
    inspect(
      @provider.is_contract(provider, @anvil.dev_account()),
      content="false",
    )
    let deployed = @anvil.deploy_answer_contract(provider)
    inspect(
      @provider.code(provider, deployed),
      content="\{@anvil.answer_contract_runtime()}",
    )
    inspect(@provider.is_contract(provider, deployed), content="true")
  })
}

///|
async test "call runs deployed code and estimate_gas prices it" {
  @anvil.on(provider => {
    let deployed = @anvil.deploy_answer_contract(provider)
    let request = @types.CallRequest::new(deployed, from=@anvil.dev_account())
    // the contract returns 42 as a single 32-byte word
    inspect(
      @provider.call(provider, request).to_string(),
      content="0x000000000000000000000000000000000000000000000000000000000000002a",
    )
    // a call that executes anything costs more than the 21000 base fee
    inspect(
      @provider.estimate_gas(provider, request).to_uint64() > 21000UL,
      content="true",
    )
  })
}

///|
/// The ABI layer against real EVM output: the same call as above, but the
/// answer is read back as a `uint256` instead of as a hex word.
///
/// A mock can prove the encoding; only a node can prove that what the EVM
/// returns is what the decoder expects. The deployed contract answers 42 to any
/// selector, so the call names one it does not have to implement.
async test "a contract call decodes the answer through the ABI" {
  @anvil.on(provider => {
    let deployed = @anvil.deploy_answer_contract(provider)
    let values = @contract.Contract::new(deployed).call(
      provider,
      name="answer",
      outputs=[Uint(256)],
      from=@anvil.dev_account(),
    )
    guard values is [Uint(answer)] else {
      fail("expected one uint256, got \{values.length()} values")
    }
    inspect(answer, content="42")
  })
}

///|
/// The other half: a contract that is not the one the caller described. Every
/// account here answers `0x`, which no return type can be read out of, and that
/// is the `Abi` half of `ContractError` rather than a wallet failure.
async test "an address with no code is an Abi error, not an Rpc one" {
  @anvil.on(provider => {
    try
      @erc20.Erc20::new(@anvil.other_account()).balance_of(
        provider,
        @anvil.dev_account(),
      )
      |> ignore
    catch {
      Abi(_) => inspect("abi", content="abi")
      e => fail("expected an Abi error, got \{e}")
    } noraise {
      _ => fail("expected an error")
    }
  })
}

///|
async test "call against a non-contract returns empty data" {
  @anvil.on(provider => {
    let request = @types.CallRequest::new(
      @anvil.other_account(),
      from=@anvil.dev_account(),
    )
    inspect(@provider.call(provider, request).is_empty(), content="true")
  })
}

///|
async test "switching to the chain the wallet is on succeeds" {
  @anvil.on(provider => {
    @provider.switch_chain(provider, @anvil.chain_id())
    inspect(@provider.chain_id(provider), content="ChainId(31337)")
  })
}

///|
async test "switching to an unknown chain raises 4902" {
  @anvil.on(provider => {
    // a chain id no other test adds — the wallet shim is shared
    try @provider.switch_chain(provider, @types.ChainId::new(9999)) catch {
      @provider.ProviderError::UnrecognizedChain(_) => ()
      e => fail("expected UnrecognizedChain, but \{e}")
    } noraise {
      _ => fail("expected UnrecognizedChain, but the switch succeeded")
    }
  })
}

///|
async test "switch_or_add_chain adds the chain the wallet does not know" {
  @anvil.on(provider => {
    let params = @types.ChainParams::new(
      @types.ChainId::new(4242),
      chain_name="Endor E2E",
      rpc_urls=[@env.endpoint()],
      native_currency=@types.NativeCurrency::new(name="Ether", symbol="ETH"),
    )
    // the switch raises 4902, and the fallback adds the chain and switches again
    @provider.switch_or_add_chain(provider, params)
  })
}

///|
/// A recipient the test numbered `id` has to itself. Tests share one chain and
/// run concurrently, so a test that asserts on a balance needs an address no
/// other test sends to. Not a dev account either: it never sends, so it never
/// pays gas.
fn recipient(id : Int) -> @types.Address {
  @types.Address::from_string("0x00000000000000000000000000000000e2e0000\{id}") catch {
    e => abort("bad recipient: \{e}")
  }
}

///|
/// The transaction `hash` identifies, once anvil has mined it. Anvil automines,
/// so by the time `eth_sendTransaction` answers the transaction is on chain and
/// the node cannot answer `null`.
async fn[P : @provider.Provider] a_sent_transaction(
  provider : P,
  hash : @types.TxHash,
) -> @types.Transaction raise @provider.ProviderError {
  guard @provider.transaction_by_hash(provider, hash) is Some(tx) else {
    raise @provider.MalformedResponse("no transaction for \{hash}")
  }
  tx
}

///|
async test "sending value moves it to the recipient" {
  @anvil.on(provider => {
    let before = @provider.balance(provider, recipient(1))
    let hash = @provider.send_transaction(
      provider,
      @types.TransactionRequest::new(
        @anvil.dev_account(),
        to=recipient(1),
        value=@types.Wei::from_int(1000),
      ),
    )
    let after = @provider.balance(provider, recipient(1))
    assert_eq(after.to_bigint(), before.to_bigint() + 1000N)
    // the hash the wallet answered with identifies that very transaction
    let tx = a_sent_transaction(provider, hash)
    assert_eq(tx.from, @anvil.dev_account())
    assert_eq(tx.to, Some(recipient(1)))
  })
}

///|
/// What the fee mode actually produces on chain. `Auto` sends no fee field and
/// the node defaults it, which since London means an EIP-1559 (type `0x02`)
/// transaction — the behaviour `Fee` documents, asserted against a real node
/// rather than against the docs.
async test "fee mode decides the transaction type on chain" {
  @anvil.on(provider => {
    debug_inspect(tx_type(provider, Auto), content="Some(2)")
    debug_inspect(
      tx_type(
        provider,
        Eip1559(
          max_fee_per_gas=@types.Wei::from_bigint(20_000_000_000N),
          max_priority_fee_per_gas=@types.Wei::from_bigint(1_000_000_000N),
        ),
      ),
      content="Some(2)",
    )
    debug_inspect(
      tx_type(
        provider,
        Legacy(gas_price=@types.Wei::from_bigint(20_000_000_000N)),
      ),
      content="Some(0)",
    )
  })
}

///|
/// Send one wei paying for gas the way `fee` says, and report the transaction
/// type the node recorded for it.
async fn[P : @provider.Provider] tx_type(
  provider : P,
  fee : @types.Fee,
) -> UInt64? raise @provider.ProviderError {
  let hash = @provider.send_transaction(
    provider,
    @types.TransactionRequest::new(
      @anvil.dev_account(),
      to=recipient(2),
      value=@types.Wei::from_int(1),
      fee~,
    ),
  )
  a_sent_transaction(provider, hash).transaction_type
}

///|
/// A wallet that refuses is the normal failure of a send, and 4001 has to reach
/// the caller as `UserRejected` through the real FFI boundary, not just through
/// the mock.
async test "a rejected send raises 4001" {
  @anvil.on(provider => {
    try
      @provider.send_transaction(
        provider,
        @types.TransactionRequest::new(
          @anvil.reject_account(),
          to=recipient(3),
          value=@types.Wei::from_int(1),
        ),
      )
      |> ignore
    catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but \{e}")
    } noraise {
      _ => fail("expected UserRejected, but the send succeeded")
    }
  })
}

///|
/// A hash of the right shape that no test ever sends, so the node genuinely
/// knows nothing about it — the "never mined" case, told apart from a
/// transaction that is merely still pending.
fn unknown_hash() -> @types.TxHash {
  @types.TxHash::from_string(
    "0xe2e0000000000000000000000000000000000000000000000000000000000000",
  ) catch {
    e => abort("bad test hash: \{e}")
  }
}

///|
/// The receipt layer against a real node: what `send_transaction` broadcast is
/// what `wait_for_receipt` reports on, and the block it names really contains
/// it.
async test "a receipt reports the transaction it was waited for" {
  @anvil.on(provider => {
    let hash = @provider.send_transaction(
      provider,
      @types.TransactionRequest::new(
        @anvil.dev_account(),
        to=recipient(4),
        value=@types.Wei::from_int(1),
      ),
    )
    let receipt = @provider.wait_for_receipt(
      provider,
      hash,
      timeout=5_000,
      poll_interval=100,
    )
    assert_eq(receipt.transaction_hash, hash)
    inspect(receipt.status, content="Success")
    // a plain transfer executes nothing, so it costs exactly the base fee
    inspect(receipt.gas_used, content="Quantity(21000)")
    assert_eq(receipt.from, @anvil.dev_account())
    assert_eq(receipt.to, Some(recipient(4)))
    assert_true(receipt.contract_address is None)
    assert_true(receipt.logs.is_empty())
    // the same receipt is there without waiting, now that it is mined
    assert_eq(@provider.transaction_receipt(provider, hash), Some(receipt))
  })
}

///|
/// A deployment is the case where the two address fields swap over, and the
/// address the receipt names is where the code ended up.
async test "a deployment receipt names the contract it created" {
  @anvil.on(provider => {
    let deployed = @anvil.deploy_answer_contract(provider)
    inspect(@provider.is_contract(provider, deployed), content="true")
  })
}

///|
/// The same deployment through the SDK's own `@contract.deploy`, which is the
/// one above with the receipt's `contractAddress` already turned into the
/// `Contract` the caller goes on to use. A mock can prove the request it builds;
/// only a node can prove the code it sent runs and answers where the receipt
/// said it would.
async test "deploying through the contract layer lands a callable contract" {
  @anvil.on(provider => {
    let deployed = @contract.deploy(
      provider,
      from=@anvil.dev_account(),
      bytecode=@anvil.answer_contract_code(),
      timeout=5_000,
      poll_interval=100,
    )
    let answer = @contract.uint_answer(
      deployed.call(provider, name="answer", outputs=[Uint(256)]),
      what="answer",
    )
    inspect(answer, content="42")
  })
}

///|
/// A log filter is the one request whose *shape* varies most — `address` and
/// each `topics` position are either a value or an array, and `blockHash` is
/// refused alongside a range. A mock proves the JSON the SDK built; only a node
/// proves that JSON is one it will accept. Anvil emits no events of its own
/// here, so what is asserted is that each filter came back as a list at all.
async test "a log filter is a request the node accepts" {
  @anvil.on(provider => {
    let head = @provider.block_number(provider)
    // the widest shape: an OR at topic 0, a hole at topic 1, a constraint at 2
    let filter = @types.LogFilter::range(
      from_block=Number(0),
      to_block=Number(head),
      address=[@anvil.dev_account(), @anvil.other_account()],
      topics=[
        Some(
          @types.Topic::any_of([
            @abi.event_topic("Approval(address,address,uint256)"),
            @erc20.Erc20::transfer_topic(),
          ]),
        ),
        None,
        Some(@types.Topic::exactly(@erc20.Erc20::transfer_topic())),
      ],
    )
    assert_true(@provider.logs(provider, filter).is_empty())
    // and the block form, which may carry no range at all
    guard @provider.block_by_number(provider) is Some(block) else {
      fail("expected a latest block")
    }
    guard block.hash is Some(hash) else { fail("expected a sealed block") }
    assert_true(
      @provider.logs(provider, @types.LogFilter::at_block(hash)).is_empty(),
    )
  })
}

///|
/// The other half of a hash, against a real node: what was actually sent. The
/// request named no nonce, no gas and no fee, so every one of those is what the
/// node chose — and this is the only way to read them back.
///
/// Anvil mines on receipt, so what comes back is already `Mined`; the pending
/// case is covered against the mock instead.
async test "a sent transaction is read back by its hash" {
  @anvil.on(provider => {
    let hash = @provider.send_transaction(
      provider,
      @types.TransactionRequest::new(
        @anvil.dev_account(),
        to=recipient(9),
        value=@types.Wei::from_int(3),
      ),
    )
    guard @provider.transaction_by_hash(provider, hash) is Some(tx) else {
      fail("expected the node to know the transaction it just took")
    }
    // what is new here is everything the request did not say
    assert_eq(tx.hash, hash)
    // the request named neither, so both are the node's own answer. The nonce
    // is not asserted on: the dev account is shared, so nothing is predictable
    inspect(tx.gas, content="Quantity(21000)")
    // the wallet priced it, since the request did not
    assert_true(tx.fee is Eip1559(_))
    guard tx.inclusion is Mined(block_number~, ..) else {
      fail("expected an auto-mined transaction")
    }
    guard @provider.block_by_number(provider, block=Number(block_number))
      is Some(block) else {
      fail("expected the block it names")
    }
    assert_true(block.transactions.contains(hash))
  })
}

///|
async test "a transaction the node never saw has no receipt" {
  @anvil.on(provider => {
    assert_true(@provider.transaction_receipt(provider, unknown_hash()) is None)
    // nor a transaction the node is holding: an unknown hash is `null` for both
    assert_true(@provider.transaction_by_hash(provider, unknown_hash()) is None)
    // and waiting for one runs out of time rather than answering
    try
      @provider.wait_for_receipt(
        provider,
        unknown_hash(),
        timeout=200,
        poll_interval=50,
      )
      |> ignore
    catch {
      @provider.ProviderError::Timeout(_) => ()
      e => fail("expected Timeout, but \{e}")
    } noraise {
      _ => fail("expected Timeout, but a receipt appeared")
    }
  })
}

///|
/// Blocks read back by both keys, and the two agree: the block a receipt names
/// is the block that contains the transaction.
async test "a block is read by number and by hash" {
  @anvil.on(provider => {
    let hash = @provider.send_transaction(
      provider,
      @types.TransactionRequest::new(
        @anvil.dev_account(),
        to=recipient(5),
        value=@types.Wei::from_int(1),
      ),
    )
    let receipt = @provider.wait_for_receipt(
      provider,
      hash,
      timeout=5_000,
      poll_interval=100,
    )
    guard @provider.block_by_hash(provider, receipt.block_hash) is Some(by_hash) else {
      fail("the block the receipt names is not there")
    }
    assert_eq(by_hash.number, Some(receipt.block_number))
    assert_true(by_hash.transactions.contains(hash))
    guard @provider.block_by_number(
        provider,
        block=Number(receipt.block_number),
      )
      is Some(by_number) else {
      fail("the block at the receipt's height is not there")
    }
    assert_eq(by_number.hash, Some(receipt.block_hash))
    assert_eq(by_number, by_hash)
    // anvil mines on demand, so the head is at or past that block
    guard @provider.block_by_number(provider) is Some(head) else {
      fail("no head block")
    }
    assert_true(head.number is Some(_))
    assert_true(head.gas_limit.to_uint64() > 0UL)
  })
}

///|
/// A height the chain has not reached is answered with `null`, which is the
/// wire fact `block_by_number`'s `Block?` is typed for.
async test "a block past the head reads as none" {
  @anvil.on(provider => {
    assert_true(
      @provider.block_by_number(provider, block=Number(999_999_999)) is None,
    )
  })
}

///|
/// The count agrees with the block it counts, which is the only thing the two
/// methods have to agree on — asked of the receipt's own block rather than of
/// the head, since the tests share one chain and mine into it concurrently.
async test "a block's transaction count agrees with its transactions" {
  @anvil.on(provider => {
    let hash = @provider.send_transaction(
      provider,
      @types.TransactionRequest::new(
        @anvil.dev_account(),
        to=recipient(6),
        value=@types.Wei::from_int(1),
      ),
    )
    let receipt = @provider.wait_for_receipt(
      provider,
      hash,
      timeout=5_000,
      poll_interval=100,
    )
    guard @provider.block_by_hash(provider, receipt.block_hash) is Some(block) else {
      fail("the block the receipt names is not there")
    }
    let counted = block.transactions.length().to_uint64()
    assert_eq(
      @provider.block_transaction_count_by_hash(provider, receipt.block_hash),
      Some(counted),
    )
    assert_eq(
      @provider.block_transaction_count_by_number(
        provider,
        block=Number(receipt.block_number),
      ),
      Some(counted),
    )
    // a block the node does not have is `null` rather than an error — for a
    // hash, at least; Anvil answers a height past its head with an error
    let unknown = @types.BlockHash::from_string(
      "0xe2e0000000000000000000000000000000000000000000000000000000000000",
    )
    assert_true(
      @provider.block_transaction_count_by_hash(provider, unknown) is None,
    )
  })
}

///|
/// Storage against a real node. Anvil can write a slot directly, so the read
/// can be checked against a value that was put there rather than only against
/// the zeroes an untouched slot answers with — and the word comes back padded
/// to 32 bytes whatever was written into it.
async test "storage reads back the word written into a slot" {
  @anvil.on(provider => {
    let who = recipient(7)
    let slot = @types.Hex::from_string(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
    )
    let word = @types.Hex::from_string(
      "0x000000000000000000000000000000000000000000000000000000000000002a",
    )
    let _ = provider.request(
      method_name="anvil_setStorageAt",
      params=Json::array([who.to_json(), slot.to_json(), word.to_json()]),
    )
    assert_eq(@provider.storage_at(provider, who, slot), word)
    // a slot nobody wrote is zeroes, not an absence
    let untouched = @types.Hex::from_string(
      "0x0000000000000000000000000000000000000000000000000000000000000002",
    )
    inspect(
      @provider.storage_at(provider, who, untouched),
      content="0x0000000000000000000000000000000000000000000000000000000000000000",
    )
  })
}

///|
/// The SDK holds no keys, so it can build nothing to broadcast here: what a node
/// can still prove is that the call reaches it and that a payload it refuses
/// comes back as the node's own error rather than as a decode failure.
async test "a raw transaction the node cannot parse is an rpc error" {
  @anvil.on(provider => {
    let raw = @types.Hex::from_string("0x02f8710182031184773594")
    try @provider.send_raw_transaction(provider, raw) |> ignore catch {
      @provider.ProviderError::Rpc(..) => ()
      e => fail("expected an Rpc error, but \{e}")
    } noraise {
      _ => fail("expected an Rpc error, but the node accepted the payload")
    }
  })
}

///|
/// Signing against a real node: the wire fact is the parameter order, which a
/// node rejects rather than silently mis-signs — Anvil's dev accounts are
/// unlocked, so it signs for them the way a wallet would. The signature itself
/// is 65 bytes, `r ‖ s ‖ v`.
async test "a message is signed by the account that owns it" {
  @anvil.on(provider => {
    let signature = @provider.sign_message(
      provider,
      @anvil.dev_account(),
      "endor.mbt e2e",
    )
    inspect(signature.byte_length(), content="65")
    // deterministic for a fixed key and message
    assert_eq(
      @provider.sign_message(provider, @anvil.dev_account(), "endor.mbt e2e"),
      signature,
    )
    // and a different account is a different signature
    assert_true(
      @provider.sign_message(provider, @anvil.other_account(), "endor.mbt e2e") !=
      signature,
    )
  })
}

///|
/// EIP-712 the same way. The document goes over the wire serialized, and a node
/// that could not parse it would answer with an error instead of a signature —
/// which is what this proves and a mock cannot. `TypedData` decides what the
/// document may say; what a node accepts is decided here.
async test "typed data is signed as an eip-712 document" {
  @anvil.on(provider => {
    let mail = @eip712.TypedData::new(
      @eip712.TypedDataDomain::new(name="Endor", chain_id=@anvil.chain_id()),
      primary_type="Mail",
      types={
        "Mail": [
          @eip712.TypedDataField::new("to", "address"),
          @eip712.TypedDataField::new("contents", "string"),
        ],
      },
      message={
        "to": @anvil.other_account().to_json(),
        "contents": "endor.mbt e2e",
      },
    )
    let signature = @provider.sign_typed_data(
      provider,
      @anvil.dev_account(),
      mail,
    )
    inspect(signature.byte_length(), content="65")
  })
}
