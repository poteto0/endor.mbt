# endor-cli

The command-line tools for [`poteto0/endor`](../README.md). One binary, one
subcommand per job:

```sh
$ endor-cli
usage: endor-cli [-h | --help] [-v | --version] <command> [<args>]
...
generate code
   abi        Write a MoonBit contract preset per ABI document (EXPERIMENTAL)

about
   help       Show this help, or `help <command>` for one command
   version    Print the version of this binary
```

`endor-cli help <command>` says what a command reads and writes; so does
`<command> --help`. Anything the CLI does not recognise — an unknown subcommand,
an unknown option, an argument a subcommand does not take — is refused and exits
non-zero rather than being stepped over, because a flag that is silently ignored
is a build script that has been asking for something for a month and never got
it.

## `endor-cli abi`

**Experimental.** A code generator: it turns a contract's JSON ABI into the
MoonBit source of a preset shaped like `@contract.Erc20` — a struct wrapping a
`Contract`, one method per function, a topic getter per event.

It takes no arguments. What it reads and where it writes is `endor.yaml` in the
directory it runs in, which is checked in, so the generated files a repository
holds are reproducible by anyone who clones it rather than dependent on the
flags whoever ran it last happened to type.

```sh
$ cat endor.yaml
version: v0.4.0
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

### What it generates, and what it will not

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

## Adding a subcommand

`main.mbt` is the entry point and nothing else: it turns an argument vector into
an `Invocation`, and an exit code into a process. `dispatch.mbt` holds
`commands()` — the one table of what exists — and reads it three ways: to run a
command, to explain one, and to render `endor-cli help`. So a name cannot
dispatch without being listed, or be listed without dispatching, and `--help`
works for a command whose author never thought about it.

A subcommand is therefore a file with a `handle_<name>(args) -> Int` and a
`print_<name>_usage()`, plus one entry in `commands()`. Handlers print their own
diagnostics, refuse arguments they do not take (via `refuse`), and never call
`@sys.exit` — reporting failure by returning it is what lets `run_for_args` be
driven from a test.

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
