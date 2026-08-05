---
title: How the SDK is shaped
description: Stateless by design, typed requests, open answers, FFI in one place.
---

# How the SDK is shaped

Four decisions explain most of the API. They are worth ten minutes because each
one shows up in every call you make.

## It is stateless

The SDK caches no current account and no current chain. There is no `connect()`
that leaves a session behind, and no `wallet.address` to read afterwards. Every
value comes from the wallet at the moment it is asked for:

```moonbit
async fn read_now(wallet : @browser.BrowserProvider) -> Unit raise {
  let accounts = @provider.accounts(wallet) // asks the wallet, every time
  let chain = @provider.chain_id(wallet) // asks the wallet, every time
  println("\{accounts.length()} account(s) on chain \{chain.to_uint64()}")
}
```

This is not minimalism for its own sake. The wallet is a separate program the
user is also driving: they can switch account in the extension, switch chain from
another tab, or revoke this page's access, and no call you made will fail because
of it. A cached "current account" would simply be wrong, and would go wrong
silently.

So the state lives in your application, and the three EIP-1193 events are how it
is kept true:

```moonbit
fn hold_it_yourself(
  wallet : @browser.BrowserProvider,
  set_account : (@endor.Address?) -> Unit,
) -> @provider.Subscription {
  // most recently selected first; an empty array means access was revoked
  @provider.on_accounts_changed(wallet, accounts => set_account(accounts.get(0)))
}
```

Subscribing reads no initial value — `accountsChanged` fires when the account
*changes*, not when you start listening — so the starting point is a
`@provider.accounts` call you make yourself. [React to wallet
changes](/cookbook/events/) is the whole pattern.

## Requests are opaque, answers are open

A type you *build* is a `pub struct` with private fields and a constructor that
validates, so an invalid value cannot be spelled:

```moonbit
fn build_a_request(token : @endor.Address) -> @endor.CallRequest raise {
  // `to` is required; from, data and value are optional and, when absent, are
  // left out of the request rather than sent as null
  @endor.CallRequest::new(token, data=@endor.Hex::from_string("0x18160ddd"))
}
```

A type you only *read back off the wire* is a `pub(all) struct` whose fields are
the answer:

```moonbit
fn read_an_answer(receipt : @endor.TransactionReceipt) -> String {
  // built by its own `from_json` and nowhere else, so an accessor in front of
  // each field would add a method per field and hide nothing
  "block \{receipt.block_number}, gas \{receipt.gas_used}"
}
```

The rule is worth stating because it explains why `Address` has a constructor
that can fail and `TransactionReceipt` does not: one is a promise you make to the
chain, the other is a fact the chain reported.

## Quantities are hex on the wire, types in your code

JSON-RPC carries numbers as `0x`-prefixed hex, and every one of them is decoded
at the edge:

```moonbit
fn quantities() -> Unit {
  let wei = @endor.Wei::from_int(1000) // 1000 wei, not 1000 ETH
  let chain = @endor.ChainId::mainnet() // 1
  println("\{wei.to_bigint()} wei on chain \{chain.to_uint64()} (\{chain.to_hex()})")
}
```

Amounts are always in the smallest whole unit — `Wei` for the chain's own
currency, a `BigInt` in the token's own unit for an ERC-20. Scaling them for a
human needs `decimals`, so `Wei::from_units` / `Wei::to_units` take it as an
argument and never guess: 18 is ether, 6 is USDC, and what any other token
carries is what `Erc20::decimals` answered. The amount they read is a `String`,
because a `Double` has already lost `0.1` before the SDK could see it.
[Read an ERC-20](/cookbook/erc20/) shows both directions of that conversion.

## FFI lives in one package

Every `extern "js"` binding in shipped code is in `endor/ffi/js`: reading
`globalThis.ethereum`, calling `request`, wiring `on` / `removeListener`, and
`spawn`. `endor/provider/browser` is the only other `js`-only package, because
the whole point there is a browser-injected object.

Everything else — the types, the codecs, `crypto`, `eip712`, `abi`, `contract`,
and the typed RPC helpers in `provider` — is backend-agnostic and testable
against `@provider.MockProvider`. That is why the SDK's own test suite needs no
browser and no wallet, and why calldata can be built with no provider in hand at
all.

## Next

- [Errors](./errors/) — the failures this shape leaves you to handle
- [Cookbook](/cookbook/) — the same ideas, one task at a time
