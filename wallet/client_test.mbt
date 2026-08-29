///|
/// Anvil's first account, and the address its key derives.
const ANVIL_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

///|
const ANVIL_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

///|
const RECIPIENT = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

///|
/// A node that answers everything `prepare` asks it, with fixed numbers so the
/// transaction it builds is fixed too.
fn node() -> @provider.MockProvider {
  @provider.MockProvider::new()
  .on(method_name="eth_chainId", response=Json::string("0x1"))
  .on(method_name="eth_getTransactionCount", response=Json::string("0x0"))
  .on(method_name="eth_getBlockByNumber", response=a_block())
  .on(
    method_name="eth_maxPriorityFeePerGas",
    response=Json::string("0x3b9aca00"),
  )
  .on(method_name="eth_gasPrice", response=Json::string("0x2540be400"))
  .on(method_name="eth_estimateGas", response=Json::string("0x5208"))
  .on(
    method_name="eth_sendRawTransaction",
    response=Json::string("0x" + "11".repeat(32)),
  )
  .on(
    method_name="eth_sendTransaction",
    response=Json::string("0x" + "22".repeat(32)),
  )
  .on(
    method_name="personal_sign",
    response=Json::string("0x" + "33".repeat(65)),
  )
  .on(
    method_name="eth_signTypedData_v4",
    response=Json::string("0x" + "44".repeat(65)),
  )
}

///|
/// The header `estimate_fees` reads a base fee off. `0x3b9aca00` is 1 gwei, so
/// the fee it works out is `2 * base + tip`.
fn a_block() -> Json {
  {
    "number": "0x1b4".to_json(),
    "hash": ("0x" + "ab".repeat(32)).to_json(),
    "parentHash": ("0x" + "cd".repeat(32)).to_json(),
    "timestamp": "0x687fbc00".to_json(),
    "miner": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266".to_json(),
    "gasLimit": "0x1c9c380".to_json(),
    "gasUsed": "0x5208".to_json(),
    "baseFeePerGas": "0x3b9aca00".to_json(),
    "transactions": Json::array([]),
  }
}

///|
/// The same header without a base fee, which is what a chain that never forked
/// to London reports — and, with a zero one, what anvil reports too.
fn a_block_without_base_fee() -> Json {
  match a_block() {
    Object(fields) => {
      fields.remove("baseFeePerGas")
      Json::object(fields)
    }
    other => other
  }
}

///|
fn recipient() -> @types.Address raise {
  @types.Address::from_string(RECIPIENT)
}

///|
fn local_account() -> @local.LocalAccount raise {
  @local.LocalAccount::new(@types.Hex::from_string(ANVIL_KEY))
}

///|
/// An authorization by anvil's first account, signed for `nonce`. Which nonce
/// that should be is the whole subject of `nonces`; here it is whatever the
/// test is checking travelled.
fn an_authorization(
  nonce : @types.Quantity,
) -> @types.SignedAuthorization raise {
  let authorization = @types.Authorization::new(
    chain_id=@types.ChainId::mainnet(),
    address=recipient(),
    nonce~,
  )
  let key = @secp256k1.PrivateKey::from_bytes(
    @types.Hex::from_string(ANVIL_KEY).to_bytes(),
  )
  let signature = key.sign(authorization.signing_digest())
  authorization.signed(
    r=signature.r(),
    s=signature.s(),
    y_parity=signature.recovery_id(),
  )
}

///|
/// A local account signs here and the bytes leave as `eth_sendRawTransaction`.
/// The node never sees the key and is never asked to sign.
async test "a local account signs and broadcasts raw" {
  @async.with_task_group(_ => {
    let node = node()
    let client = @wallet.WalletClient::new(node, local_account())
    let hash = client.send(to=recipient(), value=@types.Wei::from_ether("1"))
    assert_eq(hash.to_string(), "0x" + "11".repeat(32))
    let sent = node.calls().filter(call => call.0 == "eth_sendRawTransaction")
    assert_eq(sent.length(), 1)
    // No wallet was asked to sign anything.
    assert_eq(
      node.calls().filter(call => call.0 == "eth_sendTransaction").length(),
      0,
    )
  })
}

///|
/// The same client, the same transport, a wallet-held account: now the whole
/// transaction goes over and the wallet does both steps.
async test "a json-rpc account hands the transaction to the wallet" {
  @async.with_task_group(_ => {
    let node = node()
    let account = @wallet.JsonRpcAccount::new(
      node,
      @types.Address::from_string(ANVIL_ADDRESS),
    )
    let client = @wallet.WalletClient::new(node, account)
    let hash = client.send(to=recipient(), value=@types.Wei::from_ether("1"))
    assert_eq(hash.to_string(), "0x" + "22".repeat(32))
    // And nothing was pinned down first: the nonce, the fees and the gas are
    // the wallet's to decide, so the node was never asked for them.
    assert_eq(node.calls().map(call => call.0), ["eth_sendTransaction"])
  })
}

