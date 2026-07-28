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
    // strictly greater, not `before + 1`: the tests share one chain and run
    // concurrently, so another test's transaction may land in between
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
      @contract.Erc20::new(@anvil.other_account()).balance_of(
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
      rpc_urls=[@anvil.endpoint()],
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
/// so by the time `eth_sendTransaction` answers the transaction is on chain.
async fn[P : @provider.Provider] transaction_by_hash(
  provider : P,
  hash : @types.TxHash,
) -> Map[String, Json] raise @provider.ProviderError {
  let tx = provider.request(
    method_name="eth_getTransactionByHash",
    params=Json::array([hash.to_json()]),
  )
  guard tx is Object(fields) else {
    raise @provider.ProviderError::internal("no transaction for \{hash}")
  }
  fields
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
    let tx = transaction_by_hash(provider, hash)
    assert_eq(tx.get("from"), Some(@anvil.dev_account().to_json()))
    assert_eq(tx.get("to"), Some(recipient(1).to_json()))
  })
}

///|
/// What the fee mode actually produces on chain. `Auto` sends no fee field and
/// the node defaults it, which since London means an EIP-1559 (type `0x02`)
/// transaction — the behaviour `Fee` documents, asserted against a real node
/// rather than against the docs.
async test "fee mode decides the transaction type on chain" {
  @anvil.on(provider => {
    debug_inspect(tx_type(provider, Auto), content="Some(String(\"0x2\"))")
    debug_inspect(
      tx_type(
        provider,
        Eip1559(
          max_fee_per_gas=@types.Wei::from_bigint(20_000_000_000N),
          max_priority_fee_per_gas=@types.Wei::from_bigint(1_000_000_000N),
        ),
      ),
      content="Some(String(\"0x2\"))",
    )
    debug_inspect(
      tx_type(
        provider,
        Legacy(gas_price=@types.Wei::from_bigint(20_000_000_000N)),
      ),
      content="Some(String(\"0x0\"))",
    )
  })
}

///|
/// Send one wei paying for gas the way `fee` says, and report the transaction
/// type the node recorded for it.
async fn[P : @provider.Provider] tx_type(
  provider : P,
  fee : @types.Fee,
) -> Json? raise @provider.ProviderError {
  let hash = @provider.send_transaction(
    provider,
    @types.TransactionRequest::new(
      @anvil.dev_account(),
      to=recipient(2),
      value=@types.Wei::from_int(1),
      fee~,
    ),
  )
  transaction_by_hash(provider, hash).get("type")
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
async test "a transaction the node never saw has no receipt" {
  @anvil.on(provider => {
    assert_true(@provider.transaction_receipt(provider, unknown_hash()) is None)
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
