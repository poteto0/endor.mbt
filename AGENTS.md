# AGENTS.md — endor.mbt

**endor.mbt** is a [MoonBit](https://docs.moonbitlang.com) SDK for Ethereum: it
wraps the [EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) wallet a browser
injects at `globalThis.ethereum`, and JSON-RPC over HTTP, behind one typed async
`Provider`.

This file holds only what the repository cannot tell you itself: the decisions
to keep, the conventions, and the commands. It deliberately does **not** list
what is wrapped or what each package contains — that changes with every feature
and nobody checks the prose.

- what is implemented — <https://endor.poteto-mahiro.com/reference/>, whose
  examples CI compiles; what is not — [Not wrapped
  yet](https://endor.poteto-mahiro.com/reference/not-wrapped/)
- where it is going — [`docs/roadmap.md`](docs/roadmap.md) and the issues
- what a package is — its own directory: `moon.pkg` for its dependencies, its
  `.mbti` for its surface, its doc comments for the rest

## Design rules

These are choices, not descriptions: changing one is a decision to argue for,
not a refactor.

- **The SDK is stateless.** It caches no current account and no current chain:
  events go to callbacks and nowhere else, and every read goes to the node. A
  dapp that wants "the current account" holds it itself. Do not add a cache, and
  do not add a `connect()` that would need one. What it forbids is remembering
  what changes underneath the SDK and goes stale, not a table whose key fully
  determines its contents: `abi`'s signature → selector memo is the one of
  those, and a second one is this decision again.
- **`js` is where the _wallet_ is, not where the SDK is.** The injected wallet
  is JS-only and every recipe pins `js`, but the read layer builds on every
  backend. Before writing an `extern "js"` for anything that is not the wallet,
  check whether `moonbitlang/async` already has it on every backend — HTTP was
  written as a `fetch` binding first, and that was a `js` lock-in bought for
  nothing. Do not add wasm-gc glue.
- **Isolate FFI.** All `extern "js"` in shipped code lives in `ffi/js`.
  Everything above it is pure MoonBit, testable against a mock `Provider`. Test
  code may declare `extern "js"` to fake the environment _underneath_ the SDK
  (the mock wallets in `provider/browser/` and `backend/anvil/js.mbt`), never to
  bind new wallet functionality. A binding also decides nothing: `ffi/js`
  reports what happened (a status, a thrown message) and never which
  `ProviderError` that is — mapping is `provider/error.mbt`'s, where it is
  testable.
- **Typed surface over stringly RPC.** Public functions take and return domain
  types (`Address`, `Wei`, …), never raw JSON or raw hex. `Provider::request`
  stays as the escape hatch but is not the recommended path.
- **Requests are opaque, answers are open.** A type the caller _builds_ is a
  `pub struct` with `priv` fields and a validating constructor, so an invalid
  value cannot be spelled. A type the caller only _reads back_ off the wire is a
  `pub(all) struct` built by its own `from_json` and nowhere else.
- **Quantities are hex on the wire.** Encode and decode in `types/`; everything
  above keeps domain types.
- **Errors are `suberror`, never panics.** EIP-1193 / EIP-1474 codes (4001
  user-rejected, 4902 unrecognized chain, …) map to `ProviderError`. Public API
  must not `abort`/`panic` on wallet-side failures. An _event_ has nowhere to
  raise to, so a payload that fails to decode is dropped: the handler is not
  called and nothing is raised.
- **Events are plain callbacks.** A callback plus an unsubscribe handle
  (`Subscription`), so a UI layer can wrap it in its own lifecycle. Delivery
  lives in `EventSource`, apart from `Provider`, because a transport can answer
  RPC without being able to push.
- **The layers only point one way.** `codec` names no domain type and owns no
  error type; `types` holds the definitions (methods must sit with their type)
  and `codec` the arithmetic; `eips/` decides what a document _says_ and reaches
  no node; `contract/` is where every contract call lives and passes what it
  read _in_; `abi/codegen` emits text and depends on neither `contract` nor
  `provider`. Do not shortcut one of these by importing backwards.
- **Generators translate or skip.** `abi/codegen` and `cmd/` are experimental
  ([#48](https://github.com/poteto0/endor.mbt/issues/48)): they emit only what
  they can type unambiguously and skip the rest by name. Do not widen what is
  generated without a case that proves the wider version right, and do not
  describe them as finished.

## Coding convention

- MoonBit code is organized in block style, blocks separated by `///|`; block
  order is irrelevant, so a refactor can go block by block.
- Keep deprecated blocks in a `deprecated.mbt` per directory.
- Public API blocks get a doc comment with a short usage example.

## Tooling

Every check CI runs is a `just` recipe, so it reproduces locally with one
command. GitHub Actions gates on `just ci-check`, which must never need a node,
and `just e2e`, in its own job against `just anvil`. Add a check to the matching
recipe, not only to the workflow.

- `moon fmt` formats; `moon info` regenerates each package's `.mbti`. Run `moon
info && moon fmt` last and review the `.mbti` diff — that is what says whether
  a change is externally visible. `moon ide` has `peek-def` / `outline` /
  `find-references`.
- `moon test` runs blackbox (`_test.mbt`) and whitebox (`_wbtest.mbt`) tests;
  `moon test --update` refreshes snapshots. Prefer `assert_eq` or
  `assert_true(x is Pattern(..))`. `moon coverage analyze > uncovered.log` finds
  what is untested.
- Tests must not require a real browser or MetaMask: unit-test codecs and error
  mapping directly, and test the RPC layer against a mock `Provider`. Only
  `e2e/` talks to a live node, and it skips itself when none is configured (`just
anvil` in one terminal, `just e2e` in another). What a mock cannot prove — the
  wire format a node accepts — belongs there; what only an extension can prove
  belongs in the manual checklist in [`docs/e2e.md`](docs/e2e.md).
- Every ` ```moonbit ` block on the site and in `README.mbt.md` is compiled by
  `just docs-check` (`moon test` never reaches markdown,
  [#8](https://github.com/poteto0/endor.mbt/issues/8)). A block that cannot
  compile alone is tagged ` ```moonbit no-check `. Working on the site:
  [`docs/website.md`](docs/website.md).
- `.githooks/pre-commit` runs `just precommit` — `ci-check`'s checks _selected
  by the staged diff_ ([#96](https://github.com/poteto0/endor.mbt/issues/96)).
  The selection is `scripts/precommit.sh`, whose header states which staged path
  pulls in which check. It reads `ci-check`'s list rather than copying it, so a
  new check runs pre-commit too; say when it may be skipped, or leave it always
  on.
- `scripts/` is repository tooling a recipe calls when the recipe would
  otherwise be a shell program with a `just` header on it. It decides _which_
  checks run; _how_ a check runs stays in the `justfile`, so there is one place
  to read a command out of.
- `cmd/`, `examples/` and `website/islands/` are separate MoonBit modules
  (listed in `moon.work`) so their dependencies stay out of the SDK's, and
  `moon.mod`'s `exclude` keeps them, `backend/`, `e2e/`, `docs/` and `scripts/`
  out of the published archive. Both are needed; `just release-check` asserts
  it. `cmd/` builds `native`, so it has its own `just cli-check` / `just
cli-test`.
- The MoonBit toolchain is pinned in `.github/actions/setup`, because it is
  released nightly and a release that changes generated output turns every open
  PR red at once. Bump it in its own PR, carrying whatever `just info`, `just
fmt` and the dependency bumps that version wants, and install the same version
  locally (`MOONBIT_INSTALL_VERSION=… curl -fsSL
https://cli.moonbitlang.com/install/unix.sh | bash`) so `just ci-check` still
  answers what CI will. It is pinned a second time in `flake.nix`, for the
  optional `nix develop` shell — bump both, or `just nix-pin-check` (part of
  `ci-check`, and it needs no nix) fails. [`docs/nix.md`](docs/nix.md) is the
  rest of it.
- `treefmt.nix` formats everything `moon fmt` does not: nix, shell, `.mjs` and
  `.json`. `.mbt` is deliberately not treefmt's — `moon fmt` formats a module,
  not a file list. Run it with `nix fmt`; `nix flake check` runs it as a check.
  Markdown is nobody's: `just docs-check` reads the pages by exact fence, so a
  formatter that re-wraps them would silently change what is compiled.

## Releasing

Pushing a `v*` tag publishes to mooncakes.io
(`.github/workflows/release.yml`). A mooncakes release cannot be taken back, so
the version must be right before the tag exists:

```sh
# 1. bump every declared version — `moon.mod`, and each side module's own
#    version and its `poteto0/endor@…` dependency — then commit
just release-check v0.2.0   # verifies exactly that, before you tag
git tag v0.2.0 && git push origin v0.2.0
```

The workflow re-runs `just release-check` and `just ci-check` against the tagged
tree before publishing. It needs two repository secrets, which are the `token`
and `username` fields `moon login` writes to `~/.moon/credentials.json`:
`MOONCAKES_TOKEN` and `MOONCAKES_USERNAME`.

Extra MoonBit skills: <https://github.com/moonbitlang/skills>
