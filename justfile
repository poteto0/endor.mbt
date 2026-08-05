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
# do and do not prove is in docs/e2e.md. They are not part of `ci-check`, which
# `precommit` selects from — committing must not need a node. `e2e` is still a
# package that selection can land on, and it skips itself when there is none.
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
  ships=$'CHANGELOG.md\nLICENSE\nREADME.md\nREADME.mbt.md\nendor.mbt\nmoon.mod\nmoon.pkg\npkg.generated.mbti\ntypes\ncrypto\ncodec\neips\nabi\ncontract\nprovider\nffi'
  # the file list goes to stderr, interleaved with progress and diagnostic
  # lines. Keep only what can be an archive path — a warning's box-drawing
  # gutter has no spaces either, and once read as a path it fails the check
  # with a filename nobody can act on
  extra=$(moon package --list 2>&1 | grep -E '^[A-Za-z0-9._-]+(/|$)' | cut -d/ -f1 | sort -u \
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

# `npm ci` rather than `npm install`, so the site is built from the versions the
# lockfile names. Not `--silent`: npm silences its *errors* too, and a lockfile
# npm refuses then fails this recipe in under a second with nothing on screen.
# `package-lock.json` is generated with npm 10, the version Node 22 ships and CI
# therefore runs — npm 11 prunes optional transitive packages that npm 10 still
# expects, and a lockfile written by the newer one is one the older one rejects.
[group("docs")]
docs-build: docs-islands
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{justfile_directory()}}/website"
  npm ci --no-audit --no-fund
  npx astra build
  # Two ways a page comes out wrong that still build, render and deploy — both
  # of them shipped once before this check existed:
  #
  #   `:::`      a VitePress container. astra's markdown does not know the
  #              syntax and prints the fences as text. Raw HTML passes through,
  #              so a callout is `<div class="alert alert--warning">`.
  #   `&lt;a `   markup written where astra escapes it — the footer's `message`
  #              is text, not HTML, so a link there arrives as its source.
  bad=$(grep -rl -e ':::' -e '&lt;a ' dist-docs --include='*.html' || true)
  [ -z "$bad" ] || {
    echo "error: markup that did not render, in:"
    echo "$bad" | sed 's/^/  /'
    echo "  \`:::\` containers are not astra syntax — use <div class=\"alert alert--warning\">"
    echo "  HTML in a config string is escaped — put the link in \`footer.links\`"
    exit 1
  }

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

# serve the built site on http://localhost:7777
#
# Not `astra dev`: that renders pages but does not serve `public/`, so the
# stylesheet 404s and every island 404s with it — the site comes up in astra's
# default colours with no demos on it, which is a preview of nothing. Serving
# `dist-docs` costs a rebuild on each change and shows exactly what deploys.
[group("docs")]
docs-dev port="7777": docs-build
  @echo "open http://localhost:{{port}}/ — re-run \`just docs-dev\` after an edit"
  @python3 -m http.server {{port}} -d website/dist-docs

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

# every check, formatting and regenerating in place rather than failing
[group("ci")]
ci: unit-test fmt check info archive-check cli-check cli-test codegen-check docs-check

# what GitHub Actions runs: same checks, but fails instead of rewriting files
[group("ci")]
ci-check: fmt-check check build unit-test info-check archive-check cli-check cli-test codegen-check docs-check

