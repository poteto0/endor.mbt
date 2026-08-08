<img src="https://raw.githubusercontent.com/poteto0/endor.mbt/main/website/public/logo.svg" alt="" width="88" height="88">

# endor.mbt

[![docs](https://img.shields.io/badge/docs-endor.poteto--mahiro.com-1f6feb)](https://endor.poteto-mahiro.com)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-poteto0%2Fendor-blue)](https://mooncakes.io/docs/poteto0/endor)
[![CI](https://github.com/poteto0/endor.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/poteto0/endor.mbt/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/poteto0/endor.mbt/blob/main/LICENSE)

An Ethereum SDK for MoonBit. In a browser it wraps the
[EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) provider that extensions
such as MetaMask inject as `globalThis.ethereum`; anywhere else it speaks
JSON-RPC over HTTP to a node. Either way the surface is the same typed, async
MoonBit functions.

![demo](https://raw.githubusercontent.com/poteto0/endor.mbt/main/docs/movie/demo.gif)

## documentation

[endor.poteto-mahiro.com](https://endor.poteto-mahiro.com)

> documentation: a cookbook whose every recipe carries a demo you can drive
> against your own wallet, and a reference for what is wrapped — anything
> unwrapped is still reachable through `Provider::request`.

## Install

```sh
moon add poteto0/endor
```

Then import the packages you need in your `moon.pkg`:

```
import {
  "poteto0/endor/provider",         // @provider — Provider, typed RPC, errors
  "poteto0/endor/provider/browser", // @browser — the injected wallet
  "poteto0/endor/ffi/js",           // @js — spawn (bridge async to the JS event loop)
}
```

### Without a wallet: JSON-RPC over HTTP

A browser wallet is needed to _sign_; it is not needed to _read_. Point the SDK
at a node URL and the same typed helpers work with no extension installed —
**and on any backend**, not only `js`:

```
import {
  "poteto0/endor/provider",               // @provider — Provider, typed RPC, errors
  "poteto0/endor/provider/http",          // @http — HttpProvider, HttpTransport
  "poteto0/endor/provider/http/endpoint", // @endpoint — a node at a URL
}
```

```mbt-example
async fn read_chain_over_http(
  url : String,
) -> @endor.ChainId raise @provider.ProviderError {
  @provider.chain_id(@endpoint.at(url))
}
```

There is no FFI under this. `@endpoint.at` uses `moonbitlang/async`'s HTTP
client, which is `fetch` on `js` and sockets with TLS on `native` and `wasm`,
so the call above compiles and runs in a browser, in a CLI and on a server. A
hosted provider that wants a key takes `headers~`:

```mbt-example
async fn read_chain_from_a_paid_node(
  url : String,
  key : String,
) -> @endor.ChainId raise @provider.ProviderError {
  @provider.chain_id(@endpoint.at(url, headers={ "Authorization": "Bearer \{key}" }))
}
```

`HttpProvider` is a `Provider` like any other, so everything above it — the
typed reads, `Contract::call`, the ABI layer — is unchanged. What HTTP cannot
serve, it says so about: every `wallet_*` method and `eth_requestAccounts`
raise `UnsupportedMethod`, since there is nothing behind a URL to prompt the
user. `HttpTransport` stays a trait for a caller whose HTTP is its own —
retries, a connection pool, a proxy — and for `wasm-gc`, the one backend
`@endpoint` cannot reach.
[Read without a wallet](https://endor.poteto-mahiro.com/cookbook/http-rpc/) is
the whole recipe: headers, errors, and what an endpoint refuses.

The domain types are re-exported from the root package, so
`"poteto0/endor"` gives you `@endor.Address`, `@endor.ChainId`, and friends when
you need to spell a type out.

### The command-line tools

`endor-cli` is a separate module and a separate install — a binary rather than a
dependency, so nothing it needs ends up in your module's resolution:

```sh
moon install poteto0/endor-cli/endor-cli
```

It generates MoonBit contract presets from JSON ABI documents
(`endor-cli init`, then `endor-cli abi`). Point it at a compiler _artifact_ —
`solc --combined-json abi,bin`, a Foundry or Hardhat one — and the preset gets a
`deploy` too, with the creation code embedded. **Experimental**, and not
required to use the SDK — [`cmd/README.md`](cmd/README.md) has the details.
