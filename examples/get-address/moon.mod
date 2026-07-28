// Examples are a separate MoonBit module: the SDK itself stays dependency-free
// apart from `moonbitlang/async`, while the demo is free to pull in a UI
// library. `moon.work` at the repository root wires `poteto0/endor` here to the
// local checkout instead of the registry.

name = "poteto0/endor-examples-get-address"

version = "0.1.0"

license = "MIT"

preferred_target = "js"

description = "Browser demo: connect MetaMask and render the wallet info with Luna"

import {
  "poteto0/endor@0.4.0",
  "mizchi/luna@0.23.3",
  "mizchi/signals@0.6.5",
  "mizchi/js_browser@0.12.1",
}