# what `.githooks/pre-commit` runs (#96): the part of `ci-check` the staged diff
# can actually break. Every check here is one of `ci-check`'s, and the PR gate
# runs that one in full — so this recipe is allowed to under-approximate, and
# the price of a wrong guess is a red PR rather than a broken `main`.
#
# What is staged decides:
#
#   always          `fmt-check`, `check` and `archive-check` — whole-module and
#                   under a second each. `check` typing the *whole* module is
#                   what makes scoping the tests below safe: a rename that
#                   breaks a package nobody staged still fails right here; and
#                   `archive-check` is the one check that has to fail *closed*
#                   on a top-level directory nobody excluded, so it is never
#                   selected away.
#   a `.mbt`        `info-check`; `cli-check`, the only thing that compiles the
#                   SDK for `native`; and `unit-test` over the packages that
#                   changed plus every package that imports one of them,
#                   transitively.
#   a `.mbti`       `docs-check` and `codegen-check`. Both only *compile*
#                   against the SDK, so nothing but its interface can move
#                   them — and `info-check` above is what guarantees a moved
#                   interface arrives as a staged `.mbti`.
#   a `.md`         `docs-check`, whose input it is.
#   `cmd/`          `cli-check` and `cli-test`, and `codegen-check`, whose
#                   generator that is.
#   `fixtures/abi/` `codegen-check`, whose inputs those are.
#   `moon.mod` &c.  everything — `moon.work`, this `justfile`, the hook and the
#                   toolchain pin as well. They decide what the checks are and
#                   what they reach, so the only honest answer to a change in
#                   one of them is the whole set.
#
# The selection is a list of reasons to *skip*, read off `ci-check`'s own
# dependency list rather than copied from it: a check added there runs here
# too until somebody says when it may be left out. `build` is the one already
# said — `check` types the module and `unit-test` links every package it runs,
# which leaves a JS-emit failure, and that is what the PR gate is for.
[group("ci")]
precommit:
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{justfile_directory()}}"

  # what the commit will contain. Deletions are dropped: a deleted file has no
  # package left to test. Run by hand there is nothing staged, so fall back to
  # the unstaged diff rather than passing having checked nothing.
  changed=$(git diff --cached --name-only --diff-filter=d)
  [ -n "$changed" ] || changed=$(git diff --name-only --diff-filter=d)
  [ -n "$changed" ] || { echo "precommit: nothing changed"; exit 0; }

  # the package a file belongs to: the nearest directory above it holding a
  # `moon.pkg`. The root is one, so this always lands on a real package.
  pkg_of() {
    d=$(dirname "$1")
    while [ "$d" != "." ] && [ ! -f "$d/moon.pkg" ]; do d=$(dirname "$d"); done
    echo "$d"
  }

  full= info= native= cli= docs= codegen= pkgs=
  for f in $changed; do
    # an arm sets the *check* its path pulls in rather than the extension it
    # matched, so each row of the table above is stated in one place. First
    # match wins, which is why the modules that have their own recipes are
    # named before the extensions that would otherwise claim them.
    case "$f" in
      moon.mod|moon.work|justfile|.githooks/*|.github/actions/*) full=1 ;;
      cmd/*)                        cli=1; native=1; codegen=1 ;;
      fixtures/abi/*)               codegen=1 ;;
      examples/*|website/islands/*) ;;
      *.md)                         docs=1 ;;
      *.mbti)                       docs=1; codegen=1 ;;
      *.mbt)                        info=1; native=1; pkgs="$pkgs $(pkg_of "$f")" ;;
      moon.pkg|*/moon.pkg)          pkgs="$pkgs $(pkg_of "$f")" ;;
      # a workflow, an editor's settings, a fixture that is not an ABI: no
      # recipe here reads it, so the unconditional three are the whole answer
      *)                            ;;
    esac
  done

  if [ -n "$full" ]; then exec just ci-check; fi

  # `ci-check`'s dependency list, read rather than copied — a copy would drift
  # the moment a check was added there, and silently, since the PR gate would
  # stay green while this recipe quietly stopped covering it. A name no arm
  # below knows therefore runs, and forgetting costs a slow commit rather than
  # an unchecked one.
  for c in $(just --dump | sed -n 's/^ci-check: //p'); do
    case "$c" in
      build)         continue ;;
      # run last instead, scoped to the packages the diff reaches
      unit-test)     continue ;;
      info-check)    [ -n "$info" ] || continue ;;
      # the only thing that compiles anything for `native`, so it is owed both
      # to a CLI that changed and to an SDK the CLI links
      cli-check)     [ -n "$native" ] || continue ;;
      cli-test)      [ -n "$cli" ] || continue ;;
      docs-check)    [ -n "$docs" ] || continue ;;
      codegen-check) [ -n "$codegen" ] || continue ;;
    esac
    just "$c"
  done

  [ -n "$pkgs" ] || { echo "precommit: no package changed"; exit 0; }

  # every `moon.pkg` of this module, to ask which of them import what changed.
  # The excluded three are the other members `moon.work` lists — their own
  # modules, checked above by their own recipes or not at all; keep this
  # pathspec in step with that list.
  pkgfiles=$(git ls-files moon.pkg '*/moon.pkg' ':!:cmd/**' ':!:examples/**' \
    ':!:website/**')
  want=$(printf '%s\n' $pkgs | sort -u)
  # a change under `types/` is a change to `abi/` as far as `abi/`'s tests are
  # concerned, so grow the set until nothing outside it imports anything in it.
  # `moon.pkg` spells an import as a plain string, which is what makes the
  # dependency graph greppable.
  while :; do
    pat=$(printf '%s\n' $want |
      sed 's#^#"poteto0/endor/#; s#^"poteto0/endor/\.$#"poteto0/endor#; s#$#"#' |
      paste -sd'|' -)
    more=$(grep -lE "$pat" $pkgfiles | sed 's#/*moon\.pkg$##; s#^$#.#')
    next=$(printf '%s\n%s\n' "$want" "$more" | sort -u)
    [ "$next" != "$want" ] || break
    want=$next
  done

  # `unit-test` splices its argument into a one-line command, so the set has to
  # arrive space-separated rather than as the newlines `sort` left behind
  scoped=$(echo $want)
  echo "precommit: testing $scoped"
  just unit-test "$scoped"

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
  expect "examples/demo dependency on poteto0/endor" \
    "$(grep -m1 'poteto0/endor@' examples/demo/moon.mod | cut -d'@' -f2 | cut -d'"' -f1)"
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
# serve examples/demo on http://localhost:8000 (MetaMask needs http://, not file://)
# the example is its own module (see moon.work), so its artifact lands under its
# own module name rather than under `examples/`
[group("develop")]
example port="8000":
  @moon build --target {{target}}
  @cp _build/{{target}}/debug/build/poteto0/endor-examples-demo/endor-examples-demo.js examples/demo/main.js
  @echo "open http://localhost:{{port}}/ in a browser with MetaMask installed"
  @python3 -m http.server {{port}} -d examples/demo
