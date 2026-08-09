// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "poteto0/endor"

version = "0.7.0"

readme = "README.mbt.md"

repository = "https://github.com/poteto0/endor.mbt"

license = "MIT"

keywords = [
  "ethereum",
  "web3",
  "dapp",
  "json-rpc",
  "abi",
  "eip-712",
  "wallet",
  "eip-1193",
]

preferred_target = "js"

description = "An Ethereum SDK for MoonBit: typed JSON-RPC reads, contracts through their ABI, and signing — over a browser wallet, a node over HTTP, or a private key held in your own process."

import {
  "moonbitlang/async@0.20.3",
  "moonbitlang/x@0.4.49",
}

options(
  // Kept out of the published archive. `examples/` and `cmd/` matter most: each
  // is a nested module with its own `moon.mod` pulling in dependencies this one
  // does not have, so shipping either would drag them into a consumer's
  // resolution — `mizchi/luna` for the demo, and `moonbitlang/x` plus a
  // `native` build for the CLI. Being a separate module is what keeps those
  // dependencies out of *this* module's graph; listing it here is what keeps
  // its files out of the *archive*, which `moon package` fills from the
  // directory tree and not from the package graph. Both are needed. The rest is
  // repository-local tooling and notes. `e2e` and `backend` are packages of
  // this module that nothing shipped imports; `backend/anvil` in particular
  // installs a fake wallet over `globalThis.ethereum`, which a wallet SDK must
  // never hand a consumer. `just release-check` asserts they stayed out.
  // `_codegen_check` is the scratch package `just codegen-check` compiles: it
  // is gitignored and removed on the way out, but `moon package` reads the
  // directory tree it finds, so a publish racing a check must not ship it.
  exclude: [
    "examples",
    "cmd",
    "website",
    "e2e",
    "backend",
    "moon.work",
    "justfile",
    "flake.nix",
    "flake.lock",
    "treefmt.nix",
    ".envrc",
    "scripts",
    "AGENTS.md",
    "docs",
    "fixtures",
    "_codegen_check",
  ],
)
