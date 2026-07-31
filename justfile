# the SDK talks to a browser-injected JS object, so `js` is the only backend
# that can build `ffi/` — every recipe below pins it explicitly
target := "js"

help:
  @just -l

alias ut := unit-test
[group("ci")]
unit-test opts="":
  @moon test --target {{target}} {{opts}}

# end-to-end tests against a local Anvil node (`just anvil` first) — what they
# do and do not prove is in docs/e2e.md. They are not part of `ci-check`: that
# recipe is also the pre-commit hook, and committing must not need a node.
[group("ci")]
e2e-test port="8545": (require-node port)
  @ENDOR_E2E_RPC_URL=http://127.0.0.1:{{port}} moon test --target {{target}} -p poteto0/endor/e2e

alias e2e := e2e-test

# refuse to "pass" by skipping every test when nothing is listening. `--retry`
# covers the node CI started in the background still binding its port.
[private]
require-node port:
  @curl -sf --retry 30 --retry-delay 1 --retry-connrefused -o /dev/null \
    -X POST -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
    http://127.0.0.1:{{port}} \
    || { echo "error: no JSON-RPC node on port {{port}} — start one with \`just anvil {{port}}\`"; exit 1; }

# a throwaway chain for `just e2e`. CI runs `just anvil 8545 --silent &`, so the
# node it tests against is configured here rather than in the workflow.
[group("develop")]
anvil port="8545" *flags="":
  @anvil --port {{port}} {{flags}}

alias ut-cov := unit-test-coverage
[group("ci")]
unit-test-coverage:
  @moon test --enable-coverage --target {{target}}
  @moon coverage report -f summary

[group("ci")]
fmt:
  @moon fmt

# non-mutating `fmt`, for CI
[group("ci")]
fmt-check:
  @moon fmt --check

[group("ci")]
check:
  @moon check --target {{target}}

[group("ci")]
build:
  @moon build --target {{target}}

[group("ci")]
info:
  @moon info

# non-mutating `info`: fails when a committed .mbti no longer matches the source
[group("ci")]
info-check: info
  @git diff --exit-code -- '*.mbti' || { echo "error: .mbti is stale — run \`just info\` and commit the diff"; exit 1; }

# what `moon publish` would upload. An allowlist, not a denylist: the exclude
# list in `moon.mod` is hand-maintained, so a new directory has to fail *closed*
# — `backend/` and `e2e/` install a fake wallet over `globalThis.ethereum` and a
# mooncakes release cannot be taken back. Runs on every commit, since it needs
# no node and a release gate is too late to learn this.
[group("ci")]
archive-check:
  #!/usr/bin/env bash
  set -euo pipefail
  ships=$'CHANGELOG.md\nLICENSE\nREADME.md\nREADME.mbt.md\nendor.mbt\nmoon.mod\nmoon.pkg\npkg.generated.mbti\ntypes\ncrypto\ncodec\neip712\nabi\ncontract\nprovider\nffi'
  # the file list goes to stderr, interleaved with progress lines that all
  # contain spaces, unlike archive paths
  extra=$(moon package --list 2>&1 | grep -v ' ' | cut -d/ -f1 | sort -u \
    | grep -vxF "$ships" || true)
  [ -z "$extra" ] || {
    echo "error: the published archive would ship, beyond the SDK itself:"
    echo "$extra" | sed 's/^/  /'
    echo "add it to \`exclude\` in moon.mod, or to \`ships\` here if it is meant to ship"
    exit 1
  }
  echo "ok: the archive ships only the SDK packages"

# `cmd/` is its own module with its own backend: it needs real file access,
# which means `native`, while everything above pins `js`. So it gets its own
# recipes rather than a `--target` argument on the shared ones. `moon fmt` and
# `moon info` at the root already reach it — `moon.work` lists it as a member.
[group("ci")]
cli-check:
  @cd cmd && moon check --target native

# scoped to the CLI's own package. `cli-check` compiles the SDK for `native`,
# which is the part that has to hold — the CLI links it — but the SDK's *tests*
# are written for the target it pins, and `just unit-test` runs them there.
# Letting them run here instead turns every `js`-only corner of `moonbitlang/
# core` (`BigInt::from_string` on a `0x` literal, say) into a CLI failure about
# a package the CLI never calls.
alias cli-ut := cli-test
[group("ci")]
cli-test opts="":
  @cd cmd && moon test --target native -p poteto0/endor-cli/endor-cli {{opts}}

[group("ci")]
cli-test-coverage:
  @cd cmd && moon coverage clean && moon test --enable-coverage --target native -p poteto0/endor-cli/endor-cli
  @cd cmd && moon coverage report -f summary

# The documentation site: https://endor.poteto-mahiro.com
#
# `website/` is markdown rendered by `astra`, a static site generator written in
# MoonBit, and the live demo on each cookbook page is a package of
# `website/islands/` compiled to an ES module the page hydrates. So the recipes
# below are two builds — the MoonBit one, then the site around it.

