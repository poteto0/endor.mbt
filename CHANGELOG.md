# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/) (pre-1.0: expect
breaking changes on any minor bump).

**Until 1.0, breaking changes are accepted whenever they make the API right.**
Every such change is listed under **Changed** with what to do about it. The
policy in full — what counts as a break, and what does not — is
[Versioning](https://endor.poteto-mahiro.com/reference/versioning/).

## [0.8.0] - 2026-08-22

### Added

- **The submitter's half of a stablecoin.** `@stablecoin.Stablecoin`
  (`poteto0/endor/contract/stablecoin`) answers the whole ERC-20 interface and
  adds the calls that *send* what a holder signed: `transfer_with_authorization`,
  `receive_with_authorization`, `cancel_authorization` and `permit`. Also
  `authorization_state` and `Stablecoin::domain`, which checks the domain it
  built against the token's own `DOMAIN_SEPARATOR()`.
- **Stablecoin calls a contract wallet can sign.** `transfer_with_authorization_1271`
  and its three siblings send the `bytes signature` overload FiatTokenV2_2 added,
  which a token can verify through
  [EIP-1271](https://eips.ethereum.org/EIPS/eip-1271). Which form goes out is the
  caller's to choose: a token older than V2_2 lacks these selectors and reverts.
- **Reading EIP-3009 back out of a receipt.** `authorization_used_topic()` /
  `decode_authorization_used(log)` and `authorization_canceled_topic()` /
  `decode_authorization_canceled(log)` answer `(authorizer, nonce)` for the two
  logs FiatToken writes — which is how a relayer that sent several
  authorizations at once tells them apart.
- `@endor.TypedData::from_json`, the inverse of `to_json`, for code that
  *receives* a document rather than building one. It ends in `TypedData::new`, so
  parsing a document validates it.
- **Every provider retries the failures worth retrying.** A `429`, a socket
  closed mid-request, a `-32005`: `HttpProvider` and `BrowserProvider` now send
  the request again rather than handing the failure straight to the caller.
  viem's numbers: 150 ms doubling to at most 2 s, three retries. Nothing to
  enable.
- **`RetryPolicy` and `with_retry`, for when the defaults are wrong.**
  `@provider.RetryPolicy::new(strategy?, max_retry?)`, with `default()` and
  `none()`. Two things stay outside the policy: `Retry-After` wins over the
  backoff, and the methods that open a wallet dialog are still sent exactly once.
  [Retries](https://endor.poteto-mahiro.com/guide/retries/) is the whole of it.
- **A node that says how long to wait is waited.** `HttpStatus` carries the
  `Retry-After` a `429` or a `503` answered with, and the retry loop waits
  exactly that. Only the delta-seconds form is read, values past an hour are left
  to the backoff, and `HttpStatusInfo::retry_after()` is it in seconds.

### Changed

- **`WalletClient::prepare` asks for everything at once.** The chain id, the
  pending nonce, the fees and the gas estimate now go out in one task group, so
  the call waits for the slowest read rather than the sum. What moves is which
  failure wins when more than one fails. A contract creation with no `gas` is
  refused before any request leaves.
- **`HttpStatus` has a third field, `info~ : HttpStatusInfo`.** `code` and `url`
  are untouched; a pattern that names them both and stops there needs a `..`:

  ```moonbit no-check
  // before
  HttpStatus(code~, url~) => println("HTTP \{code} from \{url}")
  // after
  HttpStatus(code~, url~, ..) => println("HTTP \{code} from \{url}")
  ```

  This is the last field the variant gets: what a response carries is
  open-ended, and the next thing worth reading off one is an optional argument
  and an accessor inside `HttpStatusInfo`.

## [0.7.0] - 2026-08-09

### Added

- **A key of your own.** `@account.Account` is the trait for anything that can
  sign, and `@local.LocalAccount::new(key)` holds 32 bytes and signs **in this
  process**. Underneath: `endor/crypto/secp256k1`,
  `@types.Address::from_public_key`, and `endor/codec/rlp` with
  `@types.UnsignedTransaction`. A key anything can read is a key anything can
  sign with, so it belongs in a server and never in a browser bundle.
- `@wallet.WalletClient`, a transport and an account joined, so that where a
  signature comes from stops being the caller's problem. `WalletClient::new`
  pairs any `Provider` with any `Account` and `connect` asks the wallet for one.
  `prepare` fills in the chain id, the nonce, the gas and the fee pair, since a
  transaction signed here is signed complete or not at all.
- `@endor.AccountError` and `@endor.WalletError`, re-exported from the root.
  `WalletError` does not flatten what it caught: `Provider(e)` and `Account(e)`
  carry the original whole.
- **EIP-6963 wallet discovery**, for the page with more than one extension
  installed. `BrowserProvider::discover(timeout_ms~)` answers with a
  `DiscoveredWallet` per wallet, falling back to the injected one when nothing
  announces. `on_announce(f)` is the same without a deadline, since enumeration
  under EIP-6963 never finishes.

### Changed

- **Breaking:** `@crypto.keccak256` is now `@keccak.keccak256`. `crypto/` became
  a directory of subpackages, so `crypto/keccak` sits beside `crypto/secp256k1`.
  Import `poteto0/endor/crypto/keccak`; nothing about `keccak256` changed.
- The module description, the README and the site no longer present this as a
  browser-wallet SDK with HTTP as an escape hatch. How you reach a chain and who
  holds the key are independent choices, and every pairing works.
- Doc comments were cut back to what a caller needs: what a function answers,
  when it raises, how it is called. `moon.pkg` comments are gone entirely. No
  code changed.

### Performance

- **Signature hashes are cached**, so the same `balanceOf(address)` is hashed
  once rather than once per call. `@abi.selector` is **80× faster on `js`** and
  **8× on `native`**; `event_topic` shares the table.
- `keccak256` does its round arithmetic on 32-bit halves rather than on
  `UInt64`, which on `js` is a `BigInt` and pays for every shift: **3× faster**.
- `@eip712.TypedData` remembers what it has already hashed instead of walking
  the document again per field: **1.57× on `js`**, **2.28× on `native`**.
- `@abi.Event::new` works out the signature, the topic0 and the indexed/`data`
  split once, so `Event::decode_log` hashes nothing. A batch of logs decodes a
  median **1.3–1.5× faster** on both backends; the free `decode_log` delegates
  to it and keeps its old cost.
- `Address` no longer recomputes its EIP-55 checksum every time it is printed
  for debugging.

## [0.6.0] - 2026-08-08

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

  `message()` is one line written for a person, as against `Show`, which belongs
  in a log. The two types that talk to the wire add `code()`, and
  `ContractError` adds `revert_reason()`.

- `@endor.ProviderError` and `@endor.ContractError`: the root re-exports both,
  so the public error surface is four types spelled from one package.
- A timeout on every HTTP request. `@endpoint.at` takes `timeout~` in
  milliseconds (30 000 by default) bounding the whole POST, after which the call
  raises `Timeout`.
- **Batched reads**, so a listing costs one RPC round trip rather than one per
  field. `@multicall.Multicall3::new().aggregate3(p, calls)` makes every call in
  a single `eth_call` through [Multicall3](https://github.com/mds1/multicall),
  answering with an `Outcome` per call — so one call reverting does not take the
  others down, and every read saw the same block. `is_deployed` says whether
  there is a contract there at all.
- `@contract.Contract::prepare`, which splits `Contract::call` into the encode
  and the decode it was: a `PreparedCall` that `decode` reads an answer back
  with and `revert` reads raw revert bytes with. Holding an encoded call as a
  value is what makes bundling possible.
- An HTTP JSON-RPC transport, so the read layer works without a browser wallet
  **and on every backend**: `@http.HttpProvider` frames each call as JSON-RPC
  2.0 and `@endpoint.at` points it at a node:

  ```moonbit
  let provider = @endpoint.at("http://127.0.0.1:8545")
  let chain = @provider.chain_id(provider)
  ```

  No FFI is added: `@endpoint` uses `moonbitlang/async`'s HTTP client, which is
  implemented per backend. A hosted node that wants a key takes `headers~`. The
  methods that need a wallet UI raise `UnsupportedMethod` without a round trip;
  `HttpProvider` deliberately does not implement `EventSource`.

- `@provider.ProviderError::from_error_object`, the decoder for the
  `{ code, message }` object EIP-1193 and JSON-RPC both carry.
- **The transaction itself**, which `types` had no way to say until now.
  `@provider.transaction_by_hash(p, hash)` reads one back, so the fields the
  *wallet* chose — the fee, the gas, and the nonce a speed-up has to re-use —
  become visible. `@endor.Inclusion` is `Pending` or `Mined(…)`, one field
  rather than three optional ones. An EIP-2718 type this release does not know
  still decodes.
- Decoding a **log** into the arguments its event was emitted with:
  `@abi.decode_log(name~, params~, topics~, data~)` checks `topics[0]`, reads
  the indexed arguments out of the topics and the rest out of `data`.
  `@erc20.Erc20::decode_transfer(log)` is that for `Transfer`. An indexed
  dynamic type comes back as the hash the topic holds, and an `anonymous` event
  is not decoded.
- `Wei::from_units(value, decimals~)` / `Wei::to_units(decimals~)`: the decimal
  amount a person writes, and the whole smallest units the wire carries. The
  amount is a `String` and never a `Double`, and one finer than the scale raises
  the new `CodecError::InvalidDecimal` rather than being truncated. `to_units`
  folds trailing zeros and formats nothing else.
- Four reads and one write that had no typed helper:
  - `storage_at(p, who, slot, block?)` — one raw 32-byte slot, the only way to
    see state a contract does not expose. A slot nobody wrote reads as zeroes
  - `send_raw_transaction(p, raw)` — submitting a transaction signed elsewhere,
    which is exactly what a relayer does
  - `block_transaction_count_by_number(p, block?)` /
    `block_transaction_count_by_hash(p, hash)` — the count without the hashes,
    as `UInt64?`
- `@provider.logs(p, filter)` (`eth_getLogs`): the **past** events, which the
  SDK had no route to at all. A `@endor.LogFilter` is built by `range` or by
  `at_block` — two constructors, because the RPC refuses `blockHash` beside a
  range — and `topics` is an `Array[@endor.Topic?]` whose three states are
  `exactly`, `any_of` and `None`. The filter is sent as given and never split.
- The material an EIP-1559 fee is built from:
  - `max_priority_fee_per_gas(p)`, answering `@endor.Wei?`. `None` is neither an
    error nor a zero tip: the method is a geth extension
  - `fee_history(p, block_count~, newest_block?, reward_percentiles?)`, over the
    new `@endor.FeeHistory`. `base_fee_per_gas` is **one element longer** than
    the range; percentiles are checked here so the error names the argument
  - `estimate_fees(p)` — the two composed into the `Fee` a wallet would have
    built, with a cap of `2 * baseFee + tip`. **The doubling is geth's own
    default**, not something EIP-1559 states. A chain with no base fee gets
    `Legacy(gas_price=eth_gasPrice)`
  - `Fee` now implements `Show`
  - `ProviderError::is_method_not_found()`: the two spellings of "this node does
    not have that method" as one predicate. `MockProvider` answers `-32603` for
    an unregistered method, so a test that forgot one fails loudly
- EIP-2612 *permit*, as `@eip2612`: the ERC-20 approval **signed instead of
  sent**. `Permit::new` validates the five members and `Permit::typed_data`
  becomes the document. A permit's nonce is the token's counter, so `@erc20.Erc20`
  gained `nonces` and `domain_separator`. DAI's non-standard permit is not built.
- `@eip712.TypedDataDomain` gained `separator`, `check_separator(on_chain~)` and
  `for_token` — all things a *token extension* EIP needs, so EIP-2612 and
  EIP-3009 both use them. The `version` that is `"2"` on USDC and `"1"` almost
  everywhere else is otherwise invisible until the chain rejects the transaction.
- EIP-3009 *Transfer With Authorization*, as `@eip3009`: the holder signs a
  transfer and **somebody else submits it**. `Authorization::new` becomes either
  document — `transfer_typed_data` or `receive_typed_data` — and
  `CancelAuthorization` burns a nonce before it is used. Building documents is
  all it does.

### Changed

- **Breaking:** `ProviderError` gained five variants, and
  `ProviderError::internal` is deprecated. Nineteen different failures used to
  flatten into `internal`; each now says what happened:

  | was `internal(…)`                      | is now                         |
  | -------------------------------------- | ------------------------------ |
  | no connection, DNS, TLS, socket closed | `Transport(String)`            |
  | a status that is not 2xx               | `HttpStatus(code~, url~)`      |
  | a 2xx body that is not JSON-RPC        | `MalformedResponse(String)`    |
  | an answer of the wrong type            | `Decode(method_name~, cause~)` |
  | a URL or an argument that is wrong     | `InvalidConfig(String)`        |

  `Decode` keeps the `CodecError` **as a value**, so which field was wrong stays
  readable by a program. A `catch` that matched every variant by name is no
  longer exhaustive; add the cases, or a catch-all.

- **Breaking:** `CodecError` gained `InvalidValue`, and the variants now split on
  what is wrong with the value rather than on which decoder noticed: the first
  four are about the **form**, `InvalidValue` about the **meaning**. Three checks
  moved onto it. A `catch` matching all five by name is no longer exhaustive.
- **Breaking:** `CodecError` and `AbiError` now print through their derived
  `Debug`, so their payload is quoted: `InvalidHex("0x0g")`. Code that compares
  `"\{e}"` against a literal has to add the quotes. `JsError` gained the `Show`
  it never had, and every error type now derives `Debug`.
- **Breaking:** the `creation_code()` that `endor-cli abi` generates embeds the
  code as a `Bytes` literal and calls the total `Hex::from_bytes`, so it can
  neither `abort` nor raise. The signature is unchanged; regenerate for the new
  body.
- **Breaking:** a call a contract **reverts** now comes back as what the contract
  said, not as the node's `"execution reverted"` string. `ContractError` gained
  `Revert`, `Panic` and `CustomError`, and `ProviderError` gained `Reverted`,
  carrying the ABI-encoded revert as it came off the wire. A `catch` that matched
  every variant by name is no longer exhaustive.

  Where the revert data sits in a JSON-RPC error differs per node, so all three
  places are read. A custom error decodes to its arguments when the contract was
  given its own `@contract.ErrorDef`s, which `endor-cli abi` generates; without
  them it still arrives, holding its selector and raw data. `Erc20` declares the
  six [ERC-6093](https://eips.ethereum.org/EIPS/eip-6093) errors itself.
- **Breaking:** `CodecError` gained a fifth variant, `InvalidDecimal`, for a
  string that is not a decimal amount the target can hold. A `catch` that matched
  all four by name is no longer exhaustive.

## [0.5.0] - 2026-08-01

### Added

- A logo: a round green planet with a small grey satellite off its lower right,
  as `website/public/logo.svg`. It is the mark beside the site title, the
  favicon, and the top of the README.
- **Experimental:** `abi/codegen` reads a compiler **artifact** as well as a bare
  ABI array, and an artifact carries the creation code — so the generated struct
  gets a `creation_code()` and a `deploy` over `@contract.deploy`.
  `Generated::deploys` says whether it did. Bytecode that cannot be deployed is
  *skipped* with its reason, and an artifact holding several contracts is refused.
- Contract deployment: `@contract.deploy` sends the creation code with its
  constructor arguments encoded behind it, waits for the receipt and answers with
  the `Contract` at the address it names. `send_deployment` is the same without
  the wait, `deployment_data` is the `data` both build, and a deployment that
  reverted raises the new `ContractError::Deployment`.
- `Hex::concat`, which joins two hex byte strings without taking either apart:
  both of `Hex`'s rules hold of the halves, so they hold of the whole.
- **Experimental:** `abi/codegen` renders the source of a `@contract.Contract`
  preset from a JSON ABI document, and `endor-cli abi` writes one file per
  document from a checked-in `endor.yaml` that `endor-cli init` creates. It
  generates only what it can type without guessing and *skips* every other member
  by name. The CLI is a separate module, so its dependencies stay out of the SDK's.
- `@contract.uint_answer` / `int_answer` / `string_answer` / `bool_answer` /
  `address_answer`: the single value a getter answered with, or a `ContractError`
  naming the getter. `int` and `uint` stay separate deliberately.
- `Hex::from_digits`, which builds a hex byte string from the digits alone. It is
  where both of `Hex`'s rules are now stated, and `@abi.encode` is the caller it
  exists for.

### Changed

- **Breaking:** EIP-712 typed data moved out of `types` into its own package,
  `endor/eips/eip712`. Every method is unchanged, as is `@endor.TypedData` — the
  root re-exports the three types, so a caller that spells them `@endor.…` needs
  no change. `types` also gained a `codec` layer underneath it: the hex-digit and
  word arithmetic, and the ABI's width and size rules as predicates.
- **Breaking:** `CodecError` is now `pub(all)`, so a layer above the domain types
  can raise one — which is what `@eip712` does.
- **Breaking:** `AbiError` now lives in `types` and is re-exported by `abi`. Only
  its *constructors* moved: a caller that raises one writes
  `@types.InvalidData(…)`. `AbiType::name` raises it in place of `CodecError`.
- **Breaking:** `TypedData::encode_type` / `type_hash` now `raise CodecError`. A
  type name the document does not define used to panic through an `unwrap`.
  Callers add `try` / `raise` at the call site.

### Fixed

- `types/` no longer `abort`s anywhere: the two exhaustiveness-only branches in
  EIP-712 validation and encoding raise `InvalidJson` like every other unusable
  type name.
- Validate the ABI value word on decoding.

### Performance

- `@abi.encode` / `encode_call` no longer spell their result as `Bytes` only to
  spell it straight back as the same hex digits. Encoding 50,000 `uint256`
  (1.6 MB of calldata) went from 1.28 s to 0.08 s — **15× faster**.
- `Hex::from_bytes` writes a whole byte's two digits from a 256-entry table, and
  `Hex::to_bytes` reads the digits in one pass; both are about **2× faster**.
  They are on the path of every digest and every signature.

## [0.4.0] - 2026-07-28

### Added

- EIP-712 typed data hashing: `encodeType` / `typeHash` / `encodeData` /
  `hashStruct` / `domainSeparator`
- Contract layer: ABI encode/decode and typed contract calls
- Message signing: `personal_sign` / `eth_signTypedData_v4`
- Block / receipt reads and `wait_for_receipt`
- Provider events: `accountsChanged` / `chainChanged` / `disconnect`

### Changed

- Reworked the contract layer API ahead of release

## [0.3.0] - 2026-07-27

### Added

- `eth_sendTransaction` as a typed helper
- `eth_call` / `eth_estimateGas` as typed helpers
- `crypto/`: a from-scratch MoonBit implementation of keccak256
- `types/`: EIP-55 checksummed addresses
- `require_account` helper for wallet connection
- e2e tests: verify `BrowserProvider` against Anvil standing in for an
  injected wallet

## [0.2.0] - 2026-07-25

### Added

- Typed helpers for the basic read methods
- Chain switching: `switch` / `add` / EIP-4902 fallback
- Release automation: tag push → `moon publish`

### Changed

- `provider/` no longer depends on `ffi/js` directly; browser wiring moved to
  `provider/browser`

## [0.1.0] - 2026-07-25

### Added

- MetaMask connection via the EIP-1193 provider standard
- Basic read methods

[0.8.0]: https://github.com/poteto0/endor.mbt/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/poteto0/endor.mbt/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/poteto0/endor.mbt/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/poteto0/endor.mbt/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/poteto0/endor.mbt/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/poteto0/endor.mbt/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/poteto0/endor.mbt/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/poteto0/endor.mbt/releases/tag/v0.1.0
