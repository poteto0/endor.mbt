---
title: Not wrapped yet
description: What is missing, why, and how to do it anyway in the meantime.
---

# Not wrapped yet

Everything here is reachable through
[`Provider::request`](./escape-hatch/) today. The list is what does not have a
typed helper.

## Planned

**Computing the EIP-712 digest for signing.**
`endor/eips/eip712` implements the hashing, but `sign_typed_data` hands the document
to the wallet and lets it hash — which is correct for signing.
[#45](https://github.com/poteto0/endor.mbt/issues/45) is about the case that
needs the digest locally, which is EIP-1271 contract signature verification.
`@stablecoin.Stablecoin`'s `_1271` methods are the other side of that: they
*send* a contract's signature to a token that verifies it, and verify nothing
themselves.

**`newHeads` subscription to speed up receipt waiting.**
[#42](https://github.com/poteto0/endor.mbt/issues/42). `wait_for_receipt` polls.
Nothing in the SDK subscribes to a node: there is no WebSocket transport, and
[HTTP](/cookbook/http-rpc/) has nothing to subscribe over — `HttpProvider` is a
`Provider` and not an `EventSource` for that reason.

## Not planned

**`bytesN` beyond 32** in the ABI layer. No contract can declare one: the ABI
specification stops at `bytes32`.

**Recovering an indexed `string`, `bytes`, array or struct from a log.**
[`@abi.decode_log`](./abi/#reading-a-log) answers with the 32 bytes the topic
holds, which are the `keccak256` of the value and not the value. This is not a
gap in the SDK: those bytes are all the log ever carried, so nobody can invert
them. Hash a candidate value and compare, or read the argument from a
non-indexed copy if the contract emits one.

**Decoding a log of an `anonymous` event.** Such a log has no `topics[0]`, so
nothing in it says which event it is, and `decode_log` would have to take the
caller's word for it and decode into the wrong values when the word was wrong.
`@abi.decode` over `data` and the topics by hand is the honest version, and it is
where the assumption is the caller's own.

**Key management of any kind.** No private keys, no local signing, no mnemonics.
The wallet holds the key and that is the entire security model — an SDK that
could sign without the wallet would be an SDK that could sign without the user.

**Bundling calls nobody asked to have bundled.** The `[{…}, {…}]` array a node
accepts as one request is wrapped, but only where it was asked for:
`HttpProvider::with_batch` opts an endpoint into a window, and a provider
without it sends one POST per call, as it always did. There is no scheduler
folding the calls of a provider that never asked. See
[Read without a wallet](/cookbook/http-rpc/#one-post-for-many-calls).

A transport batch also gives no same-block guarantee — the node runs each
element against whatever state it has by the time it gets there. Reads that must
see one block are [Multicall3](/cookbook/batch-reads/), which is one `eth_call`,
executed once.

**A cached "current account".** The SDK is stateless on purpose; see
[How the SDK is shaped](/guide/design/). A cache would be wrong the moment the
user touched their extension, and wrong silently.

## Where the plan lives

[`docs/roadmap.md`](https://github.com/poteto0/endor.mbt/blob/main/docs/roadmap.md)
in the repository, and the
[issue tracker](https://github.com/poteto0/endor.mbt/issues).
