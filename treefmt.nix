# The formatter for everything `moon fmt` does not reach.
#
# `.mbt` is deliberately *not* here: `moon fmt` formats a module, not a file
# list, and it is the only thing that knows what a MoonBit doctest is — running
# it per-file from treefmt would rewrite the ```moonbit blocks in `README.mbt.md`
# that `just docs-check` compiles. `.mbt` stays `just fmt`; this covers the rest,
# which until now nothing formatted at all.
#
# Runs three ways, over the same config: `nix fmt`, `treefmt` inside
# `nix develop`, and `nix flake check` (as a non-mutating check).
{ lib, ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;

  # `scripts/` and the git hook. The hook has no extension, so it has to be
  # named — treefmt matches on the path, not on the shebang.
  #
  # Configured to argue with the scripts as little as possible: `-ci` keeps the
  # `case` arms indented under their `case`, the way they are written here, and
  # `simplify` is off because it rewrites code rather than laying it out, which
  # is not what a formatter is being asked for. What it does still take is the
  # column alignment inside a `case` arm — shfmt has no way to keep it.
  programs.shfmt.enable = true;
  programs.shfmt.simplify = false;
  settings.formatter.shfmt.options = [ "-ci" ];
  settings.formatter.shfmt.includes = [ ".githooks/pre-commit" ];

  # the site's build scripts and its JSON. Not markdown: the pages are input to
  # `just docs-check`, which extracts fenced blocks by exact info string, and
  # not YAML: the workflows are commented line by line and prettier moves
  # comments around when it re-wraps.
  # `mkForce`, because prettier's default include list is "every language it
  # knows" — markdown and YAML among them — and a second definition would add
  # to that list rather than replace it.
  programs.prettier.enable = true;
  settings.formatter.prettier.includes = lib.mkForce [
    "*.mjs"
    "*.json"
  ];
  # prettier's defaults are double quotes and semicolons; the scripts here are
  # written without either. A formatter adopted after the code exists should
  # settle the questions nobody has answered, not restyle the answers already
  # given.
  programs.prettier.settings = {
    singleQuote = true;
    semi = false;
  };

  settings.global.excludes = [
    # generated, vendored, or output
    "_build/**"
    ".mooncakes/**"
    "**/node_modules/**"
    "website/package-lock.json"
    "website/dist-docs/**"
    "website/public/islands/**"
    # fixtures are compiler output copied in verbatim: reformatting them would
    # make the ABI JSON stop matching what solc emitted
    "fixtures/**"
    # binary and prose
    "*.png"
    "*.gif"
    "*.mbt"
    "*.mbti"
    "*.md"
    "LICENSE"
  ];
}
