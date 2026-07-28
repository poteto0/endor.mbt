// The CLI is a separate MoonBit module, for the same reason `examples/` is: it
// needs dependencies and a backend the SDK must not. `moonbitlang/x/fs` and
// `moonbitlang/x/sys` give it real file and process access, and file access
// means a `native` build — while `poteto0/endor` itself declares
// `preferred_target = "js"` and depends on nothing but `moonbitlang/async`.
// Keeping the CLI here means a consumer resolving the SDK never resolves any
// of that, and someone who wants the CLI can `moon add poteto0/endor-cli`
// without it.
//
// `moon.work` at the repository root wires `poteto0/endor` here to the local
// checkout instead of the registry, so the CLI always generates against the
// working tree.

name = "poteto0/endor-cli"

version = "0.3.0"

license = "MIT"

preferred_target = "native"

description = "Command-line tools for poteto0/endor; `endor-cli abi` generates MoonBit contract presets from ABI documents (experimental)"

import {
  "poteto0/endor@0.3.0",
  "moonbitlang/x@0.4.46",
}
