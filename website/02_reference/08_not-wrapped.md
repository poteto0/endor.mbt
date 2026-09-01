---
title: Not wrapped yet
description: What is missing, why, and how to do it anyway in the meantime.
---

# Not wrapped yet

Everything here is reachable through
[`Provider::request`](./escape-hatch/) today. The list is what does not have a
typed helper.

## Planned

**Answering whether a signature is an address's.**
[#184](https://github.com/poteto0/endor.mbt/issues/184).
`@eip712.TypedData::digest()` and `@types.Address::recover` both exist and
nothing pairs them: there is no `verify_message` and no `verify_typed_data`. A
contract wallet's signature never recovers to an address, so the ladder is EOA
first, then EIP-1271, then ERC-6492, with SIWE on top of those.
`@stablecoin.Stablecoin`'s `_1271` methods are not this: they *send* a
contract's signature to a token that verifies it, and verify nothing
themselves.

**Mnemonics and HD derivation (BIP-32 / 39 / 44).**
[#226](https://github.com/poteto0/endor.mbt/issues/226).
`@local.LocalAccount::new` takes the 32 bytes of the scalar, and there is no
way to arrive at them from a seed phrase or a derivation path.

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

**Storing a key.** `@local.LocalAccount` signs with a private key this process
holds, but it is handed those bytes and keeps them nowhere else: no keystore
file, no encrypted JSON, no OS keyring. Where the key comes from and how long it
lives are the caller's, and in a browser the answer is still the wallet's —
[Sign with a local key](/cookbook/local-account/) is the warning in full.

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
