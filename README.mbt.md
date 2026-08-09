<img src="https://raw.githubusercontent.com/poteto0/endor.mbt/main/website/public/logo.svg" alt="" width="88" height="88">

# endor.mbt

[![docs](https://img.shields.io/badge/docs-endor.poteto--mahiro.com-1f6feb)](https://endor.poteto-mahiro.com)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-poteto0%2Fendor-blue)](https://mooncakes.io/docs/poteto0/endor)
[![CI](https://github.com/poteto0/endor.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/poteto0/endor.mbt/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/poteto0/endor.mbt/blob/main/LICENSE)

An Ethereum SDK for MoonBit: typed, async functions for reading a chain, calling
contracts through their ABI, and signing. Two choices sit under that surface and
they are independent. **How you reach a chain** — the
[EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) provider a browser extension
injects as `globalThis.ethereum`, or JSON-RPC over HTTP to a node, which works
on every backend and not only `js`. And **who holds the key** — a wallet that
prompts its user, or a private key in your own process. Every pairing is valid,
and the code above them does not change.

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

Then import the packages you need in your `moon.pkg`. The domain types are
re-exported from the root package, so `"poteto0/endor"` gives you
`@endor.Address`, `@endor.ChainId`, and friends when you need to spell a type
out.

### Reaching a chain

Everything is written against the `Provider` trait, so the transport is one
import and nothing above it knows which one you chose.

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

What HTTP cannot serve, it says so about: every `wallet_*` method and
`eth_requestAccounts` raise `UnsupportedMethod`, since there is nothing behind a
URL to prompt a user. `HttpTransport` stays a trait for a caller whose HTTP is
its own — retries, a connection pool, a proxy — and for `wasm-gc`, the one
backend `@endpoint` cannot reach.
[Read without a wallet](https://endor.poteto-mahiro.com/cookbook/http-rpc/) is
the whole recipe: headers, errors, and what an endpoint refuses.

In a browser, the transport is the extension instead. `BrowserProvider` wraps
the injected object, and `discover` enumerates every wallet that answers
[EIP-6963](https://eips.ethereum.org/EIPS/eip-6963) when more than one is
installed:

```
import {
  "poteto0/endor/provider",         // @provider — Provider, typed RPC, errors
  "poteto0/endor/provider/browser", // @browser — the injected wallet
  "poteto0/endor/ffi/js",           // @js — spawn (bridge async to the JS event loop)
}
```

```mbt-example
async fn connect_a_wallet() -> @endor.Address raise @provider.ProviderError {
  @provider.require_account(@browser.BrowserProvider::require())
}
```

This is the one part of the SDK that is `js`-only, because a browser-injected
object is what it is about. Everything under it — the types, the codecs, the ABI
layer, the typed RPC helpers — is backend-agnostic.

### Holding a key

Signing is the account's business, not the transport's. `WalletClient` pairs a
provider with an `Account`, and the calls on it — `send`, `sign_message`,
`sign_typed_data` — are the same whichever account you gave it.

```
import {
  "poteto0/endor/wallet",        // @wallet — WalletClient, JsonRpcAccount
  "poteto0/endor/account/local", // @local — LocalAccount, a key in this process
}
```

```mbt-example
async fn send_from_a_local_key(
  node : @http.HttpProvider[@endpoint.Endpoint],
  key : @endor.Hex,
  to : @endor.Address,
) -> @endor.TxHash raise {
  let client = @wallet.WalletClient::new(node, @local.LocalAccount::new(key))
  client.send(to~, value=@endor.Wei::from_ether("0.01"))
}
```

`LocalAccount` signs in this process — secp256k1 and the transaction encoding
are the SDK's own — and the signed transaction goes out as
`eth_sendRawTransaction`, which is what makes a script, a backend or a test able
to spend without anybody to click _approve_. That is also the danger: a key
anything can read is a key anything can sign with, so it belongs in a server and
never in a bundle a browser downloads.
`@wallet.WalletClient::connect(wallet)` is the other half — the same client with
the wallet as the account, prompting its user for every signature.
[Sign with a local key](https://endor.poteto-mahiro.com/cookbook/local-account/)
lays out every pairing of transport and key.

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
