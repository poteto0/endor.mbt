# endor.mbt

A MoonBit SDK for talking to browser wallets from a dapp. It wraps the
[EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) provider that extensions such
as MetaMask inject as `globalThis.ethereum`, and exposes it as typed, async
MoonBit functions.

![demo](https://raw.githubusercontent.com/poteto0/endor.mbt/main/docs/movie/demo.gif)

> **v0.1.0 is read-only.** Reading accounts and the current chain is supported;
> sending transactions, signing, and chain switching are not yet wrapped. See
> [`docs/scope.md`](https://github.com/poteto0/endor.mbt/blob/main/docs/scope.md)
> — anything unwrapped is still reachable through `Provider::request`.

## Install

```sh
moon add poteto0/endor
```

Then import the packages you need in your `moon.pkg`:

```
import {
  "poteto0/endor/provider", // @provider — Provider, typed RPC, errors
  "poteto0/endor/ffi/js",   // @js — spawn (bridge async to the JS event loop)
}
```

The domain types are re-exported from the root package, so
`"poteto0/endor"` gives you `@endor.Address`, `@endor.ChainId`, and friends when
you need to spell a type out.

## Getting a wallet address

```
async fn connect() -> Unit {
  try {
    // raises NotInstalled when no wallet extension is present
    let wallet = @provider.BrowserProvider::require()
    match @provider.request_accounts(wallet).get(0) { // eth_requestAccounts
      Some(addr) => println("address: \{addr}")
      None => println("no authorized accounts")
    }
    let chain = @provider.chain_id(wallet) // eth_chainId
    println("chain: \{chain.to_uint64()} (\{chain.to_hex()})")
  } catch {
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}

fn main {
  @js.spawn(connect) // bridge async to the JS event loop
}
```

A runnable version of this lives in
[`examples/get-address`](https://github.com/poteto0/endor.mbt/tree/main/examples/get-address),
which renders the same values onto a page, together with an `index.html` you can
open in a browser that has a wallet installed — see
[`examples/README.md`](https://github.com/poteto0/endor.mbt/blob/main/examples/README.md)
for the build-and-serve steps.

## Scope

v0.1.0 wraps `eth_requestAccounts`, `eth_accounts`, and `eth_chainId` in typed
helpers. Sending transactions, signing, chain switching, and provider events are
planned but not implemented; until they land, `Provider::request` reaches any
method with raw `Json`.

**→ [`docs/scope.md`](https://github.com/poteto0/endor.mbt/blob/main/docs/scope.md)**
for the full list, what each helper returns, and how to use the escape hatch.

## Layout

| Package           | Contents                                                                                |
| ----------------- | --------------------------------------------------------------------------------------- |
| `endor` (root)    | re-exports the domain types, so they can be spelled `@endor.Address`                    |
| `endor/types`     | `Address`, `Hex`, `ChainId`, `Wei` and their hex/JSON codecs                             |
| `endor/provider`  | `Provider` trait, `ProviderError`, typed RPC helpers, `BrowserProvider`, `MockProvider`  |
| `endor/ffi/js`    | the only `extern "js"` code: `globalThis.ethereum` access, `request`, `spawn`            |

`endor` and `endor/types` are backend-agnostic; `endor/ffi/js` and therefore
`endor/provider` are `js`-only, since the whole point is a browser-injected
object.

Wallet-side failures never panic: EIP-1193 / EIP-1474 codes map onto
`ProviderError` variants (`UserRejected`, `UnrecognizedChain`, …), and the SDK's
own internal failures use `ProviderError::internal`.

## Development

From a clone of the [repository](https://github.com/poteto0/endor.mbt) — the
recipes below live in its `justfile`, which is not part of the published package.
The default target is `js`, since the SDK drives a browser-injected object.

```sh
just ut     # unit tests — no browser or wallet needed
just build  # build for js, including the example
just ci     # test, format, check, and refresh generated interfaces
```

The typed RPC layer is tested against `MockProvider`, so nothing in the test
suite requires a wallet.
