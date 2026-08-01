///|
/// The proof that the read layer needs no wallet: the same node every other
/// e2e test reaches through an injected `globalThis.ethereum`, reached here
/// over plain HTTP with nothing installed at all. `@http_backend.on` builds an
/// `HttpProvider` over an `Endpoint` and skips when `ENDOR_E2E_RPC_URL` is
/// unset, exactly as `@anvil.on` does.
///
/// Deliberately two cases, not a transcription of `browser_test.mbt`. A
/// `FakeTransport` already proves the framing; the one thing only a node can
/// answer is whether the request the SDK POSTs is one it accepts — and every
/// helper goes out through the same `request`, so a read with no params and a
/// read with one settle that for all of them.

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
