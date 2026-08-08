---
title: Read without a wallet
description: Point the SDK at a node URL over HTTP JSON-RPC — no extension, and not only in a browser.
---

# Read without a wallet

A wallet is needed to **sign**. It is not needed to **read**. Every other page in
this cookbook drives `globalThis.ethereum`, because a dapp has one; a script, a
CLI, a backend job and a test do not, and none of them need one to ask a node
what a balance is.

`@endpoint.at` is that: a `Provider` that speaks JSON-RPC 2.0 over HTTP, built
from nothing but a URL.

<div class="alert alert--status" role="note">
  <div class="alert__title">Why this page has no demo</div>
  <div class="alert__description">

Every other recipe here runs in your browser against your wallet. This one needs
a node URL, and a public one that would accept a cross-origin POST from this site
is either rate-limited into uselessness or an API key in plain sight. The code
below is compiled by CI like every other block on this site, and it is what
[`e2e/http_test.mbt`](https://github.com/poteto0/endor.mbt/blob/main/e2e/http_test.mbt)
runs against a real node.

  </div>
</div>

## The import

```
import {
  "poteto0/endor/provider",               // @provider — typed RPC, errors
  "poteto0/endor/provider/http",           // @http — HttpProvider, HttpTransport
  "poteto0/endor/provider/http/endpoint",  // @endpoint — a node at a URL
}
```

No `supported_targets` line is needed for this one. `@browser` forces `js`
because a browser-injected object only exists there; an HTTP endpoint exists
everywhere, and `@endpoint` is written against
[`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async)'s HTTP
client — `fetch` on `js`, sockets and TLS on `native` and `wasm`. The same code
below runs in a page, in a CLI and on a server.

## The call

```moonbit
async fn chain_over_http(url : String) -> Unit {
  try {
    // raises ProviderError::internal if `url` is not an http(s) URL with a host
    let node = @endpoint.at(url)
    let chain = @provider.chain_id(node) // eth_chainId, over one POST
    let height = @provider.block_number(node) // eth_blockNumber, over another
    println("chain \{chain.to_uint64()} is at block \{height}")
  } catch {
    e => println("the node did not answer: \{e}")
  }
}
```

There is no connect step and nothing to authorize, because there is nobody to
ask: a node serves reads to whoever POSTs to it. `at` validates the URL up
front — an `http://` or `https://` scheme and a host standing after it — so a
typo is caught where it was made rather than one call later, as a connection
failure with a stack that points at the wrong place.

Each provider numbers its own requests, starting at 1 and incrementing, and
checks the id that comes back against the one it sent. A node that answers a
different request than the one it was asked raises
`ProviderError::internal` rather than being decoded into a plausible-looking
wrong answer.

## A node that wants a key

Hosted providers authenticate either in the path or in a header. The path form
needs nothing special; the header form is `headers~`, and what you pass is sent
with every request on top of the `content-type` JSON-RPC needs:

```moonbit
async fn balance_from_a_paid_node(
  url : String,
  key : String,
  who : @endor.Address,
) -> @endor.Wei raise {
  let node = @endpoint.at(url, headers={ "Authorization": "Bearer \{key}" })
  @provider.balance(node, who)
}
```

Do not put a key in a page. Anything that ships to a browser ships the key with
it — this form belongs in a CLI or on a server, which is the same reason this
transport exists.

## Everything above it is unchanged

`HttpProvider` is a `Provider` like any other, so the typed helpers, the ABI
layer and the contract presets do not know or care which one they were handed:

```moonbit
async fn token_supply_over_http(
  url : String,
  token : @endor.Address,
) -> BigInt raise {
  let node = @endpoint.at(url)
  @erc20.Erc20::new(token).total_supply(node)
}
```

Writing a function against the `Provider` trait rather than against a concrete
provider is what lets the same code serve both:

```moonbit
async fn[P : @provider.Provider] holdings(
  p : P,
  who : @endor.Address,
) -> @endor.Wei raise {
  @provider.balance(p, who) // a wallet, an endpoint, or a MockProvider
}
```

## What HTTP cannot do

Two things, and the SDK says so about both rather than failing obscurely.

**The wallet methods.** Every `wallet_*` method and `eth_requestAccounts` raise
`UnsupportedMethod` — without a round trip, since there is nothing behind a URL
to prompt a human:

| Call                                      | Against an endpoint                      |
| ----------------------------------------- | ---------------------------------------- |
| `@provider.request_accounts` / `require_account` | `UnsupportedMethod`               |
| `@provider.switch_chain` / `add_chain`    | `UnsupportedMethod`                      |
| `@provider.accounts`                      | forwarded — a dev node answers it        |
| `@provider.sign_message` / `sign_typed_data` | forwarded — an unlocked node signs    |
| `@provider.send_transaction`              | forwarded — an unlocked node broadcasts  |

The refusals stop at the ones that need a wallet **UI**. A node with unlocked
accounts — Anvil, a dev node — really does serve `eth_accounts`,
`personal_sign` and `eth_sendTransaction`, so refusing them locally would be a
lie. A node that cannot serve a method answers JSON-RPC `-32601`, which arrives
as `UnsupportedMethod` anyway. That is what makes the whole
[e2e suite](https://github.com/poteto0/endor.mbt/blob/main/docs/e2e.md) able to
run against Anvil.

**Events.** `HttpProvider` implements `Provider` and deliberately not
`EventSource`, so `@provider.on_accounts_changed` and friends will not compile
against one. Plain HTTP pushes nothing: there is no `accountsChanged` behind a
POST endpoint, and no `chainChanged` either, because there is no user switching
anything. This is exactly why the two traits are
[separate](/reference/events/#eventsource-is-a-separate-trait).

## Errors

The same four suberrors as everywhere else, from one more source. Whatever is
the **transport** failing — the request never landing, a non-2xx status, an
unreadable body — is `ProviderError::internal` with the status and the URL in
its message. A JSON-RPC `error` object is not a transport failure: it is a
well-formed answer, and it is mapped through the same code table as a wallet's,
so a revert from a node is the `Reverted` you already handle.

```moonbit
async fn read_or_explain(url : String, who : @endor.Address) -> Unit {
  try {
    let node = @endpoint.at(url)
    println("\{@provider.balance(node, who).to_bigint()} wei")
  } catch {
    // the node said no, with a code: -32601 unknown method, -32000 and its
    // neighbours for everything a node rejects
    Rpc(code~, message~) => println("node error \{code}: \{message}")
    UnsupportedMethod => println("that one needs a wallet")
    // the URL was wrong, the host was unreachable, or the status was not 2xx
    e => println("could not reach it: \{e}")
  }
}
```

## Your own HTTP

`Endpoint` is one implementation of `@http.HttpTransport`, which is a trait with
a single method: POST a body, answer with the response text. Implement it when
the HTTP is yours — a client with retries or a connection pool, an
authenticating proxy, a recorded fixture in a test — and hand it to
`HttpProvider::new`:

```moonbit
///|
/// A transport that answers from a table instead of a network, so a test can
/// drive the whole SDK over the JSON-RPC framing with nothing listening.
priv struct Recorded {
  answers : Map[String, String]
}

///|
impl @http.HttpTransport for Recorded with fn post(self, body) {
  match self.answers.get(body) {
    Some(answer) => answer
    None => raise @provider.ProviderError::internal("no answer recorded")
  }
}

///|
async fn read_from_a_recording(answers : Map[String, String]) -> Unit raise {
  let provider = @http.HttpProvider::new(Recorded::{ answers, })
  println(@provider.chain_id(provider).to_uint64())
}
```

`provider/http` itself imports nothing but `provider` and declares no target, so
the framing — ids, the envelope, the error mapping — builds on `wasm-gc` too.
That is the one backend `@endpoint` cannot reach, and a host that supplies its
own `HttpTransport` gets the rest of the SDK there anyway.

<div class="alert alert--status" role="note">
  <div class="alert__title">Next</div>
  <div class="alert__description">

[Call any contract](/cookbook/contract/) — the same reads, through an ABI. Every
example there takes a `Provider`, so an endpoint works in place of the wallet.

  </div>
</div>
