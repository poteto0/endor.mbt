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
#   `moon.mod` &c.  everything — `moon.work`, the `justfile`, the hook, this
#                   script and the toolchain pin as well. They decide what the
#                   checks are and what they reach, so the only honest answer
#                   to a change in one of them is the whole set.
#
# The selection is a list of reasons to *skip*, read off `ci-check`'s own
# dependency list rather than copied from it: a check added there runs here too
# until somebody says when it may be left out. `build` is the one already said —
# `check` types the module and `unit-test` links every package it runs, which
# leaves a JS-emit failure, and that is what the PR gate is for.
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
  # matched, so each row of the table above is stated in one place. First match
  # wins, which is why the modules that have their own recipes are named before
  # the extensions that would otherwise claim them.
  case "$f" in
    moon.mod|moon.work|justfile|.githooks/*|scripts/*|.github/actions/*) full=1 ;;
    cmd/*)                        cli=1; native=1; codegen=1 ;;
    fixtures/abi/*)               codegen=1 ;;
    examples/*|website/islands/*) ;;
    *.md)                         docs=1 ;;
    *.mbti)                       docs=1; codegen=1 ;;
    *.mbt)                        info=1; native=1; pkgs="$pkgs $(pkg_of "$f")" ;;
    moon.pkg|*/moon.pkg)          pkgs="$pkgs $(pkg_of "$f")" ;;
    # a workflow, an editor's settings, a fixture that is not an ABI: no recipe
    # reads it, so the unconditional three are the whole answer
    *)                            ;;
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
    build)         continue ;;
    # run last instead, scoped to the packages the diff reaches
    unit-test)     continue ;;
    info-check)    [ -n "$info" ] || continue ;;
    # the only thing that compiles anything for `native`, so it is owed both to
    # a CLI that changed and to an SDK the CLI links
    cli-check)     [ -n "$native" ] || continue ;;
    cli-test)      [ -n "$cli" ] || continue ;;
    docs-check)    [ -n "$docs" ] || continue ;;
    codegen-check) [ -n "$codegen" ] || continue ;;
  esac
  just "$c"
done

[ -n "$pkgs" ] || { echo "precommit: no package changed"; exit 0; }

# every `moon.pkg` of this module, to ask which of them import what changed. The
# excluded three are the other members `moon.work` lists — their own modules,
# checked above by their own recipes or not at all; keep this pathspec in step
# with that list.
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
