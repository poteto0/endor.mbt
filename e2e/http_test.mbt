///|
/// The proof that the read layer needs no wallet: the same node every other e2e
/// test reaches through an injected `globalThis.ethereum`, reached here over
/// plain HTTP with nothing installed at all.
///
/// Deliberately two cases. A `FakeTransport` already proves the framing; only a
/// node can say whether the request the SDK POSTs is one it accepts.

///|
async test "chain id is read over http, with no wallet installed" {
  @http_backend.on(provider => {
    inspect(@provider.chain_id(provider), content="ChainId(31337)")
  })
}

///|
/// The same, for a call that carries params: an address and a block tag have
/// to survive the wire as the node spells them, which an empty `params` cannot
/// show.
async test "a dev account's balance is read over http" {
  @http_backend.on(provider => {
    // anvil funds each dev account with 10000 ETH
    let balance = @provider.balance(provider, @anvil.dev_account())
    inspect(balance.to_bigint() > 0N, content="true")
  })
}

///|
/// The one thing a `FakeTransport` cannot settle: whether the wire format a
/// folded window POSTs — a JSON-RPC array, answered by an array — is one a real
/// node accepts. Two reads, one request, and both answers must come back
/// against the ids they were sent under.
async test "a batched window is one request the node accepts" {
  @http_backend.on(provider => {
    let node = provider.with_batch(@provider.BatchPolicy::default())
    let answers = @provider.request_many(node, [
      @provider.BatchCall::new(
        method_name="eth_chainId",
        params=Json::array([]),
      ),
      @provider.BatchCall::new(
        method_name="eth_blockNumber",
        params=Json::array([]),
      ),
    ])
    inspect(answers.length(), content="2")
    // anvil's chain id, and a height that decoded as a quantity at all
    inspect(answers[0] is Ok(String("0x7a69")), content="true")
    inspect(answers[1] is Ok(String(_)), content="true")
  })
}
