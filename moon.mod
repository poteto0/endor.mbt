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

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/poteto0/endor.mbt"

license = "MIT"

keywords = [ "ethereum", "metamask", "wallet", "eip-1193", "dapp", "web3" ]

preferred_target = "js"

description = "Typed, async MoonBit SDK for the EIP-1193 wallet providers that browser extensions such as MetaMask inject"

import {
  "moonbitlang/async@0.20.3",
}
