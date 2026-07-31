// The documentation site's live demos.
//
// Every cookbook page on https://endor.poteto-mahiro.com carries a widget that
// drives a real wallet, and each one is a package of this module compiled to an
// ESM `hydrate` export that astra hydrates on the page. So a recipe is not a
// listing that happens to look right: the same code is what the reader clicks.
//
// A separate MoonBit module for the same reason `examples/` is one — the SDK's
// own `moon.mod` stays free of UI dependencies, and `moon.work` at the
// repository root wires `poteto0/endor` here to the local checkout rather than
// to the registry.

name = "poteto0/endor-website-islands"

version = "0.4.0"

license = "MIT"

preferred_target = "js"

description = "Live wallet demos embedded in the endor.mbt documentation site"

import {
  "poteto0/endor@0.4.0",
  "mizchi/luna@0.23.3",
  "mizchi/signals@0.6.5",
  "mizchi/js_browser@0.12.1",
  "mizchi/js@0.12.1",
}
