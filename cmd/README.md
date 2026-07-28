# endor-cli

**Experimental.** A code generator for [`poteto0/endor`](../README.md): it turns
a contract's JSON ABI into the MoonBit source of a preset shaped like
`@contract.Erc20` — a struct wrapping a `Contract`, one method per function, a
topic getter per event.

```sh
$ cat endor.yaml
version: v0.3.0
abi:
  in: ./abi
  out: ./outputs

$ endor-cli abi
endor-cli abi — EXPERIMENTAL
  ...
erc20.abi -> ./outputs/erc20.mbt  (Erc20, 11 members)
wrote ./outputs/moon.pkg
```

One input file becomes one output file, named after it: `erc20.abi` generates
`erc20.mbt` holding `pub struct Erc20`. A `moon.pkg` is written alongside if
there is not one already; an existing one is never touched, only reported on.

## What it generates, and what it will not

It emits a method only where the MoonBit types follow from the ABI without
guessing: parameters and single return values of `address`, `bool`, `string`,
`uintN` and `intN`. Anything else — `bytes`, `bytesN`, arrays, tuples, several
return values, a Solidity overload MoonBit cannot spell twice — is **skipped**,
named on stdout and in a comment at the bottom of the generated file. It is not
approximated: a signature that looks right and hashes to a selector no contract
answers is worse than no signature at all. Reach those members through
`@contract.Contract::call` / `send`, which take the `AbiType`s directly.

Events are exempt, because a topic needs only the signature. `constructor`,
`fallback`, `receive` and `error` entries are dropped — a preset wraps a
contract that is already deployed.

**Read what it produces before you ship it.** The generator can tell that a
document is not an ABI; it cannot tell that the ABI is not the contract at the
address you will point the preset at.

## This is a separate module

`cmd/` has its own `moon.mod` (`poteto0/endor-cli`) for the same reason
`examples/` does: it needs `moonbitlang/x` for file access, and therefore a
`native` build, while the SDK depends on nothing but `moonbitlang/async` and
prefers `js`. Keeping it here means installing the SDK never resolves any of
that. `moon.work` at the repository root points its `poteto0/endor` dependency
at the working tree, so it always generates against the checkout rather than the
last published release.

Its version and its `poteto0/endor@…` pin move with the release tag; `just
release-check <tag>` asserts both.

## Development

```sh
just cli-check           # moon check --target native, in this module
just cli-test            # its unit tests
just cli-test-coverage   # ... with coverage
just codegen-check       # run it against fixtures/ and compile what came out
```

`just codegen-check` is the one that matters: `moon test` compares generated
source to expected source and never compiles it, so it is the only check that
proves the output builds.
