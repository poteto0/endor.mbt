# AGENTS.md — endor.mbt

## What this project is

**endor.mbt** is a MoonBit SDK for operating browser wallets from dapps.
It wraps the [EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) provider
(`globalThis.ethereum`) injected by extensions such as MetaMask and exposes a
typed, async MoonBit API.

**The API reads chain state, evaluates calls, and switches chains**:
`eth_requestAccounts`, `eth_accounts`, `eth_chainId`, `eth_getBalance`,
`eth_blockNumber`, `eth_getTransactionCount`, `eth_gasPrice`, `eth_getCode` and
`eth_getStorageAt` (`storage_at`, one raw 32-byte slot — the only way to see
state no ABI declares, a proxy's EIP-1967 implementation address above all)
are wrapped in typed helpers, as are `eth_call` / `eth_estimateGas` (`call`,
`estimate_gas`, over a `CallRequest`), `eth_sendTransaction` (`send_transaction`,
over a `TransactionRequest`, answering with a `TxHash`),
`eth_sendRawTransaction` (`send_raw_transaction` — a transaction signed
somewhere else, since the SDK holds no keys and so never builds one; this is the
entrance a relayer submits through) and
`wallet_switchEthereumChain` / `wallet_addEthereumChain` (`switch_chain`,
`add_chain`, `switch_or_add_chain`). **What was mined is read back** through
`eth_getTransactionReceipt` (`transaction_receipt`, and `wait_for_receipt`, which
polls for one), `eth_getBlockByNumber` / `eth_getBlockByHash`
(`block_by_number`, `block_by_hash`) and their cheap form
`eth_getBlockTransactionCountBy*` (`block_transaction_count_by_number` /
`_by_hash`) — all of them answer with an option, because a
node answers `null` for a receipt or block it does not have.
**A transaction is read back before that too**, through
`eth_getTransactionByHash` (`transaction_by_hash`, answering with a
`Transaction?`) — the state between a request and a receipt, readable from the
moment it reaches the mempool, and the only way to see the `nonce`, `gas` and
`fee` the wallet chose. Its `inclusion` is `Pending` or `Mined(block_hash,
block_number, transaction_index)`, so a hash the node never saw (`None`) and one
it is holding (`Pending`) stay different answers.
**Events already on
the chain are searched for** with `eth_getLogs` (`logs`, over a `LogFilter`),
which is the only way to a `Log` that is not in a receipt the caller just got;
the node's own range and response limits apply and the SDK does not split a
filter up to stay inside them.
**Provider events are subscribed to** through
a separate `EventSource` trait: `on_accounts_changed`, `on_chain_changed` and
`on_disconnect` take a plain callback and answer with a `Subscription` handle.
**Contracts are called through their ABI**: `abi/` encodes and decodes ABI
values (`encode`, `decode`, `encode_call`, `selector`, `event_topic`), and
`contract/` puts `Contract::call` / `Contract::send` and an `Erc20` preset on
top of `eth_call` / `eth_sendTransaction`, and `deploy` on top of a transaction
with no recipient. **A log is read back** through `@abi.decode_log`
(`EventParam`, #79): it checks `topics[0]`, reads the `indexed` arguments out of
the remaining topics and the rest out of `data`, and answers in declaration
order — `@erc20.Erc20::decode_transfer` is that for `Transfer`. Two things it
deliberately does not do, both documented where they bite: an indexed `string` /
`bytes` / array / struct comes back as the `keccak256` the topic holds, because
that is all the log ever carried, and an `anonymous` event is not decoded at all,
because its log has no `topics[0]` to match. Callers reach unwrapped methods
through the generic `Provider::request` escape hatch.
**Messages are signed by the wallet** through `personal_sign` (`sign_message`,
over a `String` the SDK hands over as UTF-8 bytes in hex) and
`eth_signTypedData_v4` (`sign_typed_data`, over a `TypedData` — the EIP-712
document as a validated value, serialized on the wire) — both answer with the
signature as `Hex`. Neither call hashes anything — the wallet computes the
digest — but `TypedData` can now compute it too (`digest`, #45), which is what
EIP-1271 will need. **Which** document to sign is `eips/`: EIP-3009's three
authorizations are built there, so a stablecoin can be moved by a holder with no
ether. Submitting one is #73 and is not implemented — do not describe it as
available.

**The SDK is stateless.** It caches no current account and no current chain:
events are delivered to callbacks and nowhere else, and every read goes to the
wallet. A dapp that wants "the current account" holds it itself. Do not add a
cache, and do not add a `connect()` that would need one.

## Project Structure

This is a [MoonBit](https://docs.moonbitlang.com) project.

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending
  in `_wbtest.mbt`).
- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

Layout:

- root package — re-exports the domain types so they can be spelled
  `@endor.Address`; deliberately holds no provider code, which keeps it and
  `types/` backend-agnostic
- `codec/` — the wire's own arithmetic, and nothing else: hex digits (`nibble`,
  `bytes_of_digits`, `digits_of_bytes`, `hex_body`), the 32-byte word
  (`WORD_BYTES` / `WORD_DIGITS` / `WORD_BITS`, two's complement, padding in
  either unit), the decimal point's arithmetic (`decimal_parts` /
  `decimal_scale` / `decimal_unscale`, what `Wei::from_units` is built from),
  and the ABI's width and size rules as predicates. A leaf
  package: it names no domain type and has no error type of its own, so every
  layer above states each rule once and raises whichever error is its own
- `types/` — `Address`, `Hex`, `TxHash`, `BlockHash`, `ChainId`, `Wei`,
  `Quantity`, `BlockTag`, `CallRequest`, `TransactionRequest`, `Fee`,
  `ChainParams`, `Block`, `TransactionReceipt`, `Log`, `LogFilter`, `Topic`,
  codecs. Also
  `AbiType` / `AbiValue` / `AbiError`, whose definitions belong with the domain
  types both `abi` and `eips/eip712` build on; the arithmetic their rules are stated
  in is `codec`'s
- `eips/` — one package per EIP that is a _document to be signed_ rather than a
  transport or a type. They stack: `eips/eip712` says how any document is
  hashed, and everything else under `eips/` states which document. Nothing here
  reaches a node — an EIP-3009 authorization is signed by a wallet and submitted
  by somebody else entirely, so the layer that submits it (`contract/erc20/`) is
  the _caller_ of these packages and never the other way round
- `eips/eip712/` — `TypedData` / `TypedDataDomain` / `TypedDataField`: the document, the
  validation it does when it is built, and the digest a wallet signs
  (`encodeType` / `typeHash` / `encodeData` / `hashStruct` / `domainSeparator` /
  `digest`). Depends on `types`, `codec` and `crypto`; only `sign_typed_data`
  needs it, and the root re-exports the three types as `@endor.TypedData` &c.
  What every _token extension_ EIP needs of a domain lives here rather than in
  each of them: `TypedDataDomain::for_token` builds the four-field domain both
  EIP-2612 and EIP-3009 bind to, and `check_separator` compares it against the
  `DOMAIN_SEPARATOR()` the verifying contract publishes
- `eips/eip3009/` — EIP-3009 *Transfer With Authorization*: `Authorization` and
  `CancelAuthorization`, and the `@eip712.TypedData` each becomes
  (`TransferWithAuthorization` / `ReceiveWithAuthorization` /
  `CancelAuthorization`), plus `domain`, which fixes the three domain fields the
  standard fixes. This is how a stablecoin moves for a holder with no ether: the
  holder signs, anybody submits. It builds documents and **calls no contract** —
  the ERC-20 preset that sends `transferWithAuthorization` is
  [#73](https://github.com/poteto0/endor.mbt/issues/73) and will read the
  authorization back through its accessors. The nonce is 32 random bytes drawn
  by the caller, because this package owns no randomness. Its type hashes are
  checked against the constants USDC's own `EIP3009.sol` declares
- `eips/eip2612/` — EIP-2612 *permit*: `Permit` and the `@eip712.TypedData` it
  becomes, plus `domain`. The ERC-20 approval signed instead of sent, so the
  spender submits `permit` alongside its own call. It **calls no contract**
  either, but unlike EIP-3009 it cannot: a permit's nonce is the token's counter
  (`nonces(owner)`) and its domain is checkable against the token's
  `DOMAIN_SEPARATOR()`, so both are read by `contract/erc20/` — which is where
  every contract call in this repository lives — and passed *in*. That is the
  layer split to keep: `eips/` decides what a document says, `contract/` asks
  the chain. The comparison itself is `@eip712.TypedDataDomain::check_separator`
  rather than anything here, since nothing about it is EIP-2612's; it cannot
  catch DAI's non-standard permit, whose domain is ordinary and whose *message*
  is not, and building that document is out of scope. Its type hash is checked
  against the `PERMIT_TYPEHASH` constant every EIP-2612 token declares
- `crypto/` — `keccak256`, the hash every Ethereum identifier is built from
  (function selectors, event topics, EIP-55 checksums, EIP-712 hashing). A leaf
  package depending on nothing else in the module, so the layers above can use
  it without a cycle
- `abi/` — the contract ABI: `encode` / `decode`, `signature` / `selector` /
  `event_topic` / `encode_call`, over the `AbiType` / `AbiValue` / `AbiError` it
  re-exports from `types` (spelled `@abi.AbiType`, as before). Depends on
  `types`, `codec` and `crypto` and on no transport, so calldata can be built
  with no provider in hand
- `abi/codegen/` — **experimental, in progress (#48)**: renders the _source_ of
  a `Contract` preset from a JSON ABI document, or from a compiler _artifact_
  (`solc --combined-json`, standard JSON, Foundry, Hardhat), which carries the
  creation code as well and so also generates a `creation_code()` and a
  `deploy`. Bytecode is validated as hex while generating, which is what lets
  the generated `Hex::from_string` be infallible; bytecode that cannot be
  deployed is skipped with its reason, never embedded. An `error` entry becomes
  an entry of the generated `errors()`, which `new` hands to the `Contract` so
  reverts come back decoded; those carry every ABI type rather than only the
  ones a generated *signature* may name, since nothing is passed to an error. It emits text and nothing else,
  so it depends on `abi` (to resolve and validate the declared types) and on
  neither `contract` nor `provider`, whose names it only ever spells. It
  translates what it can type unambiguously and skips the rest by name rather
  than approximating it — do not describe it as a finished feature, and do not
  widen what it generates without a case that proves the wider version right.
  An ABI member's `name` is checked against the Solidity identifier grammar as
  it is read, because the name is the one thing out of the document that
  reaches the generated source verbatim
- `contract/` — `Contract`, which is `call` / `send` with the arguments encoded
  and the answer decoded, plus the `Erc20` preset — the standard interface **and
  its common extensions**, which is why `nonces` and `DOMAIN_SEPARATOR()` are on
  it and why `transferWithAuthorization`
  ([#73](https://github.com/poteto0/endor.mbt/issues/73)) will be; a token
  without the extension fails at call time, as any missing function does — and
  `deploy` /
  `send_deployment`, which are the same thing for a transaction with no
  recipient: creation code with the constructor's arguments encoded behind it,
  and the address the receipt names. `ContractError` keeps the wallet's failures
  (`Rpc`) apart from the ABI's (`Abi`) and from a deployment that left no
  contract behind (`Deployment`), and apart again from **the contract refusing**:
  `revert_error` reads the revert `@provider.ProviderError::Reverted` carries
  into `Revert(reason)` (`Error(string)`), `Panic(code)` (the compiler's own
  checks, `panic_reason`) or `CustomError(selector~, name~, args~, data~)`. A
  custom error decodes down to its arguments only when the caller passed the
  `ErrorDef`s — `Contract::new(address, errors~)`, which `abi/codegen`
  generates — because a revert names its error by selector and nothing on the
  wire says what it was called. Which key a node hides the revert under is not
  standardized, so `ProviderError::from_code` reads the three that occur
- `provider/` — public SDK surface: `Provider` trait, `ProviderError`, typed RPC
  helpers, `MockProvider`; backend-agnostic
- `provider/browser/` — `BrowserProvider`, the injected `globalThis.ethereum`;
  the only _shipped_ package above `ffi/js` that is `js`-only
- `ffi/js/` — the **only** package whose shipped code contains `extern "js"`
  bindings to `globalThis.ethereum` / JS Promises
- `backend/` — the `Backend` trait: what an end-to-end run needs in place
  before the SDK can reach a real node, and the shared skip/install/task-group
  protocol (`run`). Backend-agnostic, no FFI
- `backend/anvil/` — the `Backend` implementation for a local Anvil node, its
  dev accounts and test-contract helpers (the answer contract, the selector
  gate, and `deploy_reverter`, which reverts with whatever bytes it was given),
  and `js.mbt`, which injects a fake EIP-1193 wallet at `globalThis.ethereum` —
  including the `data` of an error, since that is where a revert travels
- `e2e/` — the end-to-end test cases themselves, driven through
  `@anvil.on`; test files only, so the package exports nothing

  `backend/` and `e2e/` are repo-only: `moon.mod` excludes both from the
  published archive and `just release-check` asserts it (see `docs/e2e.md`)

- `examples/demo/` — browser demo; a separate MoonBit module so the SDK's
  own `moon.mod` stays free of UI dependencies
- `website/` — the documentation site, <https://endor.poteto-mahiro.com>,
  rendered by `astra` (a static site generator written in MoonBit) and deployed
  to Cloudflare Workers static assets. `website/islands/` is a separate MoonBit
  module (`poteto0/endor-website-islands`, listed in `moon.work`) whose packages
  link as ES modules exporting `hydrate`: the live demo each cookbook page
  carries is that page's recipe, compiled, driving a real wallet. Like
  `examples/` it is excluded from the published archive. **Every ` ```moonbit `
  block on the site and in `README.mbt.md` is compiled by `just docs-check`,
  which `ci` and `ci-check` run** — `moon test` never reaches markdown here
  (#8), so that recipe is the only thing keeping a documented call honest. A
  block that cannot compile on its own is tagged ` ```moonbit no-check `.
  How to work on it: `docs/website.md`
- `cmd/` — **experimental, in progress (#48)**: `endor-cli`, the command-line
  tools; `cmd/endor-cli/` is the binary and `abi`, the front end to
  `abi/codegen`, is so far its only real subcommand. How to add one is
  `cmd/README.md#adding-a-subcommand`. Like `examples/`, a separate MoonBit module
  (`poteto0/endor-cli`, listed in `moon.work`) so its dependencies stay out of
  this one: it needs `moonbitlang/x` for file access and therefore a `native`
  build, and the SDK must need neither. Being a separate module keeps it out of
  the _package graph_; the `exclude` list in `moon.mod` keeps it out of the
  _archive_, which `moon package` fills from the directory tree — both are
  needed, exactly as for `examples/`. Its version and its `poteto0/endor@…`
  pin move with the release tag, which `just release-check` asserts. Its own
  recipes are `just cli-check` / `just cli-test`, because everything else here
  pins `js`

## SDK design rules

- **Primary target is `js`.** The SDK talks to a browser-injected JS object,
  so FFI is written for the JS backend. Do not add wasm-gc glue.
- **Isolate FFI.** All `extern "js"` declarations in shipped code live in the
  `ffi/js` package. Everything above it is pure MoonBit and must be testable
  with a mock provider (dependency injection via the `Provider` abstraction).
  Test code may declare `extern "js"` to fake the _environment underneath_ the
  SDK — the mock wallets in `provider/browser/browser_provider_test.mbt` and
  `backend/anvil/js.mbt` — but never to bind new wallet functionality; that
  belongs in `ffi/js` regardless of who calls it. Keep the two apart: `ffi/js`
  binds the wallet a browser really injected and ships to consumers, so a
  function that _fabricates_ a wallet must not live there.
- **Typed surface over stringly RPC.** Public API functions like
  `request_accounts` / `send_transaction` take and return domain types
  (`Address`, `Wei`, …), never raw JSON or raw hex strings. The generic
  escape hatch `Provider::request(method_name~, params~)` stays available but is
  not the recommended path.
- **Requests are opaque, answers are open.** A type the caller _builds_
  (`Address`, `CallRequest`, `TransactionRequest`, `ChainParams`, …) is a
  `pub struct` with `priv` fields and a constructor that validates, so an
  invalid value cannot be spelled. A type the caller only _reads back_ off the
  wire (`Block`, `TransactionReceipt`, `Log`) is a `pub(all) struct` whose
  fields are the answer: it is built by its own `from_json` and nowhere else,
  and putting an accessor in front of each field would add a method per field
  and hide nothing.

- **Errors are `suberror`, never panics.** EIP-1193 / EIP-1474 error codes
  (4001 user-rejected, 4902 unrecognized chain, …) map to a `ProviderError`
  suberror. Public API must not `abort`/`panic` on wallet-side failures. An
  _event_ has nowhere to raise to — it arrives outside any call the dapp made —
  so a payload that fails to decode is dropped: the handler is not called and
  nothing is raised.
- **Events are plain callbacks.** The event API is a callback plus an
  `unsubscribe` handle (`Subscription`) and nothing more, so a UI layer can wrap
  it into its own lifecycle without the SDK depending on that layer. Event
  delivery lives in the `EventSource` trait, kept apart from `Provider` because a
  transport can answer RPC without being able to push anything back.
- **Quantities are hex on the wire.** JSON-RPC quantities are `0x`-prefixed
  hex; encode/decode in `types/`, keep the rest of the code in domain types.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.
- Try to keep deprecated blocks in a file called `deprecated.mbt` in each
  directory.
- Public API blocks get doc comments with a short usage example.

## Tooling

- `moon fmt` is used to format your code properly.
- `moon ide` provides project navigation helpers like `peek-def`, `outline`,
  and `find-references`.
- `moon info` updates the generated interface (`.mbti`) of each package; check
  its diff to see whether a change is externally visible.
- In the last step, run `moon info && moon fmt` and review the `.mbti` diffs.
- Run `moon test` (blackbox `_test.mbt` / whitebox `_wbtest.mbt`) to check
  tests pass. MoonBit supports snapshot testing; when changes affect outputs,
  run `moon test --update` to refresh snapshots.
- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for stable
  results. Use `moon coverage analyze > uncovered.log` to find uncovered code.
- Tests must not require a real browser or MetaMask: unit-test codecs and
  error mapping directly, and test the RPC layer against a mock `Provider`.
  The one place that talks to a live node is `e2e/`, and it skips itself when
  no node is configured — run it with `just anvil` in one terminal and
  `just e2e` in another. Anything a mock cannot prove (the wire format a node
  accepts) belongs there; anything only an extension can prove belongs in the
  manual checklist in `docs/e2e.md`.
- Every check CI runs is a `just` recipe, so it reproduces locally with one
  command. GitHub Actions gates on two: `just ci-check`, which must never need
  a node, and `just e2e`, in its own job with an Anvil started by `just anvil`.
  Add a check to the matching recipe, not only to the workflow.
- `.githooks/pre-commit` runs `just precommit`, which is `ci-check`'s checks
  _selected by the staged diff_ — the whole set is a gate the PR already has,
  and paying for it on every commit is #96. The selection is
  `scripts/precommit.sh`, whose header states which staged path pulls in which
  check; scoped `unit-test` follows the import graph out of `moon.pkg`, so a
  change under `types/` still tests `abi/`. Add a check to `ci-check` and it
  runs pre-commit too: the script reads that recipe's list rather than copying
  it, and skips only what it is told to. Say when a new one may be skipped, or
  leave it running always.
- `scripts/` is repository tooling a recipe calls when the recipe would
  otherwise be a shell program with a `just` header on it. It decides *which*
  checks run; how a check runs stays in the `justfile`, so there is one place
  to read a command out of. Excluded from the published archive, like `docs/`.
- The MoonBit toolchain is pinned in `.github/actions/setup`, because it is
  released nightly and a release that changes generated output turns every open
  PR red at once. Bump it in its own PR, carrying whatever `just info`, `just
  fmt` and the dependency bumps that version wants, and install the same version
  locally (`MOONBIT_INSTALL_VERSION=… curl -fsSL
  https://cli.moonbitlang.com/install/unix.sh | bash`) so `just ci-check` still
  answers what CI will.

## Releasing

Pushing a `v*` tag publishes to mooncakes.io
(`.github/workflows/release.yml`). A mooncakes release cannot be taken back, so
the version must be right before the tag exists:

```sh
# 1. bump every declared version — `moon.mod`, and the example module's own
#    version and its `poteto0/endor@…` dependency — then commit
just release-check v0.2.0   # verifies exactly that, before you tag
git tag v0.2.0 && git push origin v0.2.0
```

The workflow re-runs `just release-check` and `just ci-check` against the tagged
tree before publishing. It needs two repository secrets, which are the `token`
and `username` fields `moon login` writes to `~/.moon/credentials.json`:
`MOONCAKES_TOKEN` and `MOONCAKES_USERNAME`.

You can browse and install extra MoonBit skills here:
<https://github.com/moonbitlang/skills>
