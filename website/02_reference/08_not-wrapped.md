---
title: Not wrapped yet
description: What is missing, why, and how to do it anyway in the meantime.
---

# Not wrapped yet

Everything here is reachable through
[`Provider::request`](./escape-hatch/) today. The list is what does not have a
typed helper.

## Planned

**Decoding a log into an event's arguments.** A `Log`'s `topics` are raw `Hex`.
`@abi.event_topic` computes the topic to match `topics[0]` against and
`@abi.decode` reads the non-indexed arguments out of `data`, but pairing the
*indexed* arguments back up with their topics is not wrapped. In the meantime:

```moonbit
fn find_transfers(receipt : @endor.TransactionReceipt) -> Array[@endor.Log] {
  let topic = @abi.event_topic("Transfer(address,address,uint256)")
  receipt.logs.filter(log => log.topics.get(0) is Some(t) && t == topic)
}
```

**EIP-6963.** The SDK takes `globalThis.ethereum`, which is whichever wallet won
the race to inject itself. Enumerating several injected providers and letting the
user pick is not implemented.

**Computing the EIP-712 digest for signing.**
`endor/eip712` implements the hashing, but `sign_typed_data` hands the document
to the wallet and lets it hash — which is correct for signing.
[#45](https://github.com/poteto0/endor.mbt/issues/45) is about the case that
needs the digest locally, which is EIP-1271 contract signature verification.

**An HTTP JSON-RPC transport.**
[#19](https://github.com/poteto0/endor.mbt/issues/19). Today the only `Provider`
that reaches a real chain is the injected browser wallet, which means the SDK
cannot be used from a server or a script. The trait is already the right shape
for it — that is why `Provider` and `EventSource` are separate.

**`newHeads` subscription to speed up receipt waiting.**
[#42](https://github.com/poteto0/endor.mbt/issues/42). `wait_for_receipt` polls.

## Not planned

**`bytesN` beyond 32** in the ABI layer. No contract can declare one: the ABI
specification stops at `bytes32`.

**Key management of any kind.** No private keys, no local signing, no mnemonics.
The wallet holds the key and that is the entire security model — an SDK that
could sign without the wallet would be an SDK that could sign without the user.

**A cached "current account".** The SDK is stateless on purpose; see
[How the SDK is shaped](/guide/design/). A cache would be wrong the moment the
user touched their extension, and wrong silently.

## Where the plan lives

[`docs/roadmap.md`](https://github.com/poteto0/endor.mbt/blob/main/docs/roadmap.md)
in the repository, and the
[issue tracker](https://github.com/poteto0/endor.mbt/issues).
