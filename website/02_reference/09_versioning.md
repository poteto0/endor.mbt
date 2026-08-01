---
title: Versioning policy
description: What counts as a breaking change, how much 0.x may break, and what you get in return.
---

# Versioning policy

`poteto0/endor` follows [Semantic Versioning](https://semver.org/). It is
currently `0.4.0`, and pre-1.0 the rule is short:

> **Until 1.0, breaking changes are accepted whenever they make the API right,
> and they land on a minor bump.**

The public surface is still being settled. A signature that turns out wrong — a
missing `raise`, a type that should not be public, a name that reads badly — gets
fixed rather than kept for compatibility. From 1.0 onward, the usual SemVer
promise applies: breaking changes wait for a major.

A published mooncakes release cannot be taken back, so pin what you depend on.

## What counts as a breaking change

**In the SDK's public API:**

- removing or renaming any `pub` function, type, constructor, method or field
- changing a function's parameter list, including making an optional parameter
  required, or reordering positional parameters
- changing a return type, or narrowing one — `T` to `T?` and `T?` to `T` are
  both breaking
- adding a `raise` to a function that had none, or widening the error type it
  raises
- **adding a variant to a `pub(all)` suberror or enum.** `ProviderError`,
  `ContractError`, `AbiError`, `CodecError`, `Fee`, `BlockTag` and
  `ReceiptStatus` are all matched exhaustively by callers, so a new variant
  turns a compiling `match` into a warning or an error. This one is easy to
  underestimate and is treated as breaking
- adding a field to a `pub(all)` struct that callers construct. The
  read-back-off-the-wire structs (`Block`, `TransactionReceipt`, `Log`) are
  built by their own `from_json` and nowhere else, so a new field there is
  additive for anyone reading them — but it still breaks a caller that
  constructs one in a test fixture, and it is listed as breaking
- moving a type between packages, even when the root package re-exports it under
  the same name — `@endor.TypedData` surviving does not help a caller who spelled
  `@types.TypedData`
- changing what a function does on the wire: a different JSON-RPC method, a
  different default, a field that is now sent where it used to be omitted

**Not breaking:**

- adding a new function, type, or package
- adding an *optional* parameter with a default that preserves the old behaviour
- adding a variant to a `priv` or non-`pub(all)` type
- widening what an input accepts — a constructor that used to reject a form it
  now handles
- documentation, comments, and error *message* text. The message inside
  `Rpc(code~, message~)` or `InvalidHex(what)` is for a human; matching on it is
  not a supported way to branch, and the code is
- anything in `abi/codegen`, `cmd/` (`endor-cli`), `examples/`, `website/`,
  `backend/` and `e2e/` — see below

## What is outside the promise

**`abi/codegen` and `endor-cli` are experimental.** The generated output's shape,
the CLI's flags and `endor.yaml`'s schema may change on any release. They are
labelled experimental in the [reference](./abi/#generating-a-preset-experimental)
and in `cmd/README.md`. `endor-cli` is a separate module with its own version
anyway — it is installed as a binary rather than depended on, so it cannot break
your build by moving.

**Repository-only packages ship to nobody.** `backend/`, `e2e/`, `examples/` and
`website/` are excluded from the published archive, which
[`just archive-check`](https://github.com/poteto0/endor.mbt/blob/main/justfile)
asserts on every commit — the check is an allowlist, so a new directory fails
closed rather than leaking into a release.

**Error message text is not API.** Branch on the variant, not on the string.

**MoonBit's own moving parts.** The SDK follows the toolchain and
`moonbitlang/core`; a change forced by a MoonBit release is documented, but it is
not something the SDK can hold back.

## How a break is announced

Every breaking change is listed in
[`CHANGELOG.md`](https://github.com/poteto0/endor.mbt/blob/main/CHANGELOG.md)
under **Changed**, marked `**Breaking:**`, with the issue number and with what to
do about it. The entry says the migration, not just the fact:

> **Breaking:** EIP-712 typed data moved out of `types` into its own package:
> `@types.TypedData` / `TypedDataDomain` / `TypedDataField` are now `@eip712.…`.
> … `@endor.TypedData` is unchanged — the root re-exports the three types from
> their new home, so a caller that spells them `@endor.…` needs no change. (#55)

Where a rename can be softened, it is: deprecated blocks live in a
`deprecated.mbt` per package rather than disappearing in the same release that
replaces them.

## Version numbers move together

The SDK, the example module and `endor-cli` all declare a version, and
`endor-cli` also pins the SDK it generates code against. A release tag asserts
that every one of them agrees before anything is published:

```sh
just release-check v0.5.0   # run this *before* `git tag`
```

That check exists because `moon publish` uploads whatever `moon.mod` says and
ignores the tag, and a mooncakes release cannot be withdrawn.

## What you can rely on before 1.0

Even pre-1.0, three things do not change on a whim:

1. **The SDK stays stateless.** No cached account, no cached chain, no session.
   This is a design decision, not an unfinished feature —
   [How the SDK is shaped](/guide/design/) explains why.
2. **Wallet-side failures never panic.** Every EIP-1193 / EIP-1474 failure
   arrives as a `ProviderError`, and public API does not `abort`.
3. **`Provider::request` stays.** The typed helpers are a convenience over it,
   and anything the SDK has not wrapped remains reachable.
