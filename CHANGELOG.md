# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/) (pre-1.0: expect
breaking changes on any minor bump).

**Until 1.0, breaking changes are accepted whenever they make the API right.**
The public surface is still being settled, so a signature that turns out wrong —
a missing `raise`, a type that should not be public, a name that reads badly —
gets fixed rather than kept for compatibility. Every such change is listed under
**Changed** with what to do about it. From 1.0 onward, the usual SemVer promise
applies.

## [Unreleased]

### Added

- An HTTP JSON-RPC transport, so the read layer works without a browser wallet:
  `@http.HttpProvider` (`provider/http`) is a `Provider` that frames each call
  as JSON-RPC 2.0 — unique, monotonic ids, checked against the id the answer
  carries — over an `@http.HttpTransport` the caller supplies, and
  `@fetch.FetchTransport` (`provider/http/fetch`) is that transport over
  `fetch`. A node URL is all it needs:

  ```moonbit
  let provider = @http.HttpProvider::new(
    @fetch.FetchTransport::new("http://127.0.0.1:8545"),
  )
  let chain = @provider.chain_id(provider)
  ```

  `provider/http` declares no `supported_targets` and imports no FFI, so a
  non-JS HTTP client is a transport away. The methods that need a wallet UI —
  every `wallet_*`, plus `eth_requestAccounts` — raise `UnsupportedMethod`
  without a round trip; everything a node can serve, including
  `eth_sendTransaction` against an unlocked account, is forwarded.
  `HttpProvider` implements `Provider` and deliberately not `EventSource`:
  plain HTTP pushes nothing. (#19)
- `@provider.ProviderError::from_error_object`, the decoder for the
  `{ code, message }` object EIP-1193 and JSON-RPC both carry. It was already
  there privately, behind the event path's `from_json`; a node's `error` member
  needed the same reading, and one mapping is better than two. (#19)

### Changed

- **Breaking:** EIP-712 typed data moved out of `types` into its own package:
  `@types.TypedData` / `TypedDataDomain` / `TypedDataField` are now
  `@eip712.…`, and `sign_typed_data` takes an `@eip712.TypedData`. Every method
  is unchanged, as is `@endor.TypedData` — the root re-exports the three types
  from their new home, so a caller that spells them `@endor.…` needs no change.
  `types` also gained a `codec` layer underneath it (`@codec`): the hex-digit
  and 32-byte-word arithmetic the ABI encoder and EIP-712 both work in, and the
  ABI's width and size rules as predicates. `AbiType` / `AbiValue` / `AbiError`
  stay in `types`, where the domain types are. (#55)
- **Breaking:** `CodecError` is now `pub(all)`, so a layer above the domain
  types can raise one — which is what `@eip712` does for a document whose shape
  does not match what it declares. (#55)
- **Breaking:** `AbiError` now lives in `types` and is re-exported by `abi`, so
  `@abi.AbiError` and `@endor.AbiError` both name it and `raise`/`catch` keep
  working. Only its _constructors_ moved: a caller that raises one itself writes
  `@types.InvalidData(…)` rather than `@abi.InvalidData(…)`. `AbiType::name`
  raises it too, in place of `CodecError` — the width and size rules `abi` and
  EIP-712 both check now have one statement each, in `codec`. (#55)
- **Breaking:** `TypedData::encode_type` / `TypedData::type_hash` now
  `raise CodecError`. A type name the document does not define used to panic
  through an `unwrap`; it now raises `InvalidJson("<name> is not defined")`, the
  same way `encodeData` already reported it. Callers add `try` / `raise` at the
  call site. (#56)

### Added

- A logo: a round green planet with a small grey satellite off its lower right,
  as `website/public/logo.svg`. It is the mark beside the site title in the
  header, the favicon, and the top of the README.
- **Experimental:** `abi/codegen` reads a compiler **artifact** as well as a
  bare ABI array — `solc --combined-json abi,bin`, solc's standard JSON, a
  Foundry or a Hardhat artifact — and an artifact carries the creation code, so
  the generated struct gets a `creation_code()` and a `deploy` over
  `@contract.deploy` that takes the constructor's arguments and answers with the
  contract it created. `Generated::deploys` says whether it did, and
  `endor-cli abi` reports it per file. The code is validated as hex while
  generating, so the generated `Hex::from_string` cannot fail; bytecode that
  cannot be deployed — unlinked libraries, the empty bytecode of an interface, a
  constructor this generator cannot type — is *skipped* with its reason, like
  any other member. An artifact holding several contracts is refused by name
  rather than resolved. `generate`'s second parameter is now `document` rather
  than `abi_json`. (#67)
- Contract deployment: `@contract.deploy` sends the creation code with its
  constructor arguments encoded behind it, waits for the receipt and answers
  with the `Contract` now at the address it names; `send_deployment` is the same
  broadcast without the wait, and `deployment_data` is the `data` both build.
  A deployment that reverted, or whose receipt names no `contractAddress`,
  raises the new `ContractError::Deployment`. (#63)
- `Hex::concat`, which joins two hex byte strings without taking either apart:
  both of `Hex`'s rules hold of the halves, so they hold of the whole, and the
  caller gets no error it has no way to cause. `deployment_data` is what it
  exists for. (#63)
- **Experimental:** `abi/codegen` renders the source of a `@contract.Contract`
  preset — a struct, a method per ABI function, a topic getter per event — from
  a JSON ABI document, and `endor-cli abi` writes one file per document from a
  checked-in `endor.yaml` — which `endor-cli init` writes, along with the input
  directory it names, so a fresh project reaches a working generator in one
  command. It generates only what it can type without guessing
  (`address`, `bool`, `string`, `uintN`, `intN`, single return values) and
  *skips* every other member by name rather than approximating it. The CLI is a
  separate module (`poteto0/endor-cli`, in `cmd/`), so `moonbitlang/x` and a
  `native` build stay out of the SDK's dependency graph. Not part of the stable
  surface: read what it produces before shipping it. (#48)
- `@contract.uint_answer` / `int_answer` / `string_answer` / `bool_answer` /
  `address_answer`: the single value a getter answered with, or a
  `ContractError` naming the getter. They were private helpers in `Erc20`;
  generated presets need them, so they are public and there is one per type the
  SDK can name. `int` and `uint` stay separate deliberately — the same 32 bytes
  differ only in how the top bit reads. (#48)
- `Hex::from_digits`, which builds a hex byte string from the digits alone —
  no `0x`, no `Bytes` in between. It is where both of `Hex`'s rules are now
  stated: `from_string` is this with the prefix taken off first, so a shortcut
  past the representation is not a shortcut past the rule. `@abi.encode` is the
  caller it exists for. (#54)

### Fixed

- `types/` no longer `abort`s anywhere: the two exhaustiveness-only branches in
  EIP-712 validation and encoding raise `InvalidJson` like every other
  unusable type name. (#56)
- validate abi value word on abi decoding. (#53)

### Performance

- `@abi.encode` / `@abi.encode_call` no longer spell their result as `Bytes`
  only to spell it straight back as the same hex digits. Encoding 50,000
  `uint256` (1.6 MB of calldata) went from 1.28 s to 0.08 s — **15× faster**.
  (#54)
- `Hex::from_bytes` writes a whole byte's two digits from a 256-entry table
  rather than a character at a time, and `Hex::to_bytes` reads the digits in
  one pass with no intermediate `Array[Byte]`; both are about **2× faster**.
  They are on the path of every digest, every signature and every
  `eth_getCode` answer, not just the ABI's. (#54)

## [0.4.0] - 2026-07-28

### Added

- EIP-712 typed data hashing: `encodeType` / `typeHash` / `encodeData` /
  `hashStruct` / `domainSeparator` (#45)
- Contract layer: ABI encode/decode and typed contract calls (#18)
- Message signing: `personal_sign` / `eth_signTypedData_v4` (#14)
- Block / receipt reads and `wait_for_receipt` (#11)
- Provider events: `accountsChanged` / `chainChanged` / `disconnect` (#16)

### Changed

- Reworked the contract layer API ahead of release (#46)

## [0.3.0] - 2026-07-27

### Added

- `eth_sendTransaction` as a typed helper (#10)
- `eth_call` / `eth_estimateGas` as typed helpers (#9)
- `crypto/`: a from-scratch MoonBit implementation of keccak256 (#28)
- `types/`: EIP-55 checksummed addresses (#29)
- `require_account` helper for wallet connection (#36)
- e2e tests: verify `BrowserProvider` against Anvil standing in for an
  injected wallet (#12)

## [0.2.0] - 2026-07-25

### Added

- Typed helpers for the basic read methods (#3)
- Chain switching: `switch` / `add` / EIP-4902 fallback (#15)
- Release automation: tag push → `moon publish` (#7)

### Changed

- `provider/` no longer depends on `ffi/js` directly; browser wiring moved to
  `provider/browser` (#4)

## [0.1.0] - 2026-07-25

### Added

- MetaMask connection via the EIP-1193 provider standard
- Basic read methods

[Unreleased]: https://github.com/poteto0/endor.mbt/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/poteto0/endor.mbt/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/poteto0/endor.mbt/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/poteto0/endor.mbt/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/poteto0/endor.mbt/releases/tag/v0.1.0
