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
`estimate_gas`, over a `CallRequest`) and `wallet_switchEthereumChain` /
`wallet_addEthereumChain` (`switch_chain`, `add_chain`, `switch_or_add_chain`).
Blocks and receipts, transaction sending, message signing, and provider events
are planned but not implemented — do not describe them as available. There is no
ABI layer yet either, so a call's `data` and its answer are raw `Hex`. Callers
reach unwrapped methods through the generic `Provider::request` escape hatch.

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
- `types/` — `Address`, `Hex`, `ChainId`, `Wei`, `Quantity`, `BlockTag`,
  `ChainParams`, codecs
- `crypto/` — `keccak256`, the hash every Ethereum identifier is built from
  (function selectors, event topics, EIP-55 checksums, EIP-712 hashing). A leaf
  package depending on nothing else in the module, so the layers above can use
  it without a cycle
- `provider/` — public SDK surface: `Provider` trait, `ProviderError`, typed RPC
  helpers, `MockProvider`; backend-agnostic
- `provider/browser/` — `BrowserProvider`, the injected `globalThis.ethereum`;
  the only package above `ffi/js` that is `js`-only
- `ffi/js/` — the **only** package containing `extern "js"` bindings to
  `globalThis.ethereum` / JS Promises
- `examples/get-address/` — browser demo; a separate MoonBit module so the SDK's
  own `moon.mod` stays free of UI dependencies

## SDK design rules

- **Primary target is `js`.** The SDK talks to a browser-injected JS object,
  so FFI is written for the JS backend. Do not add wasm-gc glue.
- **Isolate FFI.** All `extern "js"` declarations live in the `ffi/js` package.
  Everything above it is pure MoonBit and must be testable with a mock
  provider (dependency injection via the `Provider` abstraction).
- **Typed surface over stringly RPC.** Public API functions like
  `request_accounts` / `send_transaction` take and return domain types
  (`Address`, `Wei`, …), never raw JSON or raw hex strings. The generic
  escape hatch `Provider::request(method_name~, params~)` stays available but is
  not the recommended path.
- **Errors are `suberror`, never panics.** EIP-1193 / EIP-1474 error codes
  (4001 user-rejected, 4902 unrecognized chain, …) map to a `ProviderError`
  suberror. Public API must not `abort`/`panic` on wallet-side failures.
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
- Every check CI runs is a `just` recipe, so it reproduces locally with one
  command: `just ci-check` is what GitHub Actions gates on and what
  `.githooks/pre-commit` runs. Add a check to the recipe, not only to the
  workflow.

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
