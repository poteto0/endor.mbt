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

### Fixed

- `types/` no longer `abort`s anywhere: the two exhaustiveness-only branches in
  EIP-712 validation and encoding raise `InvalidJson` like every other
  unusable type name. (#56)

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
