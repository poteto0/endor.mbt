---
title: Reference
description: Everything poteto0/endor wraps, what each helper returns, and what it deliberately does not.
---

# Reference

What `poteto0/endor` covers. It reads accounts, balances and the current chain,
evaluates calls without broadcasting them, sends transactions — signed by a
wallet or by a key it holds itself — switches the wallet between chains, waits
for what it sent to be mined, reads blocks and receipts, calls contracts through
their ABI and batches those calls into one round trip, subscribes to the
provider events that say those answers went stale, and signs messages and
EIP-712 typed data.

The SDK is **stateless**: it caches no current account and no current chain.
Every value comes from the provider at the moment it is asked for, and events
are delivered to callbacks and nowhere else.

## By area

| Page                                | Covers                                                          |
| ----------------------------------- | --------------------------------------------------------------- |
| [Reads](./reads/)                   | accounts, balances, nonces, code, blocks, receipts, `eth_call`    |
| [Writes](./writes/)                 | `send_transaction`, `WalletClient`, fees, `wait_for_receipt`      |
| [Chains](./chains/)                 | `switch_chain`, `add_chain`, `switch_or_add_chain`, `ChainParams` |
| [Signing](./signing/)               | `sign_message`, `sign_typed_data`, `TypedData` validation         |
| [Events](./events/)                 | the three EIP-1193 events, `Subscription`, `EventSource`          |
| [ABI and contracts](./abi/)         | `encode` / `decode`, `Contract`, `Erc20`, `Stablecoin`, `Multicall3`, `deploy` |
| [Escape hatch](./escape-hatch/)     | `Provider::request`, and decoding what it answers                 |
| [Not wrapped yet](./not-wrapped/)   | what is missing, and where it sits in the plan                    |
| [Versioning](./versioning/)         | what counts as a breaking change while this is `0.x`              |

Errors are documented once, in the guide: [Errors](/guide/errors/) — and what
the providers send again before an error reaches you is
[Retries](/guide/retries/).

## Packages

| Package                  | Contents                                                                                                   |
| ------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `endor` (root)           | re-exports the domain types, so they can be spelled `@endor.Address`                                        |
| `endor/types`            | `Address`, `Hex`, `ChainId`, `Wei`, `Quantity`, `BlockTag`, `CallRequest`, `ChainParams` and their codecs   |
| `endor/codec`            | the wire's arithmetic: hex digits, the 32-byte word, two's complement, the ABI's width rules                |
| `endor/codec/rlp`        | RLP — the encoding a transaction is signed and broadcast in                                                 |
| `endor/eips/eip712`      | `TypedData` — the EIP-712 document, its validation and the digest a wallet signs                            |
| `endor/eips/eip3009`     | `Authorization` — the EIP-3009 transfer a holder signs and somebody else submits                            |
| `endor/eips/eip2612`     | `Permit` — the ERC-20 approval, signed instead of sent                                                      |
| `endor/eips/eip191`      | the `\x19Ethereum Signed Message:` prefix, and the digest a `personal_sign` is over                         |
| `endor/crypto/keccak`    | `keccak256` — the hash Ethereum builds its identifiers from; a leaf package, depending on nothing else here |
| `endor/crypto/secp256k1` | the curve: `PrivateKey`, its public key, and the recoverable `Signature` over a digest                       |
| `endor/abi`              | ABI encode / decode, function selectors and event topics — `AbiType`, `AbiValue`, `AbiError`                |
| `endor/contract`         | `Contract` — typed calls over the ABI layer — `PreparedCall` and `deploy`                                   |
| `endor/contract/erc20`   | `Erc20`, the preset over `Contract` for the standard token interface                                        |
| `endor/contract/multicall` | `Multicall3` — many prepared calls, one `eth_call`, one block                                             |
| `endor/contract/stablecoin` | `Stablecoin` — `Erc20` plus the EIP-3009 and EIP-2612 calls a submitter sends                            |
| `endor/account`          | the `Account` trait — sign a transaction, a message, typed data, a 7702 authorization — and `AccountError`                        |
| `endor/account/local`    | `LocalAccount` — a private key held in this process, signing with no prompt                                 |
| `endor/wallet`           | `WalletClient`, a provider paired with an account, and `JsonRpcAccount`, the account a wallet holds         |
| `endor/provider`         | `Provider` / `EventSource` traits, `ProviderError`, typed RPC and event helpers, `MockProvider`             |
| `endor/provider/browser` | `BrowserProvider` — the injected `globalThis.ethereum`, wrapped                                             |
| `endor/provider/http`    | `HttpProvider` — JSON-RPC 2.0 over an `HttpTransport`, the trait a caller's own HTTP fits                   |
| `endor/provider/http/endpoint` | `Endpoint` and `at(url, headers?)` — a node at a URL, over `moonbitlang/async`'s HTTP client          |
| `endor/ffi/js`           | the only `extern "js"` code: `globalThis.ethereum` access, `request`, `on` / `removeListener`, `spawn`      |

