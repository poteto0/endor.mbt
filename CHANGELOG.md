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

- **Breaking:** `CodecError` gained a fifth variant, `InvalidDecimal`, for a
  string that is not a decimal amount the target can hold. A `catch` that
  matched all four by name is no longer exhaustive; add the case, or a
  catch-all. (#77)
- **Breaking:** EIP-712 typed data moved out of `types` into its own package,
  `endor/eips/eip712`: `@types.TypedData` / `TypedDataDomain` / `TypedDataField`
  are now `@eip712.…`, and `sign_typed_data` takes an `@eip712.TypedData`. It
  sits under `eips/` because an EIP that is a _document to be signed_ is now a
  family — EIP-3009 below is the second, and each states which document while
  `eip712` says how any of them is hashed. Every method
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

- Decoding a **log** into the arguments its event was emitted with, which was
  the last thing the ABI layer could not do: `@abi.decode_log(name~, params~,
  topics~, data~)` checks `topics[0]` against the event's own signature hash,
  reads the `indexed` arguments out of the topics after it and the rest out of
  `data`, and answers in the order the event declares them. `@abi.EventParam` —
  an `AbiType` and whether it is `indexed` — is what carries the half of the
  declaration the wire does not. `@erc20.Erc20::decode_transfer(log)` is that
  for `Transfer`, answering with `(from, to, value)` next to the
  `transfer_topic()` that finds the log in the first place, and `abi/codegen`
  now generates a `decode_…` per event alongside its `…_topic`.
  Two limits, both raised rather than guessed at: an indexed `string`, `bytes`,
  array or struct comes back as the 32-byte `keccak256` the topic holds — the
  value was never in the log — and an `anonymous` event is not decoded, because
  its log carries no `topics[0]` to say which event it is. (#79)
- `Wei::from_units(value, decimals~)` / `Wei::to_units(decimals~)`: the decimal
  amount a person writes, and the whole smallest units the wire carries. The
  scale is passed in because only the token says what it is — 18 for ether, 6
  for USDC, whatever `Erc20::decimals` answers for anything else — and
  `from_ether` / `to_ether` and `from_gwei` / `to_gwei` are the two the chain
  itself fixes. The amount is a `String` and never a `Double`: `0.1` is not
  representable in binary, so a `Double` has lost the value before the SDK could
  see it. An amount **finer** than the scale raises the new
  `CodecError::InvalidDecimal` rather than being truncated, because a digit of
  somebody's money dropped silently is worse than a retype; `to_units` folds
  trailing zeros (`"1.5"`, not `"1.500000000000000000"`) and formats nothing
  else — no separators, no symbol, no fixed width. The decimal-string arithmetic
  underneath is `@codec.decimal_parts` / `decimal_scale` / `decimal_unscale`.
  (#77)
- Four reads and one write that had no typed helper, each of them small enough
  that `Provider::request` was the only reason not to have missed them: (#85)
  - `storage_at(p, who, slot, block?)` — `eth_getStorageAt`, one raw 32-byte
    slot. The only way to see state a contract does not expose, since no ABI
    declares a storage layout; what the word means stays the caller's to know.
    A slot nobody wrote reads as zeroes, not as an absence. The use that
    motivates it is a proxy's implementation address at its fixed EIP-1967 slot
  - `send_raw_transaction(p, raw)` — `eth_sendRawTransaction`. The SDK holds no
    keys and so never _builds_ a signed transaction, but submitting one signed
    elsewhere is exactly what a relayer does — an EIP-3009 authorization is
    signed by a holder with no ether and paid for by somebody else
  - `block_transaction_count_by_number(p, block?)` /
    `block_transaction_count_by_hash(p, hash)` —
    `eth_getBlockTransactionCountBy*`, the count without the hashes.
    `UInt64?`, for the block a node does not have; a height past the head is
    where nodes disagree, some answering `null` and Anvil raising, so `None` is
    the answer to expect rather than to rely on
- `@provider.logs(p, filter)` (`eth_getLogs`): the **past** events, which the
  SDK had no route to at all — a `Log` could only be reached through the receipt
  of a transaction the caller had just sent, so a history, an incoming transfer,
  or a state rebuilt from events all needed `Provider::request` and hand-written
  JSON. What to search for is a `@endor.LogFilter`, built by `range` (an
  optional `from_block` / `to_block`, each a `BlockTag`) or by `at_block` (a
  `BlockHash`) — two constructors rather than one, because the RPC refuses
  `blockHash` together with a range and this way the refused filter cannot be
  spelled. Both take `address=` (one contract or several) and `topics=`, an
  `Array[@endor.Topic?]` whose three states are the point: `Topic::exactly(t)`,
  `Topic::any_of([a, b])` — the OR a flat array of hashes could not express —
  and `None`, which leaves a position unconstrained while still occupying it, so
  a later constraint keeps its index. A node's own range and response limits
  apply as the node's errors; the filter is sent as given and is never split up
  to stay inside them. What comes back is decoded with `@abi.decode_log` (#79),
  which pairs the indexed arguments up with the topics this filter matched on.
  (#78)
- The material an EIP-1559 fee is built from, which the SDK did not have: `Fee`
  could spell `Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~)` but only
  `eth_gasPrice` was wrapped, so a caller that wanted to fill it in had to drop
  to `Provider::request`. (#84)
  - `max_priority_fee_per_gas(p)` — `eth_maxPriorityFeePerGas`, answering
    `@endor.Wei?`. `None` is neither an error nor a zero tip: the method is a
    geth extension rather than a standardized one, and a node that never
    implemented it answers `-32601` (or a provider refusing to forward it,
    EIP-1193's 4200). Every other failure raises as before
  - `fee_history(p, block_count~, newest_block?, reward_percentiles?)` —
    `eth_feeHistory`, over the new `@endor.FeeHistory`: `oldest_block`,
    `base_fee_per_gas`, `gas_used_ratio` and an optional `reward`.
    `base_fee_per_gas` is **one element longer** than the range, its last being
    the already-fixed base fee of the block after the newest — the one a fee for
    the next block is built from. `reward` is `None`, not a list of empty lists,
    when no percentile was asked for. Percentiles are checked for being
    ascending and within 0–100 here, so the error names the argument
  - `estimate_fees(p)` — the two composed into the `Fee` a wallet would have
    built: the latest block's base fee, the suggested tip, and a cap of
    `2 * baseFee + tip`. **The doubling is geth's own default** for a request
    naming no cap, not something EIP-1559 states, and it is written down where
    it is used. Where the tip method is missing the tip is `eth_gasPrice` less
    the base fee, which is the same quantity by construction, floored at zero. A
    chain with no base fee or one pinned at zero has no 1559 market to price
    into and gets `Legacy(gas_price=eth_gasPrice)`. `Auto` is still what a dapp
    normally sends — this is for bidding above the market, replacing a stuck
    transaction, or pricing one as a relayer with no wallet to ask
  - `Fee` now implements `Show`, so the answer can be printed
- EIP-2612 _permit_, as `@eip2612`: the ERC-20 approval **signed instead of
  sent**, so `approve` and the call that spends the allowance stop being two
  transactions. `Permit::new` validates the five members and
  `Permit::typed_data` becomes the document, and `domain` fixes the three
  EIP-712 domain fields the standard fixes. A permit's nonce is the token's
  counter, not random bytes, so it has to be read: `@erc20.Erc20` gained
  `nonces` and `domain_separator`, the two EIP-2612 getters, and `eips/eip2612`
  itself still calls no contract. DAI's non-standard permit is not built —
  compare the token's `PERMIT_TYPEHASH` against `type_hash("Permit")` if you may
  be handed either. (#86)
- `@eip712.TypedDataDomain` gained three methods, all of them things a _token
  extension_ EIP needs and none of them EIP-2612's alone, so EIP-3009 uses them
  too: `separator` is the domain separator on its own, without a message;
  `check_separator(on_chain~)` compares it against the `DOMAIN_SEPARATOR()` a
  verifying contract publishes and refuses a domain it would not verify under —
  the `version` that is `"2"` on USDC and `"1"` almost everywhere else is
  otherwise invisible until the chain rejects the transaction; and `for_token`
  builds the four-field domain a token binds to, which `@eip2612.domain` and
  `@eip3009.domain` are now both named wrappers over. (#86)
- EIP-3009 _Transfer With Authorization_, as `@eip3009`: the holder signs a
  transfer and **somebody else submits it**, so a wallet holding nothing but
  stablecoins can still move them. `Authorization::new` validates the six
  members and becomes either document —
  `transfer_typed_data` (`TransferWithAuthorization`, anyone may submit) or
  `receive_typed_data` (`ReceiveWithAuthorization`, only the recipient may) —
  `CancelAuthorization` burns a nonce before it is used, and `domain` fixes the
  three EIP-712 domain fields the standard fixes, leaving only the token's
  `name()`. What comes back is an `@eip712.TypedData`, so `sign_typed_data`
  sends it and `digest()` says what was signed. Building documents is all it
  does: the preset that _sends_ `transferWithAuthorization` is #73, and it will
  read the authorization back through its accessors. (#74)
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
  constructor this generator cannot type — is _skipped_ with its reason, like
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
  _skips_ every other member by name rather than approximating it. The CLI is a
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
