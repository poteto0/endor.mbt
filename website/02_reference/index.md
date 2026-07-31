---
title: Reference
description: Everything poteto0/endor wraps, what each helper returns, and what it deliberately does not.
---

# Reference

What `poteto0/endor` covers. It reads accounts, balances and the current chain,
evaluates calls without broadcasting them, sends transactions, switches the
wallet between chains, waits for what it sent to be mined, reads blocks and
receipts, calls contracts through their ABI, subscribes to the provider events
that say those answers went stale, and signs messages and EIP-712 typed data.

The SDK is **stateless**: it caches no current account and no current chain.
Every value comes from the wallet at the moment it is asked for, and events are
delivered to callbacks and nowhere else.

## By area

| Page                                | Covers                                                          |
| ----------------------------------- | --------------------------------------------------------------- |
| [Reads](./reads/)                   | accounts, balances, nonces, code, blocks, receipts, `eth_call`    |
| [Writes](./writes/)                 | `send_transaction`, fees, `wait_for_receipt`                      |
| [Chains](./chains/)                 | `switch_chain`, `add_chain`, `switch_or_add_chain`, `ChainParams` |
| [Signing](./signing/)               | `sign_message`, `sign_typed_data`, `TypedData` validation         |
| [Events](./events/)                 | the three EIP-1193 events, `Subscription`, `EventSource`          |
| [ABI and contracts](./abi/)         | `encode` / `decode`, `Contract`, `Erc20`, `deploy`, codegen       |
| [Escape hatch](./escape-hatch/)     | `Provider::request`, and decoding what it answers                 |
| [Not wrapped yet](./not-wrapped/)   | what is missing, and where it sits in the plan                    |
| [Versioning](./versioning/)         | what counts as a breaking change while this is `0.x`              |

Errors are documented once, in the guide: [Errors](/guide/errors/).

## Packages

| Package                  | Contents                                                                                                   |
| ------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `endor` (root)           | re-exports the domain types, so they can be spelled `@endor.Address`                                        |
| `endor/types`            | `Address`, `Hex`, `ChainId`, `Wei`, `Quantity`, `BlockTag`, `CallRequest`, `ChainParams` and their codecs   |
| `endor/codec`            | the wire's arithmetic: hex digits, the 32-byte word, two's complement, the ABI's width rules                |
| `endor/eip712`           | `TypedData` — the EIP-712 document, its validation and the digest a wallet signs                            |
| `endor/crypto`           | `keccak256` — the hash Ethereum builds its identifiers from; a leaf package, depending on nothing else here |
| `endor/abi`              | ABI encode / decode, function selectors and event topics — `AbiType`, `AbiValue`, `AbiError`                |
| `endor/contract`         | `Contract` — typed calls over the ABI layer — and `deploy`                                                  |
| `endor/contract/erc20`   | `Erc20`, the preset over `Contract` for the standard token interface                                        |
| `endor/provider`         | `Provider` / `EventSource` traits, `ProviderError`, typed RPC and event helpers, `MockProvider`             |
| `endor/provider/browser` | `BrowserProvider` — the injected `globalThis.ethereum`, wrapped                                             |
| `endor/ffi/js`           | the only `extern "js"` code: `globalThis.ethereum` access, `request`, `on` / `removeListener`, `spawn`      |

## Backends

`endor`, `endor/crypto`, `endor/codec`, `endor/types`, `endor/eip712`,
`endor/abi`, `endor/contract` and `endor/provider` are backend-agnostic;
`endor/ffi/js` and therefore `endor/provider/browser` are `js`-only, since the
whole point there is a browser-injected object.

So calldata can be built, a typed-data document validated and an answer decoded
with no provider in hand and no `js` target — and the SDK's own tests run against
`@provider.MockProvider` with no browser anywhere.

## Finding a wallet

| Function                                | Answers                                              |
| --------------------------------------- | ---------------------------------------------------- |
| `@browser.BrowserProvider::detect()`    | `Some(p)`, or `None` when nothing is injected        |
| `@browser.BrowserProvider::require()`   | `p`, or raises `NotInstalled`                        |
| `@browser.BrowserProvider::is_metamask()` | whether the injected object identifies as MetaMask |
| `@browser.BrowserProvider::has_events()`  | whether it exposes `on` / `removeListener`         |

## Testing without a wallet

`@provider.MockProvider` is an in-memory `Provider`, so the whole typed RPC layer
can be exercised with no browser:

- `MockProvider::on(method_name~, response~)` — a canned answer for one method
- `MockProvider::on_error(method_name~, error~)` — and a canned failure
- `MockProvider::on_sequence(method_name~, answers~)` — one answer per call, for
  flows that retry (the 4902 fallback is tested with it)
- `MockProvider::emit(event~, payload~)` — it is an `EventSource` too, so event
  handling is testable as well
- `MockProvider::calls()` / `last_call()` — what was asked, and with what
