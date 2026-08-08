#!/usr/bin/env bash
#
# What `.githooks/pre-commit` runs, through `just precommit` (#96): the part of
# `just ci-check` the staged diff can actually break. Every check run here is
# one of `ci-check`'s, and the PR gate runs that one in full — so this script is
# allowed to under-approximate, and the price of a wrong guess is a red PR
# rather than a broken `main`.
#
# What is staged decides:
#
#   always          `fmt-check` and `check` — whole-module and under a second
#                   each. `check` typing the *whole* module is what makes
#                   scoping the tests below safe: a rename that breaks a
#                   package nobody staged still fails right here.
#   a new top-level `archive-check`. Its only inputs are `exclude` in `moon.mod`
#                   and the set of top-level entries, and git tracks files, not
#                   directories — so a directory the archive would newly ship
#                   can only reach a commit as a file staged under it. This arm
#                   is therefore not an under-approximation like the rest: the
#                   check still fails *closed* on a top-level directory nobody
#                   excluded, which it has to, since a mooncakes release cannot
#                   be taken back.
#   a `.mbt`        `info-check`, and `unit-test` over the packages that
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
#   `moon.mod`      `archive-check`, whose `exclude` list that is, and
#                   `codegen-check`, which reads the `version` out of it.
#   `flake.nix` &c. nothing extra. The only check that reads them is
#                   `nix-pin-check`, which no arm below skips and which
#                   therefore runs on every commit — it is two `sed`s. Building
#                   the flake is CI's `nix` job; a commit must not need nix.
#   `moon.work` &c. everything — the `justfile`, the hook, this script and the
#                   toolchain pin as well. They decide what the checks are and
#                   what they reach, so the only honest answer to a change in
#                   one of them is the whole set.
#
# The selection is a list of reasons to *skip*, read off `ci-check`'s own
# dependency list rather than copied from it: a check added there runs here too
# until somebody says when it may be left out. Two are already said:
#
#   `build`      `check` types the module and `unit-test` links every package it
#                runs, which leaves a JS-emit failure.
#   `cli-check`  it is the only thing that compiles the SDK for `native`, a
#                target the SDK does not even pin — `moon.mod` says `js` and
#                every recipe repeats it. So a `native`-only break is real but
#                rare, and paying 1.5s for it on every `.mbt` commit is not the
#                trade this script makes. A CLI that changed still gets it.
#
# Both land as a red PR rather than a broken `main`, which is the deal the whole
# script runs on.
#
# Every check is still spelled as a `just` recipe, never as the command inside
# it: one place states how a check is run, and this script only decides which.

set -euo pipefail
cd "$(dirname "$0")/.."

# what the commit will contain. Deletions are dropped: a deleted file has no
# package left to test. Run by hand there is nothing staged, so fall back to the
# unstaged diff rather than passing having checked nothing.
changed=$(git diff --cached --name-only --diff-filter=d)
[ -n "$changed" ] || changed=$(git diff --name-only --diff-filter=d)
[ -n "$changed" ] || {
  echo "precommit: nothing changed"
  exit 0
}

# the package a file belongs to: the nearest directory above it holding a
# `moon.pkg`. The root is one, so this always lands on a real package.
pkg_of() {
  d=$(dirname "$1")
  while [ "$d" != "." ] && [ ! -f "$d/moon.pkg" ]; do d=$(dirname "$d"); done
  echo "$d"
}

# every top-level entry `HEAD` already has, newline-delimited and fenced so a
# name can be matched whole. A staged path whose first component is missing from
# it is a directory the archive has never seen. Empty when there is no `HEAD` to
# read — an initial commit then simply runs `archive-check`, which is the safe
# way round.
tops=$'\n'$(git ls-tree --name-only HEAD || true)$'\n'

