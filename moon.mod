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

version = "0.2.0"

readme = "README.mbt.md"

repository = "https://github.com/poteto0/endor.mbt"

license = "MIT"

keywords = [ "ethereum", "metamask", "wallet", "eip-1193", "dapp", "web3" ]

preferred_target = "js"

description = "Typed, async MoonBit SDK for the EIP-1193 wallet providers that browser extensions such as MetaMask inject"

import {
  "moonbitlang/async@0.20.3",
}

options(
  // Kept out of the published archive. `examples/` matters most: it is a nested
  // module with its own `moon.mod` pulling in UI dependencies, so shipping it
  // would drag `mizchi/luna` into a consumer's resolution. The rest is
  // repository-local tooling and notes.
  exclude: [ "examples", "moon.work", "justfile", "AGENTS.md", "docs" ],
)