## Backends

Every package above is backend-agnostic except two, and both are named by what
they are. `endor/ffi/js` — and therefore `endor/provider/browser`, the only
package that imports it — is `js`-only, since a browser-injected object is the
whole point there. `endor/provider/http/endpoint` is `js`, `native` and `wasm`:
every backend `moonbitlang/async`'s HTTP client reaches, which is every one but
`wasm-gc`.

So calldata can be built, a typed-data document validated, a transaction signed
and an answer decoded with no provider in hand and no `js` target — and the
SDK's own tests run against `@provider.MockProvider` with no browser anywhere.

## Reaching a chain

| Provider                                  | Speaks to                     | Signs? | Pushes events? |
| ----------------------------------------- | ----------------------------- | ------ | -------------- |
| `@browser.BrowserProvider`                | the injected wallet           | yes    | yes            |
| `@endpoint.at(url, headers?)`             | a node over HTTP JSON-RPC     | only what an unlocked node signs | no |
| `@http.HttpProvider::new(t)`              | whatever `t` POSTs to         | —      | no             |
| `@provider.MockProvider`                  | canned answers, in memory     | —      | yes            |

Each is a `Provider`, so everything above the trait — the typed reads,
`Contract`, `Erc20`, the ABI layer — takes any of them. The browser one and the
mock are also `EventSource`: HTTP pushes nothing, which is why the two traits
are [separate](./events/#eventsource-is-a-separate-trait).

The **Signs?** column is about the transport only. A key the transport does not
hold can still sign: `@wallet.WalletClient` pairs any of these with an
`@account.Account`, and `@local.LocalAccount` signs in this process, so an
endpoint that holds no key still sends a signed transaction. [Sign with a local
key](/cookbook/local-account/) is the worked page.

Against an endpoint, the methods that need a wallet UI — every `wallet_*`, plus
`eth_requestAccounts` — raise `UnsupportedMethod` without a round trip.
Everything a node can serve is forwarded, including `eth_sendTransaction`
against an unlocked account. [Read without a wallet](/cookbook/http-rpc/) is the
worked page.

## Finding a wallet

| Function                                | Answers                                              |
| --------------------------------------- | ---------------------------------------------------- |
| `@browser.BrowserProvider::detect()`    | `Some(p)`, or `None` when nothing is injected        |
| `@browser.BrowserProvider::require()`   | `p`, or raises `NotInstalled`                        |
| `@browser.BrowserProvider::is_metamask()` | whether the injected object identifies as MetaMask |
| `@browser.BrowserProvider::has_events()`  | whether it exposes `on` / `removeListener`         |
| `@browser.BrowserProvider::discover()`  | every wallet that announced itself (EIP-6963) within the deadline, falling back to the injected one |
| `@browser.BrowserProvider::on_announce()` | a `Subscription` fed by EIP-6963 announcements as they arrive |

`discover` is the one to draw a picker from; `on_announce` is the honest shape of
EIP-6963, where enumeration never finishes. [Connect a
wallet](/cookbook/connect/#two-wallets-installed) is the worked page.

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