full= info= cli= docs= codegen= archive= pkgs=
for f in $changed; do
  # orthogonal to the arms below — what pulls `archive-check` in is where a path
  # *starts*, not what it ends in
  case "$tops" in
    *$'\n'"${f%%/*}"$'\n'*) ;;
    *) archive=1 ;;
  esac
  # an arm sets the *check* its path pulls in rather than the extension it
  # matched, so each row of the table above is stated in one place. First match
  # wins, which is why the modules that have their own recipes are named before
  # the extensions that would otherwise claim them.
  case "$f" in
    moon.work | justfile | .githooks/* | scripts/* | .github/actions/*) full=1 ;;
    moon.mod)
      archive=1
      codegen=1
      ;;
    cmd/*)
      cli=1
      codegen=1
      ;;
    fixtures/abi/*) codegen=1 ;;
    examples/* | website/islands/*) ;;
    *.md) docs=1 ;;
    *.mbti)
      docs=1
      codegen=1
      ;;
    *.mbt)
      info=1
      pkgs="$pkgs $(pkg_of "$f")"
      ;;
    moon.pkg | */moon.pkg) pkgs="$pkgs $(pkg_of "$f")" ;;
    # a workflow, an editor's settings, a fixture that is not an ABI: no recipe
    # reads it, so the unconditional three are the whole answer
    *) ;;
  esac
done

if [ -n "$full" ]; then exec just ci-check; fi

# `ci-check`'s dependency list, read rather than copied — a copy would drift the
# moment a check was added there, and silently, since the PR gate would stay
# green while this script quietly stopped covering it. A name no arm below knows
# therefore runs, and forgetting costs a slow commit rather than an unchecked
# one.
for c in $(just --dump | sed -n 's/^ci-check: //p'); do
  case "$c" in
    build) continue ;;
    # run last instead, scoped to the packages the diff reaches
    unit-test) continue ;;
    info-check) [ -n "$info" ] || continue ;;
    archive-check) [ -n "$archive" ] || continue ;;
    cli-check) [ -n "$cli" ] || continue ;;
    cli-test) [ -n "$cli" ] || continue ;;
    docs-check) [ -n "$docs" ] || continue ;;
    codegen-check) [ -n "$codegen" ] || continue ;;
  esac
  just "$c"
done

[ -n "$pkgs" ] || {
  echo "precommit: no package changed"
  exit 0
}

# every `moon.pkg` that can *pull the set wider*, to ask which of them import
# what changed.
#
#   `cmd`, `examples`, `website` are the other members `moon.work` lists — their
#   own modules, checked above by their own recipes or not at all. Keep this
#   pathspec in step with that list.
#   `e2e`, `backend` are packages of this module, but ones `moon.mod` keeps out
#   of the published archive: `e2e` needs a node and skips itself without one,
#   `backend` is the harness it drives. Reaching them as *importers* therefore
#   only ever proves they still compile, and it is the widest edge in the graph
#   — `backend/http` imports `provider`, so a one-line edit under `types/` drags
#   both in for about a second. Editing one still tests it: they are excluded
#   here from who gets pulled in, not from `pkgs` above.
pkgfiles=$(git ls-files moon.pkg '*/moon.pkg' ':!:cmd/**' ':!:examples/**' \
  ':!:website/**' ':!:e2e/**' ':!:backend/**')
want=$(printf '%s\n' $pkgs | sort -u)
# a change under `types/` is a change to `abi/` as far as `abi/`'s tests are
# concerned, so grow the set until nothing outside it imports anything in it.
# `moon.pkg` spells an import as a plain string, which is what makes the
# dependency graph greppable.
while :; do
  pat=$(printf '%s\n' $want |
    sed 's#^#"poteto0/endor/#; s#^"poteto0/endor/\.$#"poteto0/endor#; s#$#"#' |
    paste -sd'|' -)
  # nothing importing the set is the answer for a package nobody imports yet —
  # a new leaf. `grep -l` calls that exit 1, which `set -e` would read as the
  # script having failed, so it is caught here and the blank line it leaves is
  # dropped rather than growing the set by an empty package name.
  more=$(grep -lE "$pat" $pkgfiles | sed 's#/*moon\.pkg$##; s#^$#.#' || true)
  next=$(printf '%s\n%s\n' "$want" "$more" | grep -v '^$' | sort -u)
  [ "$next" != "$want" ] || break
  want=$next
done

# `unit-test` splices its argument into a one-line command, so the set has to
# arrive space-separated rather than as the newlines `sort` left behind
scoped=$(echo $want)
echo "precommit: testing $scoped"
just unit-test "$scoped"