///|
/// What `prepare` asks the node for, and what it does not ask when told.
async test "prepare fills only what it was not given" {
  @async.with_task_group(_ => {
    let node = node()
    let client = @wallet.WalletClient::new(node, local_account())
    client.prepare(
      to=recipient(),
      nonce=@types.Quantity::new(9),
      gas=@types.Quantity::new(21000),
      fee=Eip1559(
        max_fee_per_gas=@types.Wei::from_gwei("20"),
        max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
      ),
    )
    |> ignore
    // Only the chain id was left to find out.
    let asked = node.calls().map(call => call.0)
    assert_eq(asked, ["eth_chainId"])
  })
}

///|
/// The transaction a local account builds and signs is the one `cast mktx`
/// makes from the same numbers — the node's answers here are chosen to match
/// that vector, so this pins the whole path end to end.
async test "the prepared transaction is the known vector" {
  @async.with_task_group(_ => {
    let node = node()
    let account = local_account()
    let client = @wallet.WalletClient::new(node, account)
    let tx = client.prepare(
      to=recipient(),
      value=@types.Wei::from_ether("1"),
      fee=Eip1559(
        max_fee_per_gas=@types.Wei::from_gwei("20"),
        max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
      ),
    )
    assert_eq(
      account.sign_transaction(tx).to_string(),
      "0x02f8730180843b9aca008504a817c8008252089470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c001a00a3a2646d4ad968bb56317fdb15e17fb4d9deec0d03e8b6cb05e7125bda3006da026618ad17cc63cf1979ca75f850c536a073ec88ab1ab7c8db8b8eb129499d9ae",
    )
  })
}

///|
/// A message is signed the same way whichever account it is; only where the
/// work happens differs.
async test "signing a message goes to whoever holds the key" {
  @async.with_task_group(_ => {
    let node = node()
    let held = @wallet.WalletClient::new(node, local_account())
    assert_eq(
      held.sign_message("hello").to_string(),
      "0xf16ea9a3478698f695fd1401bfe27e9e4a7e8e3da94aa72b021125e31fa899cc573c48ea3fe1d4ab61a9db10c19032026e3ed2dbccba5a178235ac27f94504311c",
    )
    // Nothing was asked of the node.
    assert_eq(node.calls().length(), 0)
    let remote = @wallet.WalletClient::new(
      node,
      @wallet.JsonRpcAccount::new(
        node,
        @types.Address::from_string(ANVIL_ADDRESS),
      ),
    )
    assert_eq(remote.sign_message("hello").to_string(), "0x" + "33".repeat(65))
    assert_eq(node.last_call().unwrap().0, "personal_sign")
  })
}