# the compiled demos. `moon.work` lists `website/islands` as a member, so this
# resolves `poteto0/endor` from the working tree: what the reader clicks is the
# SDK as it is now, not as the registry last published it.
[group("docs")]
docs-islands:
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{justfile_directory()}}/website/islands"
  moon build --target {{target}} --release
  out="{{justfile_directory()}}/website/public/islands"
  rm -rf "$out" && mkdir -p "$out"
  built="{{justfile_directory()}}/_build/{{target}}/release/build/poteto0/endor-website-islands"
  # every package except the shared `ui`, which is a library and links no entry
  for js in "$built"/*/*.js; do
    grep -q 'as hydrate' "$js" && cp "$js" "$out/"
  done
  ls "$out" | sed 's/^/  /'

[group("docs")]
docs-build: docs-islands
  @cd website && npm ci --silent && npx astra build

# the check neither `docs-check` nor `docs-islands` can make: that the built
# demos are ones a browser hydrates. A wrong `link` format, an island renamed
# out from under its `<Island name=…>`, a missing stylesheet — each of those
# fails silently, leaving a page that renders with the demo simply absent.
# Drives no wallet: there is none in a headless browser, and every demo is
# written to say so rather than to break.
[group("docs")]
docs-smoke: docs-build
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{justfile_directory()}}/website"
  # `--with-deps` installs the system libraries the browser needs, which takes
  # root — fine on a CI runner, a password prompt on a developer's machine that
  # already has them
  if [ -n "${CI:-}" ]; then
    npx playwright install --with-deps chromium
  else
    npx playwright install chromium
  fi
  node smoke.mjs dist-docs

# serve the site on http://localhost:7777 with the demos wired up
[group("docs")]
docs-dev: docs-islands
  @cd website && npx astra dev

# every documented MoonBit example, compiled: the site's pages and the README
# the registry shows. `moon test` never reaches markdown in this module (#8), so
# each one would otherwise be prose that nothing proves — and prose about an API
# rots silently. When this check was written, `README.mbt.md` had two examples
# that no longer compiled: a package that had moved, and a `catch` that had gone
# non-exhaustive under a variant added since.
#
# Each file becomes one package of *this* module, so a snippet resolves the
# working tree rather than whatever the registry last published, and so two
# pages may name the same function without colliding.
#
# A block that cannot compile on its own — a `fn main`, a fragment, a shell
# transcript — is tagged ```moonbit no-check and skipped: the info string is
# matched exactly, so tagging is deliberate rather than accidental.
[group("ci")]
docs-check:
  #!/usr/bin/env bash
  set -euo pipefail
  root="{{justfile_directory()}}"
  out="$root/_docs_check"
  trap 'rm -rf "$out"' EXIT
  rm -rf "$out"
  pkgs=()
  while IFS= read -r md; do
    # ```moonbit on the site, where astra highlights it; ```mbt-example in the
    # README, where `moon fmt` claims every ```moonbit block as a doctest and
    # rewrites it — inserting `///|` before each definition and retagging it
    # `nocheck`, which would both uglify the README and turn this check off.
    body=$(awk '
      /^```(moonbit|mbt-example)$/ { on = 1; next }
      /^```/                       { on = 0; next }
      on                           { print }
    ' "$md")
    [ -n "$body" ] || continue
    slug=$(printf '%s' "${md#website/}" | sed 's/\.mbt\.md$//; s/\.md$//; s#[/_.]#-#g')
    mkdir -p "$out/$slug"
    printf '%s\n' "$body" > "$out/$slug/main.mbt"
    cp "$root/website/.docs-check.moon.pkg" "$out/$slug/moon.pkg"
    pkgs+=("_docs_check/$slug")
  # the site's pages, plus the published README. `README.md` is a symlink to
  # `README.mbt.md`, so checking one checks both. `islands/` is MoonBit source
  # with its own `.mooncakes` checkout under it, and every build directory
  # carries a README nobody here wrote — feeding either to the compiler would
  # check somebody else's docs.
  done < <(cd "$root" && { echo README.mbt.md; find website \
    \( -name node_modules -o -name islands -o -name dist-docs -o -name public \
       -o -name .mooncakes -o -name _build -o -name target \) -prune \
    -o -name '*.md' -print | sort; })
  [ ${#pkgs[@]} -gt 0 ] || { echo "error: no \`\`\`moonbit blocks found"; exit 1; }
  moon check --target {{target}} --deny-warn "${pkgs[@]}"
  echo "ok: ${#pkgs[@]} documentation pages compile"

# the check the ABI generator itself cannot make: that what it wrote compiles.
# `moon test` never compiles generated source — it only compares it to a string
# — which is the same blind spot doc examples have in this repository, and the
# reason they rot. So the CLI is run for real against `fixtures/`, and the
# result is checked as a standalone package.
[group("ci")]
codegen-check:
  #!/usr/bin/env bash
  set -euo pipefail
  scratch=$(mktemp -d)
  trap 'rm -rf "$scratch" "{{justfile_directory()}}/_codegen_check"' EXIT
  mkdir -p "$scratch/abi"
  # both shapes an input comes in: the ABI array, and a compiler artifact
  # carrying the creation code as well — the second is the only one that
  # generates a `deploy`, so it is the only one that compiles one
  cp fixtures/abi/*.abi fixtures/abi/*.json "$scratch/abi/"
  printf 'version: v%s\nabi:\n  in: ./abi\n  out: ./outputs\n' \
    "$(grep -m1 '^version' moon.mod | cut -d'"' -f2)" > "$scratch/endor.yaml"
  cd cmd && moon build --target native && cd ..
  cli="{{justfile_directory()}}/_build/native/debug/build/poteto0/endor-cli/endor-cli/endor-cli.exe"
  (cd "$scratch" && "$cli" abi)
  # a package of *this* module, so it resolves `poteto0/endor` from the working
  # tree and not from whatever the registry last published
  rm -rf _codegen_check && mkdir _codegen_check
  cp "$scratch"/outputs/*.mbt "$scratch"/outputs/moon.pkg _codegen_check/
  # scoped to the generated package: `ci` and `ci-check` both run `check` and
  # `fmt`/`fmt-check` over the whole module already, and the only thing they
  # cannot see is this directory, which does not exist when they run
  moon check --target {{target}} --deny-warn _codegen_check
  # and it came out formatted, so nobody's `just fmt` shows it as a diff
  moon fmt --check _codegen_check
  echo "ok: the generated code compiles and is already formatted"

# what the pre-commit hook runs: formats and regenerates in place
[group("ci")]
ci: unit-test fmt check info archive-check cli-check cli-test codegen-check docs-check

# what GitHub Actions runs: same checks, but fails instead of rewriting files
[group("ci")]
ci-check: fmt-check check build unit-test info-check archive-check cli-check cli-test codegen-check docs-check

# every version this repo declares must agree with the release tag. `moon publish`
# uploads whatever `moon.mod` says and ignores the tag, and a mooncakes release
# cannot be taken back — so run this *before* `git tag`, not after.
# just release-check v0.2.0
[group("ci")]
release-check tag:
  #!/usr/bin/env bash
  set -euo pipefail
  want="{{tag}}"
  want="${want#v}"
  fail=0
  expect() { # expect <what> <found>
    [ "$2" = "$want" ] || { echo "error: $1 is \"$2\", expected \"$want\""; fail=1; }
  }
  expect "moon.mod version" \
    "$(grep -m1 '^version' moon.mod | cut -d'"' -f2)"
  # the demo should show the version being released, not the previous one
  expect "examples/get-address dependency on poteto0/endor" \
    "$(grep -m1 'poteto0/endor@' examples/get-address/moon.mod | cut -d'@' -f2 | cut -d'"' -f1)"
  # the CLI is its own module and its own release, but it generates code against
  # this SDK — a CLI declaring a version the SDK never had is a CLI nobody can
  # resolve, so both its own version and what it pins move together with the tag
  expect "cmd version" \
    "$(grep -m1 '^version' cmd/moon.mod | cut -d'"' -f2)"
  expect "cmd dependency on poteto0/endor" \
    "$(grep -m1 'poteto0/endor@' cmd/moon.mod | cut -d'@' -f2 | cut -d'"' -f1)"
  # and what the binary itself answers `endor-cli version` with — an installed
  # binary has no `moon.mod` to read, so its version is a constant that has to
  # be moved by hand and is therefore the one that gets forgotten
  expect "cmd/endor-cli VERSION" \
    "$(grep -m1 '^const VERSION' cmd/endor-cli/version.mbt | cut -d'"' -f2)"
  [ "$fail" -eq 0 ] || exit 1
  echo "ok: every declared version is ${want}"

alias ac := analyze-coverage
# just ac types
[group("develop")]
analyze-coverage +pkg:
  @moon coverage analyze -p {{pkg}}

alias ex := example
# serve examples/get-address on http://localhost:8000 (MetaMask needs http://, not file://)
# the example is its own module (see moon.work), so its artifact lands under its
# own module name rather than under `examples/`
[group("develop")]
example port="8000":
  @moon build --target {{target}}
  @cp _build/{{target}}/debug/build/poteto0/endor-examples-get-address/endor-examples-get-address.js examples/get-address/main.js
  @echo "open http://localhost:{{port}}/ in a browser with MetaMask installed"
  @python3 -m http.server {{port}} -d examples/get-address
