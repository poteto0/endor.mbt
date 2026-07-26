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

# what the pre-commit hook runs: formats and regenerates in place
[group("ci")]
ci: unit-test fmt check info

# what GitHub Actions runs: same checks, but fails instead of rewriting files
[group("ci")]
ci-check: fmt-check check build unit-test info-check

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
  # a release cannot be taken back, so also check what the archive contains:
  # the test-only packages are repo-only and `moon.mod` excludes them by hand,
  # with nothing else watching that denylist. `backend/anvil` matters most — it
  # can overwrite `globalThis.ethereum` with a fake wallet.
  for repo_only in e2e backend; do
    if moon package --list | grep -q "^${repo_only}/"; then
      echo "error: ${repo_only}/ is in the published archive — check moon.mod's exclude"
      fail=1
    fi
  done
  [ "$fail" -eq 0 ] || exit 1
  echo "ok: every declared version is ${want}, and the test-only packages stay unpublished"

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
