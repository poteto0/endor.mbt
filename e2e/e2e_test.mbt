///|
/// Every test here runs the real `BrowserProvider` against a live Anvil node
/// and skips when `ENDOR_E2E_RPC_URL` is unset. What a `MockProvider` cannot
/// tell us is whether the wire format the SDK emits is the one a node accepts —
/// so the assertions deliberately stay close to what Anvil guarantees about a
/// fresh chain, and the point is that the request went out and decoded.

///|
async test "wallet is detected and answers as the injected provider" {
  on_anvil(provider => {
    assert_true(provider.is_metamask())
    let accounts = @provider.request_accounts(provider)
    assert_eq(accounts.length(), 10)
    assert_eq(accounts[0], dev_account())
    assert_eq(accounts[1], other_account())
    assert_eq(@provider.accounts(provider), accounts)
  })
}

///|
async test "chain id is anvil's" {
  on_anvil(provider => assert_eq(@provider.chain_id(provider), anvil_chain_id()))
}

///|
async test "dev accounts are funded" {
  on_anvil(provider => {
    // anvil funds each dev account with 10000 ETH
    let balance = @provider.balance(provider, dev_account())
    assert_true(balance.to_bigint() > 0N)
  })
}

///|
async test "mining advances the block number" {
  on_anvil(provider => {
    let before = @provider.block_number(provider)
    let _ = provider.request(method_name="evm_mine", params=Json::array([]))
    assert_true(@provider.block_number(provider) > before)
  })
}

///|
async test "nonce grows with each transaction from the account" {
  on_anvil(provider => {
    let before = @provider.transaction_count(provider, dev_account())
    let _ = deploy_answer_contract(provider)
    // strictly greater, not `before + 1`: the tests share one chain and run
    // concurrently, so another test's transaction may land in between
    assert_true(@provider.transaction_count(provider, dev_account()) > before)
  })
}

///|
async test "gas price is reported" {
  on_anvil(provider => {
    let price = @provider.gas_price(provider)
    assert_true(price.to_bigint() > 0N)
  })
}

///|
async test "code distinguishes an account from a contract" {
  on_anvil(provider => {
    assert_true(@provider.code(provider, dev_account()).is_empty())
    assert_false(@provider.is_contract(provider, dev_account()))
    let deployed = deploy_answer_contract(provider)
    assert_eq(@provider.code(provider, deployed), answer_contract_runtime())
    assert_true(@provider.is_contract(provider, deployed))
  })
}

///|
async test "call runs deployed code and estimate_gas prices it" {
  on_anvil(provider => {
    let deployed = deploy_answer_contract(provider)
    let request = @types.CallRequest::new(deployed, from=dev_account())
    // the contract returns 42 as a single 32-byte word
    assert_eq(
      @provider.call(provider, request).to_string(),
      "0x000000000000000000000000000000000000000000000000000000000000002a",
    )
    // a call that executes anything costs more than the 21000 base fee
    assert_true(@provider.estimate_gas(provider, request).to_uint64() > 21000UL)
  })
}

///|
async test "call against a non-contract returns empty data" {
  on_anvil(provider => {
    let request = @types.CallRequest::new(other_account(), from=dev_account())
    assert_true(@provider.call(provider, request).is_empty())
  })
}

///|
async test "switching to the chain the wallet is on succeeds" {
  on_anvil(provider => {
    @provider.switch_chain(provider, anvil_chain_id())
    assert_eq(@provider.chain_id(provider), anvil_chain_id())
  })
}

///|
async test "switching to an unknown chain raises 4902" {
  on_anvil(provider => {
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
  on_anvil(provider => {
    let params = @types.ChainParams::new(
      @types.ChainId::new(4242),
      chain_name="Endor E2E",
      rpc_urls=[rpc_url()],
      native_currency=@types.NativeCurrency::new(name="Ether", symbol="ETH"),
    )
    // the switch raises 4902, and the fallback adds the chain and switches again
    @provider.switch_or_add_chain(provider, params)
  })
}
