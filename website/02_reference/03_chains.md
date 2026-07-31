---
title: Chains
description: Switching, adding, and the EIP-3085 description a wallet needs to do the second.
---

# Chains

| Function                                   | JSON-RPC method              |
| ------------------------------------------ | ---------------------------- |
| `@provider.switch_chain(p, chain_id)`      | `wallet_switchEthereumChain` |
| `@provider.add_chain(p, params)`           | `wallet_addEthereumChain`    |
| `@provider.switch_or_add_chain(p, params)` | both, see below              |

All three prompt the user, so they raise `UserRejected` when the user declines.
`switch_chain` raises `UnrecognizedChain` (4902) when the wallet does not know
the chain, which is what the composite absorbs: it switches, and on 4902 adds the
chain and switches again. Any other error propagates from the step that raised
it.

```moonbit
async fn move_the_wallet(wallet : @browser.BrowserProvider) -> Unit raise {
  @provider.switch_chain(wallet, @endor.ChainId::mainnet())
  let polygon = @endor.ChainParams::new(
    @endor.ChainId::polygon(),
    chain_name="Polygon Mainnet",
    rpc_urls=["https://polygon-rpc.com"],
    native_currency=@endor.NativeCurrency::new(name="POL", symbol="POL"),
    block_explorer_urls=["https://polygonscan.com"],
  )
  @provider.switch_or_add_chain(wallet, polygon)
}
```

Adding a chain is also how a wallet switches to it, so `switch_or_add_chain`'s
second switch is redundant on wallets that do both — it is there for the ones
that add without switching.

## ChainParams

`@endor.ChainParams` is the EIP-3085 description a wallet needs in order to add a
chain it has never seen — a domain type like the rest, so it lives in
`endor/types`.

- `chain_name`, `rpc_urls` and `native_currency` are required
- `block_explorer_urls` is optional and left out of the request when empty
- `NativeCurrency`'s `decimals` defaults to 18

## ChainId

```moonbit
fn chain_ids() -> Unit {
  // presets, so the ids do not have to be spelled out: mainnet, sepolia,
  // holesky, polygon, amoy, arbitrum, optimism, base
  let _ = @endor.ChainId::mainnet() // 1
  let _ = @endor.ChainId::sepolia() // 11155111
  let _ = @endor.ChainId::base() // 8453
  // anything else
  let other = @endor.ChainId::new(42161)
  // hex on the wire, a number in your code
  println("\{other.to_uint64()} is \{other.to_hex()}")
}
```

## After a switch

Everything the page read is about the old chain: balances, nonces, and every
contract address, since the same address is a different contract — or nothing at
all — on another chain. `chainChanged` fires for switches your code did not make
as well; see [Events](./events/).