///|
/// A wallet cannot hand back signed bytes, and says so rather than producing
/// something that looks like a signature.
async test "a json-rpc account refuses to sign a transaction alone" {
  @async.with_task_group(_ => {
    let node = node()
    let account = @wallet.JsonRpcAccount::new(
      node,
      @types.Address::from_string(ANVIL_ADDRESS),
    )
    let tx = @types.UnsignedTransaction::new(
      chain_id=@types.ChainId::mainnet(),
      nonce=@types.Quantity::new(0),
      max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
      max_fee_per_gas=@types.Wei::from_gwei("20"),
      gas=@types.Quantity::new(21000),
      to=recipient(),
    )
    try account.sign_transaction(tx) |> ignore catch {
      NotSupported(_) => ()
      e => fail("expected NotSupported, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A head block with no base fee makes `estimate_fees` answer with a flat
/// price, and a flat price is a legacy transaction: the chain that reports no
/// base fee is the one that would reject a type-`0x02` envelope.
async test "a chain with no base fee is priced from eth_gasPrice" {
  @async.with_task_group(_ => {
    let node = node().on(
      method_name="eth_getBlockByNumber",
      response=a_block_without_base_fee(),
    )
    let client = @wallet.WalletClient::new(node, local_account())
    let tx = client.prepare(to=recipient(), value=@types.Wei::from_ether("1"))
    inspect(
      tx
      .to_request(from=@types.Address::from_string(ANVIL_ADDRESS))
      .unwrap()
      .to_json()
      .stringify(),
      content=(
        #|{"from":"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266","to":"0x70997970c51812dc3a010c7d01b50e0d17dc79c8","value":"0xde0b6b3a7640000","data":"0x","gas":"0x5208","nonce":"0x0","gasPrice":"0x2540be400"}
      ),
    )
  })
}

///|
/// A flat price the caller named picks the format too, on a chain that prices
/// both ways: what comes back is signed locally as a legacy transaction, at
/// exactly the price asked for.
async test "a legacy fee the caller named builds a legacy transaction" {
  @async.with_task_group(_ => {
    let client = @wallet.WalletClient::new(node(), local_account())
    let tx = client.prepare(
      to=recipient(),
      value=@types.Wei::from_ether("1"),
      fee=Legacy(gas_price=@types.Wei::from_gwei("7")),
    )
    // The format is the whole of the claim; what the fields become on the wire
    // is `to_request`'s, and tested there.
    assert_true(
      tx is Legacy(gas_price~, ..) && gas_price == @types.Wei::from_gwei("7"),
    )
  })
}

///|
/// The wallet, though, can send one — and `send` reaches it without going
/// through `prepare`, so the flat price arrives as `gasPrice`.
async test "a legacy fee reaches a wallet as gasPrice" {
  @async.with_task_group(_ => {
    let node = node()
    let client = @wallet.WalletClient::new(
      node,
      @wallet.JsonRpcAccount::new(
        node,
        @types.Address::from_string(ANVIL_ADDRESS),
      ),
    )
    client.send(
      to=recipient(),
      value=@types.Wei::from_ether("1"),
      fee=Legacy(gas_price=@types.Wei::from_gwei("7")),
    )
    |> ignore
    let (called, params) = node.last_call().unwrap()
    assert_eq(called, "eth_sendTransaction")
    inspect(
      params.stringify(),
      content=(
        #|[{"from":"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266","to":"0x70997970c51812dc3a010c7d01b50e0d17dc79c8","value":"0xde0b6b3a7640000","data":"0x","gasPrice":"0x1a13b8600"}]
      ),
    )
  })
}

///|
/// A contract creation cannot have its gas estimated, so it has to say it.
async test "a contract creation must say its own gas" {
  @async.with_task_group(_ => {
    let client = @wallet.WalletClient::new(node(), local_account())
    let data = @types.Hex::from_string("0x60806040")
    incomplete(() => client.prepare(data~) |> ignore)
  })
}

///|
/// Run `attempt` and require it to raise `Incomplete` — a field the client was
/// asked to fill in and could not.
async fn incomplete(attempt : async () -> Unit raise WalletError) -> Unit {
  try attempt() catch {
    Incomplete(_) => ()
    e => fail("expected Incomplete, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The nonce arithmetic EIP-7702 turns on: an account delegating in its own
/// transaction signs for the nonce *after* the one that transaction takes.
async test "a self-sponsored authorization is signed one nonce ahead" {
  @async.with_task_group(_ => {
    let node = node().on(
      method_name="eth_getTransactionCount",
      response=Json::string("0x7"),
    )
    let client = @wallet.WalletClient::new(node, local_account())
    let nonces = client.nonces(SelfSponsored)
    assert_eq(nonces.transaction, @types.Quantity::new(7))
    assert_eq(nonces.authorization, @types.Quantity::new(8))
    // one account, one question
    assert_eq(node.calls().length(), 1)
  })
}

///|
/// A sponsor's transaction moves the sponsor's nonce, so the authority's is
/// read as it stands — the two are different accounts and different counts.
async test "a sponsored authorization keeps the authority's own nonce" {
  @async.with_task_group(_ => {
    let node = node().on_sequence(method_name="eth_getTransactionCount", answers=[
      Answers(Json::string("0x7")),
      Answers(Json::string("0x2")),
    ])
    let client = @wallet.WalletClient::new(node, local_account())
    let nonces = client.nonces(Sponsored(recipient()))
    assert_eq(nonces.transaction, @types.Quantity::new(7))
    assert_eq(nonces.authorization, @types.Quantity::new(2))
    // and the second question was about the authority, not about the sponsor
    assert_true(
      node.last_call().unwrap().1.stringify().contains(RECIPIENT.to_lower()),
    )
  })
}

///|
/// Naming this client's own account as somebody else's is the mistake the
/// distinction exists to catch, so it is refused rather than answered with the
/// nonce one short.
async test "sponsoring yourself is refused" {
  @async.with_task_group(_ => {
    let client = @wallet.WalletClient::new(node(), local_account())
    let me = @types.Address::from_string(ANVIL_ADDRESS)
    incomplete(() => client.nonces(Sponsored(me)) |> ignore)
  })
}

///|
/// An authorization list makes `prepare` build a type-`0x04` envelope, and the
/// list travels on it.
async test "prepare builds a 7702 transaction from an authorization list" {
  @async.with_task_group(_ => {
    let node = node()
    let client = @wallet.WalletClient::new(node, local_account())
    let authorization = an_authorization(@types.Quantity::new(1))
    let tx = client.prepare(
      to=recipient(),
      gas=@types.Quantity::new(200000),
      fee=Eip1559(
        max_fee_per_gas=@types.Wei::from_gwei("20"),
        max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
      ),
      authorization_list=[authorization],
    )
    assert_true(
      tx is Eip7702(authorization_list~, ..) &&
      authorization_list == [authorization],
    )
    // the gas was named, so nothing was estimated against a call that does not
    // know about the delegation
    assert_eq(
      node.calls().filter(call => call.0 == "eth_estimateGas").length(),
      0,
    )
  })
}

///|
/// The two fields a delegating transaction cannot be given by the node, and
/// the fee market it has no legacy form for.
async test "a 7702 transaction says what cannot be worked out" {
  @async.with_task_group(_ => {
    let client = @wallet.WalletClient::new(node(), local_account())
    let list = [an_authorization(@types.Quantity::new(1))]
    let gas = @types.Quantity::new(200000)
    let to = recipient()
    let flat : @types.Fee = Legacy(gas_price=@types.Wei::from_gwei("7"))
    // no gas: `eth_estimateGas` is never told the list
    incomplete(() => client.prepare(to~, authorization_list=list) |> ignore)
    // no recipient: a delegating transaction creates nothing
    incomplete(() => client.prepare(gas~, authorization_list=list) |> ignore)
    // a flat price: there is no legacy 7702 envelope
    incomplete(() => {
      client.prepare(to~, gas~, fee=flat, authorization_list=list) |> ignore
    })
  })
}

///|
/// A wallet-held account can send one after all: `authorizationList` is a field
/// `eth_sendTransaction` carries, so the whole transaction goes over as it is.
async test "a 7702 transaction reaches a wallet with its authorizations" {
  @async.with_task_group(_ => {
    let node = node()
    let client = @wallet.WalletClient::new(
      node,
      @wallet.JsonRpcAccount::new(
        node,
        @types.Address::from_string(ANVIL_ADDRESS),
      ),
    )
    let tx = client.prepare(
      to=recipient(),
      gas=@types.Quantity::new(200000),
      fee=Eip1559(
        max_fee_per_gas=@types.Wei::from_gwei("20"),
        max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
      ),
      authorization_list=[an_authorization(@types.Quantity::new(1))],
    )
    client.send_transaction(tx) |> ignore
    let (called, params) = node.last_call().unwrap()
    assert_eq(called, "eth_sendTransaction")
    assert_true(params.stringify().contains("authorizationList"))
  })
}

///|
/// A node that cannot answer is reported as itself, so a caller can still ask
/// whether it is worth trying again — the answer has to come from the
/// `ProviderError` inside, not from the wrapper.
async test "the transport's error survives" {
  @async.with_task_group(_ => {
    let node = @provider.MockProvider::new().on_error(
      method_name="eth_chainId",
      error=@provider.Timeout("no answer"),
    )
    let client = @wallet.WalletClient::new(node, local_account())
    let to = recipient()
    try client.prepare(to~) |> ignore catch {
      Provider(Timeout(_)) as e => assert_true(e.is_retryable())
      e => fail("expected a timeout, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// `connect` is the three lines a dapp would otherwise write: prompt, wrap,
/// pair. What it returns signs as whichever account the wallet named.
async test "connect prompts and pairs in one call" {
  @async.with_task_group(_ => {
    let node = node().on(
      method_name="eth_requestAccounts",
      response=Json::array([Json::string(ANVIL_ADDRESS.to_lower())]),
    )
    let client = @wallet.WalletClient::connect(node)
    assert_eq(client.address().to_checksum_string(), ANVIL_ADDRESS)
    assert_eq(node.last_call().unwrap().0, "eth_requestAccounts")
    // and it is the wallet that will sign, not this process
    let hash = client.send(to=recipient(), value=@types.Wei::from_ether("1"))
    assert_eq(hash.to_string(), "0x" + "22".repeat(32))
  })
}

///|
/// A user who declines the connection gets the provider's own error back.
async test "a declined connection is UserRejected" {
  @async.with_task_group(_ => {
    let node = @provider.MockProvider::new().on_error(
      method_name="eth_requestAccounts",
      error=@provider.UserRejected,
    )
    try @wallet.WalletClient::connect(node) |> ignore catch {
      Provider(UserRejected) => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}
