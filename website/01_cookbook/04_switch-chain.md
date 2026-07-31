---
title: Switch chains
description: One call that switches, adds the chain when the wallet has never seen it, and switches again.
islands:
  - switch_chain
---

# Switch chains

A wallet that does not know the chain you asked for answers `4902`. Handling that
is the part every dapp otherwise writes by hand.

<Island name="switch_chain" trigger="load" />

## The call

```moonbit
async fn to_polygon(wallet : @browser.BrowserProvider) -> Unit {
  try {
    @provider.switch_or_add_chain(
      wallet,
      @endor.ChainParams::new(
        @endor.ChainId::polygon(),
        chain_name="Polygon Mainnet",
        rpc_urls=["https://polygon-rpc.com"],
        native_currency=@endor.NativeCurrency::new(name="POL", symbol="POL"),
        block_explorer_urls=["https://polygonscan.com"],
      ),
    )
  } catch {
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}
```

`switch_or_add_chain` sends `wallet_switchEthereumChain`. When the wallet answers
`4902` — it does not know that chain — it adds the chain with
`wallet_addEthereumChain` from the same `ChainParams` and switches again. There
is no `4902` anywhere in the code above, and that is the point.

The two steps are also available on their own, for a dapp that wants to decide
what to do between them:

| Function                                   | JSON-RPC method              |
| ------------------------------------------ | ---------------------------- |
| `@provider.switch_chain(p, chain_id)`      | `wallet_switchEthereumChain` |
| `@provider.add_chain(p, params)`           | `wallet_addEthereumChain`    |
| `@provider.switch_or_add_chain(p, params)` | both                         |

All three prompt, so all three raise `UserRejected` when the user says no.
`switch_chain` is the one that raises `UnrecognizedChain` for 4902.

## Describing a chain

`ChainParams` is the EIP-3085 description a wallet needs to add a chain it has
never seen. Most of it only matters on the 4902 path — a wallet that already
knows the chain ignores everything but the id:

```moonbit
fn sepolia() -> @endor.ChainParams {
  @endor.ChainParams::new(
    @endor.ChainId::sepolia(), // presets save spelling the id out
    chain_name="Sepolia",
    rpc_urls=["https://ethereum-sepolia-rpc.publicnode.com"],
    native_currency=@endor.NativeCurrency::new(name="Ether", symbol="ETH"),
    // optional, and left out of the request when empty
    block_explorer_urls=["https://sepolia.etherscan.io"],
  )
}
```

`NativeCurrency`'s `decimals` defaults to 18. `ChainId` has presets for
`mainnet()`, `sepolia()` and `polygon()`; anything else is
`ChainId::from_uint64(n)`.

## Everything you read is about a chain

A switch invalidates every balance, every nonce and every contract address the
page is holding. The chain can also change from inside the wallet, with no button
of yours involved, which is what `chainChanged` is for:

```moonbit
fn rerun_on_switch(
  wallet : @browser.BrowserProvider,
  reload : () -> Unit,
) -> @provider.Subscription {
  @provider.on_chain_changed(wallet, chain => {
    println("now on chain \{chain.to_uint64()} — everything read before is stale")
    reload()
  })
}
```

The demo above watches for exactly this. Switch chains in your extension rather
than with its buttons and the fields still update.

## Reading which chain you are on

```moonbit
async fn where_am_i(wallet : @browser.BrowserProvider) -> Unit raise {
  let chain = @provider.chain_id(wallet) // eth_chainId
  println("\{chain.to_uint64()} (\{chain.to_hex()})")
  if chain == @endor.ChainId::mainnet() {
    println("this is real money")
  }
}
```
