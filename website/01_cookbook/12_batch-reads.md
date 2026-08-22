---
title: Read many things at once
description: Multicall3 — several contract reads bundled into a single eth_call, all evaluated against the same block.
---

# Read many things at once

Listing anything costs a round trip per field. A token's `name`, `symbol` and
`decimals`, then a `balanceOf` per holder: that is one `eth_call` each, made one
after another, and the wait is the sum of all of them.

A browser extension will sometimes batch those behind your back, which is why
this is easy to miss during development. It is not something to rely on:
[read over plain HTTP](/cookbook/http-rpc/) and nothing is hiding the cost any
more — every read is a full request over the network.

[Multicall3](https://github.com/mds1/multicall) is the chain's own answer. It is
a contract that makes calls on your behalf, so you hand it all of them and it
answers once:

```moonbit
async fn token_summary(
  wallet : @browser.BrowserProvider,
  token : @endor.Address,
  holder : @endor.Address,
) -> Array[@multicall.Outcome] raise @contract.ContractError {
  let erc20 = @contract.Contract::new(token)
  // four reads, one round trip
  @multicall.Multicall3::new().aggregate3(wallet, [
    @multicall.Call::new(erc20.prepare(name="name", outputs=[String])),
    @multicall.Call::new(erc20.prepare(name="symbol", outputs=[String])),
    @multicall.Call::new(erc20.prepare(name="decimals", outputs=[Uint(8)])),
    @multicall.Call::new(
      erc20.prepare(
        name="balanceOf",
        inputs=[Address],
        args=[Address(holder)],
        outputs=[Uint(256)],
      ),
    ),
  ])
}
```

The second thing you get is free and worth as much: the node runs every call in
the batch against **the same block**. Four separate `eth_call`s can straddle a
new block and answer with a `totalSupply` from one and a `balanceOf` from the
next, and nothing in the answers says they did.

## `prepare` is `call` without the call

[`Contract::call`](/cookbook/contract/) encodes the arguments, makes the request
and decodes the answer. Bundling needs the first and last of those without the
middle, so they are separately available:

```moonbit
fn encoded_call(token : @endor.Address, holder : @endor.Address) -> Unit raise {
  let prepared = @contract.Contract::new(token).prepare(
    name="balanceOf",
    inputs=[Address],
    args=[Address(holder)],
    outputs=[Uint(256)],
  )
  // where it would go, and what would be sent — no provider involved
  println(prepared.target().to_string())
  println(prepared.data().to_string())
  // and how to read an answer, whenever one turns up
  let values = prepared.decode(
    @endor.Hex::from_string(
      "0x00000000000000000000000000000000000000000000000000000000000003e8",
    ),
  )
  println("\{values.length()} value(s)")
}
```

A `PreparedCall` is "this calldata, and how to read its answer" as a value. That
is all a batcher needs, and `Contract::call` itself now goes through it, so a
batched read encodes and decodes by exactly the same rules as a direct one.

## One failure does not lose the rest

Each answer is an `Outcome`, in the order the calls were given:

```moonbit
async fn decimals_of(
  wallet : @browser.BrowserProvider,
  tokens : Array[@endor.Address],
) -> Array[Int] raise @contract.ContractError {
  let calls = []
  for token in tokens {
    calls.push(
      @multicall.Call::new(
        @contract.Contract::new(token).prepare(name="decimals", outputs=[Uint(8)]),
      ),
    )
  }
  let answers = []
  for outcome in @multicall.Multicall3::new().aggregate3(wallet, calls) {
    match outcome {
      // `values()` would re-raise it; here a token that is not a token is
      // simply not one, and the rest of the list still renders
      Failed(_) => answers.push(0)
      Returned([Uint(d)]) => answers.push(d.to_int())
      Returned(_) => answers.push(0)
    }
  }
  answers
}
```

`Outcome::Failed` carries a `ContractError`, which is the same error a direct
call raises — the revert is decoded the same way, so `Revert("…")`, `Panic(code)`
and `CustomError(…)` all arrive intact. Pass the contract's `error` declarations
to `Contract::new(address, errors~)` and a custom error's arguments come back
decoded too, exactly as they would from an unbatched call.

That is the whole reason to bundle: nineteen balances should not be lost because
the twentieth address turned out not to be a token. When one call failing does
make the rest meaningless, say so, and the batch fails as a whole instead:

```moonbit
fn all_or_nothing(
  token : @endor.Address,
) -> Array[@multicall.Call] raise @contract.ContractError {
  let erc20 = @contract.Contract::new(token)
  [
    // if this one fails, `aggregate3` reverts and the batch raises
    @multicall.Call::new(
      erc20.prepare(name="totalSupply", outputs=[Uint(256)]),
      allow_failure=false,
    ),
    @multicall.Call::new(erc20.prepare(name="decimals", outputs=[Uint(8)])),
  ]
}
```

What `aggregate3` raises is only ever the batch failing as a whole: the node
refusing the request, or an `allow_failure=false` element bringing it down. An
empty batch answers `[]` without asking the node anything.

## Where it lives

Multicall3 is at `0xcA11bde05977b3631167028862bE2a173976CA11` on every major
chain — the same address everywhere, because it was deployed from the same key
at the same nonce. That is why `new()` takes none.

On a chain that has neither that deployment nor any other, a batch would be sent
to an address holding no code, which answers with empty return data rather than
with an error — a decode failure that says nothing about the cause. Ask first:

```moonbit
async fn batchable(
  wallet : @browser.BrowserProvider,
  private_deployment : @endor.Address,
) -> Bool raise @contract.ContractError {
  // the canonical one, wherever it is deployed
  let canonical = @multicall.Multicall3::new()
  // or one somebody deployed themselves — a private chain, or a test node
  let mine = @multicall.Multicall3::new(address=private_deployment)
  canonical.is_deployed(wallet) || mine.is_deployed(wallet)
}
```

A caller that finds `false` falls back to reading one at a time.

## What this is not

It is not JSON-RPC batching — the `[{…}, {…}]` array a node will accept as one
request. That is a transport concern, it can carry methods other than `eth_call`,
and it gives no same-block guarantee, because the node is free to run each
element against whatever state it has by the time it gets there. Multicall3 is
one call, executed once, on one block. The SDK has that fold too, over HTTP and
[only where you ask for it](/cookbook/http-rpc/#one-post-for-many-calls); the two
compose, and neither replaces the other.

Nothing here collects your reads behind your back. Calls are bundled because you
bundled them, and a `Contract::call` is still exactly one `eth_call` — over a
batched endpoint, one `eth_call` in a POST it may be sharing.

Writes are not batchable this way at all. `aggregate3` runs inside a single
`eth_call`, which changes nothing — several *transactions* in one is a different
problem, and it needs a contract that holds the funds or an account-abstraction
wallet, not this.
