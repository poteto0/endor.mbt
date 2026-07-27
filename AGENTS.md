# AGENTS.md — endor.mbt

## What this project is

**endor.mbt** is a MoonBit SDK for operating browser wallets from dapps.
It wraps the [EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) provider
(`globalThis.ethereum`) injected by extensions such as MetaMask and exposes a
typed, async MoonBit API.

**The API reads chain state, evaluates calls, and switches chains**:
`eth_requestAccounts`, `eth_accounts`, `eth_chainId`, `eth_getBalance`,
`eth_blockNumber`, `eth_getTransactionCount`, `eth_gasPrice` and `eth_getCode`
are wrapped in typed helpers, as are `eth_call` / `eth_estimateGas` (`call`,
`estimate_gas`, over a `CallRequest`), `eth_sendTransaction` (`send_transaction`,
over a `TransactionRequest`, answering with a `TxHash`) and
`wallet_switchEthereumChain` / `wallet_addEthereumChain` (`switch_chain`,
`add_chain`, `switch_or_add_chain`). **Provider events are subscribed to** through
a separate `EventSource` trait: `on_accounts_changed`, `on_chain_changed` and
`on_disconnect` take a plain callback and answer with a `Subscription` handle.
Blocks and receipts and message signing are planned but not implemented — do not
describe them as available. There is no
ABI layer yet either, so a call's `data` and its answer are raw `Hex`. Callers
reach unwrapped methods through the generic `Provider::request` escape hatch.

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
- `types/` — `Address`, `Hex`, `TxHash`, `ChainId`, `Wei`, `Quantity`,
  `BlockTag`, `CallRequest`, `TransactionRequest`, `Fee`, `ChainParams`, codecs
- `crypto/` — `keccak256`, the hash every Ethereum identifier is built from
  (function selectors, event topics, EIP-55 checksums, EIP-712 hashing). A leaf
  package depending on nothing else in the module, so the layers above can use
  it without a cycle
- `provider/` — public SDK surface: `Provider` trait, `ProviderError`, typed RPC
  helpers, `MockProvider`; backend-agnostic
- `provider/browser/` — `BrowserProvider`, the injected `globalThis.ethereum`;
  the only *shipped* package above `ffi/js` that is `js`-only
- `ffi/js/` — the **only** package whose shipped code contains `extern "js"`
  bindings to `globalThis.ethereum` / JS Promises
- `backend/` — the `Backend` trait: what an end-to-end run needs in place
  before the SDK can reach a real node, and the shared skip/install/task-group
  protocol (`run`). Backend-agnostic, no FFI
- `backend/anvil/` — the `Backend` implementation for a local Anvil node, its
  dev accounts and test-contract helpers, and `js.mbt`, which injects a fake
  EIP-1193 wallet at `globalThis.ethereum`
- `e2e/` — the end-to-end test cases themselves, driven through
  `@anvil.on`; test files only, so the package exports nothing

  `backend/` and `e2e/` are repo-only: `moon.mod` excludes both from the
  published archive and `just release-check` asserts it (see `docs/e2e.md`)
- `examples/get-address/` — browser demo; a separate MoonBit module so the SDK's
  own `moon.mod` stays free of UI dependencies

## SDK design rules

- **Primary target is `js`.** The SDK talks to a browser-injected JS object,
  so FFI is written for the JS backend. Do not add wasm-gc glue.
- **Isolate FFI.** All `extern "js"` declarations in shipped code live in the
  `ffi/js` package. Everything above it is pure MoonBit and must be testable
  with a mock provider (dependency injection via the `Provider` abstraction).
  Test code may declare `extern "js"` to fake the *environment underneath* the
  SDK — the mock wallets in `provider/browser/browser_provider_test.mbt` and
  `backend/anvil/js.mbt` — but never to bind new wallet functionality; that
  belongs in `ffi/js` regardless of who calls it. Keep the two apart: `ffi/js`
  binds the wallet a browser really injected and ships to consumers, so a
  function that *fabricates* a wallet must not live there.
- **Typed surface over stringly RPC.** Public API functions like
  `request_accounts` / `send_transaction` take and return domain types
  (`Address`, `Wei`, …), never raw JSON or raw hex strings. The generic
  escape hatch `Provider::request(method_name~, params~)` stays available but is
  not the recommended path.
- **Errors are `suberror`, never panics.** EIP-1193 / EIP-1474 error codes
  (4001 user-rejected, 4902 unrecognized chain, …) map to a `ProviderError`
  suberror. Public API must not `abort`/`panic` on wallet-side failures. An
  *event* has nowhere to raise to — it arrives outside any call the dapp made —
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
  command. GitHub Actions gates on two: `just ci-check`, which is also what
  `.githooks/pre-commit` runs and therefore must never need a node, and
  `just e2e`, in its own job with an Anvil started by `just anvil`. Add a
  check to the matching recipe, not only to the workflow.

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
