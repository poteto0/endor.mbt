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

- `message()` and `is_retryable()` on all four error types — `ProviderError`,
  `ContractError`, `AbiError` and `CodecError` — so one handler works whichever
  one was caught:

  ```moonbit
  try @provider.chain_id(node) |> ignore catch {
    UserRejected => ()
    e =>
      if e.is_retryable() { retry() } else { show(e.message()) }
  }
  ```

  `message()` is one line written for a person — no variant name, no URL, no
  JSON-RPC code — as against `Show`, which keeps all three and belongs in a log.
  `is_retryable()` is true for the failures that are about _this attempt_
  (`Transport`, `Timeout`, `HttpStatus` 429 / 5xx, the `-32005` a hosted RPC
  rate-limits with) and false for everything already decided. The two types that
  talk to the wire, `ProviderError` and `ContractError`, add `code()` — the
  EIP-1193 / EIP-1474 number, or `None` for what never reached the protocol —
  and `ContractError` adds `revert_reason()`, the string a `require(cond, "…")`
  carried. (#113)

- `@endor.ProviderError` and `@endor.ContractError`: the root re-exports both,
  so the public error surface is four types spelled from one package rather than
  two that need `@provider` and `@contract` imported to be named. (#113)
- A timeout on every HTTP request. `@endpoint.at` takes `timeout~` in
  milliseconds (30 000 by default) bounding the whole POST — connecting, sending
  and reading the body — after which the call raises `Timeout` instead of
  waiting on a node that stopped answering. (#113)
- **Batched reads**, so a listing costs one RPC round trip rather than one per
  field. `@multicall.Multicall3::new().aggregate3(p, calls)` makes every call in
  a single `eth_call` through
  [Multicall3](https://github.com/mds1/multicall) and answers with one
  `@multicall.Outcome` per call, in order — which also means every read in the
  batch saw the same block. A `@multicall.Call` is a prepared call plus
  `allow_failure` (`true` by default), and an `Outcome` is `Returned(values)` or
  `Failed(error)`: one call reverting does not take the others down, and its
  revert is decoded exactly as a direct call's is, so `Revert` / `Panic` /
  `CustomError` all arrive — with a custom error's arguments filled in when the
  `Contract` was given the matching `ErrorDef`s. What _does_ raise is the batch
  failing as a whole: the node refusing it, or an element with `allow_failure =
false` bringing `aggregate3` down. An empty batch answers `[]` and asks the
  node nothing. The address defaults to the canonical
  `0xcA11bde05977b3631167028862bE2a173976CA11` — the same on every major chain
  — and `Multicall3::new(address=…)` points at another deployment;
  `is_deployed` says whether there is a contract there at all, for the chains
  where there is not. No JSON-RPC batching and no implicit scheduler: calls are
  bundled because the caller bundled them. (#88)
- `@contract.Contract::prepare`, which splits `Contract::call` into the encode
  and the decode it was: it answers with a `@contract.PreparedCall` — the
  target, the calldata, the declared outputs and the contract's own `ErrorDef`s
  — that `PreparedCall::decode` reads an answer back with and
  `PreparedCall::revert` reads raw revert bytes with. Holding an encoded call as
  a value is what makes bundling possible at all, and `Contract::call` is now
  `prepare` → `eth_call` → `decode`, so there is one encode path and one decode
  path. Its behaviour is unchanged. (#88)
- An HTTP JSON-RPC transport, so the read layer works without a browser wallet
  **and on every backend**: `@http.HttpProvider` (`provider/http`) is a
  `Provider` that frames each call as JSON-RPC 2.0 — unique, monotonic ids,
  checked against the id the answer carries — and `@endpoint.at`
  (`provider/http/endpoint`) points it at a node:

  ```moonbit
  let provider = @endpoint.at("http://127.0.0.1:8545")
  let chain = @provider.chain_id(provider)
  ```

  No FFI is added for this. `@endpoint` uses `moonbitlang/async`'s HTTP client,
  already a dependency of this module and implemented per backend — `fetch` on
  `js`, sockets and TLS on `native` and `wasm` — so the same code reads a chain
  from a browser, a CLI or a server. `provider/http` itself declares no
  `supported_targets` and imports nothing but `provider`, so the framing builds
  on `wasm-gc` too, where a host supplies its own `HttpTransport`. A hosted
  node that wants a key takes `headers~`.

  The methods that need a wallet UI — every `wallet_*`, plus
  `eth_requestAccounts` — raise `UnsupportedMethod` without a round trip;
  everything a node can serve, including `eth_sendTransaction` against an
  unlocked account, is forwarded. `HttpProvider` implements `Provider` and
  deliberately not `EventSource`: plain HTTP pushes nothing. (#19)

- `@provider.ProviderError::from_error_object`, the decoder for the
  `{ code, message }` object EIP-1193 and JSON-RPC both carry. It was already
  there privately, behind the event path's `from_json`; a node's `error` member
  needed the same reading, and one mapping is better than two. (#19)

### Changed

- **Breaking:** `ProviderError` gained five variants, and
  `ProviderError::internal` is deprecated. Nineteen different failures used to
  flatten into `internal`, which is `Rpc(code=-32603, …)` — so a typo in a URL
  claimed the node had had an internal error before any request left the
  process, and telling "unreachable" from "unreadable" meant matching on the
  message string. Each now says what happened:

  | was `internal(…)`                      | is now                         |
  | -------------------------------------- | ------------------------------ |
  | no connection, DNS, TLS, socket closed | `Transport(String)`            |
  | a status that is not 2xx               | `HttpStatus(code~, url~)`      |
  | a 2xx body that is not JSON-RPC        | `MalformedResponse(String)`    |
  | an answer of the wrong type            | `Decode(method_name~, cause~)` |
  | a URL or an argument that is wrong     | `InvalidConfig(String)`        |

  `Decode` keeps the `CodecError` **as a value** rather than interpolating it
  into a message, so which field was wrong stays readable by a program. A
  `catch` that matched every variant by name is no longer exhaustive; add the
  cases, or a catch-all. (#113)

- **Breaking:** `CodecError` gained `InvalidValue`, and the variants now split
  on what is wrong with the value rather than on which decoder noticed:
  `InvalidHex` / `InvalidLength` / `InvalidChecksum` / `InvalidJson` are about
  the **form**, `InvalidValue` about the **meaning**. Three checks moved onto it
  — a number too wide for `uint256` in `@eip2612` / `@eip3009` (was
  `InvalidLength`), a `Topic::any_of` with no alternatives (was
  `InvalidLength`), and an EIP-712 document naming a type it never defines (was
  `InvalidJson`, which read as "you passed broken JSON" for JSON that parsed
  exactly as written). A `catch` matching all five by name is no longer
  exhaustive. (#113)
- **Breaking:** `CodecError` and `AbiError` now print through their derived
  `Debug`, so their payload is quoted: `InvalidHex("0x0g")` where it used to be
  `InvalidHex(0x0g)`. Code that compares `"\{e}"` against a literal has to add
  the quotes; nothing that matches on variants is affected. The point is that
  the variant list is the only place to edit when one is added. `JsError` gained
  the `Show` it never had, and every error type now derives `Debug`. (#113)
- **Breaking:** the `creation_code()` that `endor-cli abi` generates now embeds
  the creation code as a `Bytes` literal and calls the total
  `Hex::from_bytes`, so it can neither `abort` — which it used to, on a literal
  the generator itself had validated — nor raise. Generated code was the one
  place in the repository that could panic, and buying out of that with an error
  no caller can trigger would only have moved it. The signature is unchanged
  (`-> @types.Hex`); regenerate to get the new body. (#113)
- **Breaking:** a call a contract **reverts** now comes back as what the
  contract said, not as the node's `"execution reverted"` string.
  `ContractError` gained three variants — `Revert(reason)` for
  `Error(string)`, `Panic(code)` for the checks the Solidity compiler inserts
  (`@contract.panic_reason` says what a code means), and
  `CustomError(selector~, name~, args~, data~)` for a contract's own
  `error` — and `ProviderError` gained `Reverted(code~, message~, data~)`,
  which carries the ABI-encoded revert as it came off the wire. A `catch` that
  matched every variant by name is no longer exhaustive; add the cases, or a
  catch-all. Nothing that is _not_ a revert changed shape: `Rpc` and `Abi` mean
  exactly what they meant.
  Where the revert data sits in a JSON-RPC error differs per node, so all three
  places are read (`error.data`, `error.data.data`,
  `error.data.originalError.data`). A custom error decodes down to its arguments
  when the contract was given its own declarations —
  `Contract::new(address, errors~)`, taking `@contract.ErrorDef` values, which
  `endor-cli abi` now generates as a `<Name>::errors()` from the `error` entries
  of an ABI document. Without them a custom error still arrives, holding its
  selector and raw data. The `Erc20` preset declares its own —
  `@erc20.standard_errors()`, the six [ERC-6093](https://eips.ethereum.org/EIPS/eip-6093)
  errors an OpenZeppelin v5 token reverts with — so a transfer beyond a balance
  reads back as `ERC20InsufficientBalance(sender, balance, needed)`. (#80)
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

- **The transaction itself**, which `types` had no way to say until now: it had
  `TransactionRequest` (what is about to be sent) and `TransactionReceipt` (what
  mining it cost) and nothing for the state in between.
  `@provider.transaction_by_hash(p, hash)` reads one back
  (`eth_getTransactionByHash`, answering with a `@endor.Transaction?` because a
  hash the node has never seen is `null`). A transaction is readable from the
  moment it reaches the mempool, so this is where the fields the _wallet_ chose
  become visible — the `fee` it priced the transaction at, the `gas` it
  estimated, and the `nonce` it took, which is the one a speed-up or a cancel
  has to re-use. `send_transaction` answers with a hash and nothing else, so
  there was no way to see any of them before a receipt existed.
  `@endor.Inclusion` is where the transaction is: `Pending`, or
  `Mined(block_hash, block_number, transaction_index)`. One field rather than
  three optional ones, because a node reports those three together or not at
  all — and it makes `None` and `Pending` the different facts they are. Fees are
  read into the same `Fee` a request is built with, and a transaction of an
  EIP-2718 type this release does not know still decodes: unmodelled fields (the
  signature, an access list, blob fees) are dropped rather than rejected, and a
  fee that names none of the known keys reads as `Auto`. (#83)
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
