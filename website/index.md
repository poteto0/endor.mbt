---
title: endor.mbt
description: An Ethereum SDK for MoonBit — browser wallets over EIP-1193, any node over HTTP.
layout: home
islands:
  - connect
---

# endor.mbt

**An Ethereum SDK for MoonBit.** It wraps the
[EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) provider that extensions such
as MetaMask inject as `globalThis.ethereum`, and exposes it as typed, async
MoonBit functions. Where there is no wallet — a script, a CLI, a server — it
speaks [JSON-RPC over HTTP](/cookbook/http-rpc/) to a node instead, through the
same typed helpers.

```sh
moon add poteto0/endor
```

## Try it

The widget below is not a picture of a wallet connecting. It is
[`website/islands/connect`](https://github.com/poteto0/endor.mbt/tree/main/website/islands/connect)
— MoonBit, compiled to an ES module, calling this SDK against whatever wallet
your browser has. Every demo on this site works the same way.

<Island name="connect" trigger="load" />

## The code behind it

```moonbit
async fn connect() -> Unit {
  try {
    // raises NotInstalled when no wallet extension is present
    let wallet = @browser.BrowserProvider::require()
    let addr = @provider.require_account(wallet) // eth_requestAccounts
    let chain = @provider.chain_id(wallet) // eth_chainId
    println("\{addr.to_checksum_string()} on chain \{chain.to_uint64()}")
  } catch {
    NotInstalled => println("no wallet detected")
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}
```

## What you get

**Typed all the way down.** Addresses, wei, chain ids and block tags are domain
types with validating constructors, not strings that happen to start with `0x`.
A value the wire would reject cannot be spelled — a mistyped checksummed address
is caught by `Address::from_string`, not by the chain.

**Stateless on purpose.** No cached account, no cached chain. Every read answers
for the wallet at the moment it is asked, and the three EIP-1193 events are how
you learn an answer went stale.

**Errors, not panics.** EIP-1193 and EIP-1474 codes map onto a `ProviderError`
suberror — `UserRejected`, `UnrecognizedChain`, `Timeout` — so a user who
declines is a branch in your `match`, not a crash.

**Contracts through their ABI.** `encode` / `decode`, selectors and event
topics, with `Contract::call` and an `Erc20` preset on top. `deploy` is the same
machinery for a transaction with no recipient.

**A wallet is not required to read.** `@endpoint.at("https://…")` is a
`Provider` over HTTP JSON-RPC, so the same reads work with no extension
installed and on `native` and `wasm` as well as `js`. It adds no FFI:
`moonbitlang/async`'s HTTP client is `fetch` in a browser and sockets with TLS
everywhere else.

**FFI in exactly one package.** Every `extern "js"` binding lives in
`endor/ffi/js`. Everything above it is pure MoonBit and testable against
`MockProvider`, so the test suite needs no browser.

**Nothing is hidden.** `Provider::request` reaches any JSON-RPC method the SDK
does not wrap, with raw `Json` in and out. The typed helpers are a convenience,
never a ceiling.

## Where to go

- [Getting started](/guide/getting-started/) — install it, import it, run it
- [Cookbook](/cookbook/) — connect, send, read a token, switch chains, each with
  a demo you can drive
- [Reference](/reference/) — every wrapped method, what it returns, and what is
  deliberately not wrapped
- [Versioning](/reference/versioning/) — what counts as a breaking change while
  this is still `0.x`

## Status

`0.4.0`, published on [mooncakes.io](https://mooncakes.io/docs/poteto0/endor).
Pre-1.0: the API still moves, and [Versioning](/reference/versioning/) says how
much and with what warning.
