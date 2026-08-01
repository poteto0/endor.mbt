---
title: Getting started
description: Install poteto0/endor, import what you need, and read an address.
---

# Getting started

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

The domain types are re-exported from the root package, so `"poteto0/endor"`
gives you `@endor.Address`, `@endor.ChainId` and friends when you need to spell a
type out.

A package that reaches the wallet is a `js` package, because the wallet is a
JavaScript object the browser injected. Say so:

```
supported_targets = "js"
```

Everything below `provider/browser` — the types, the codecs, the ABI layer, the
typed RPC helpers — is backend-agnostic, so a package that only builds calldata
needs no such line.

## The first call

```moonbit
async fn first_call() -> Unit {
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

Three calls, and each answers with a type rather than a string: `require`
finds `globalThis.ethereum`, `require_account` asks the wallet for permission
and an account, and `chain_id` says which chain that answer is about.

## Running it

Every SDK call is `async`, and a browser page is not. `@js.spawn` is the bridge:
it hands an async body to the JS event loop and returns immediately.

```moonbit no-check
fn main {
  @js.spawn(first_call)
}
```

That block is not compiled by CI — a `main` needs a main package, and the checker
that compiles this site's examples puts them all in one library package. Every
other MoonBit block on this site is compiled.

## A page to run it on

Wallets gate `eth_requestAccounts` behind a user gesture, so the flow belongs
behind a button rather than on load. The
[`examples/demo`](https://github.com/poteto0/endor.mbt/tree/main/examples/demo)
module is exactly that: a page, an `index.html`, and the build-and-serve steps in
[`examples/README.md`](https://github.com/poteto0/endor.mbt/blob/main/examples/README.md).

```sh
git clone https://github.com/poteto0/endor.mbt
cd endor.mbt
just example        # builds it and serves http://localhost:8000
```

Open that in a browser with a wallet extension installed.

## The code on this site compiles

Every ` ```moonbit ` block on this site is extracted into a package of the SDK's
own module and compiled by CI, against the working tree rather than against the
last published release:

```sh
just docs-check
```

A block that cannot compile on its own — a `fn main`, a fragment, a `moon.pkg` —
is tagged ` ```moonbit no-check ` and skipped. That tag is opt-in, so an example
is checked unless somebody deliberately said otherwise.

This matters more than it sounds. `moon test` does not reach markdown in this
repository ([#8](https://github.com/poteto0/endor.mbt/issues/8)), so before this
check existed a documented call could be renamed out from under its own
documentation and nothing would say so. Two examples in the README were wrong by
the time it was added.

## Next

- [Cookbook](/cookbook/) — one page per task, each with a demo you can drive
- [How the SDK is shaped](./design/) — the one design decision that changes how
  you write against it
