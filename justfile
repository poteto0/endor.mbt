# the SDK talks to a browser-injected JS object, so `js` is the only backend
# that can build `ffi/` — every recipe below pins it explicitly
target := "js"

help:
  @just -l

alias ut := unit-test
[group("ci")]
unit-test opts="":
  @moon test --target {{target}} {{opts}}

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
