# The nix development environment

```sh
nix develop        # or `just nix-dev`, or `direnv allow` once (.envrc)
just ci-check      # everything CI gates on, from inside the shell
```

The shell carries the MoonBit toolchain **at the version CI installs**, plus
`just`, Node 22, `anvil`, python3 and `treefmt`. Nothing else on your machine is
touched: `~/.moon` stays yours and writable, so `moon update` and `moon add`
work from inside the shell as they do outside it.

Nix is **optional**. `.github/actions/setup` — two `curl | bash` installers — is
still what CI runs and still works; the flake is a second way in, for people who
would rather not install a nightly toolchain into their home directory by hand.

## What is where

| File          | What it is                                                     |
| ------------- | -------------------------------------------------------------- |
| `flake.nix`   | the dev shell, the formatter, and the flake's own checks         |
| `flake.lock`  | the pin — nixpkgs, the MoonBit overlay, treefmt-nix              |
| `treefmt.nix` | which formatter owns which file (`.mbt` is not one of them)      |
| `.envrc`      | direnv, for people who want the shell entered on `cd`            |

## Where MoonBit comes from

Not from nixpkgs — it is not there. The open-sourced compiler builds only the
wasm-gc backend, and this SDK pins `js`, so the toolchain has to be the official
binary. [`moonbit-community/moonbit-overlay`][overlay] mirrors exactly the
tarballs `cli.moonbitlang.com/install/unix.sh` unpacks and patchelfs them for
nix, with one attribute per released version.

That release is pinned in two places, and they must agree:

- `.github/actions/setup` — `MOONBIT_INSTALL_VERSION`, what CI installs
- `flake.nix` — `moonbitVersion`, what `nix develop` hands out

`just nix-pin-check` fails when they disagree. It is part of `just ci-check`,
needs no nix, and exists because the reason to pin at all (#76 — the toolchain
is released nightly, and a release that changes `moon fmt` or `moon info` output
turns every open PR red at once) is defeated the moment half the developers are
on a different pin than CI.

**Bumping the toolchain** means moving both, in the same PR that carries
whatever `just info` and `just fmt` regenerate. The flake's spelling of the
version has the `core` revision appended (`0.10.6+80dc50f24` **`+c19f78e`**),
which is the overlay's coordinate and has no counterpart in the setup action —
copy it from [the overlay's version list][versions]; `nix-pin-check` compares
everything before that last `+`.

Only `x86_64-linux` and `aarch64-darwin` are listed as systems: those are the
platforms the pinned release publishes binaries for. There is no aarch64 Linux
MoonBit build to mirror.

## Formatting

`treefmt` — `nix fmt`, or `just nix-fmt` — formats everything **except** `.mbt`,
which stays `moon fmt` (`just fmt`). The split is not tidiness: `moon fmt`
formats a module rather than a file list, and it is the only thing that knows a
MoonBit doctest from a markdown code block, so running it per-file out of
treefmt would rewrite the ```` ```moonbit ```` examples in `README.mbt.md` that
`just docs-check` compiles.

What treefmt does own is `nix` (nixfmt), shell (shfmt — `scripts/` and
`.githooks/pre-commit`), and `.mjs` / `.json` (prettier, configured for the
quote and semicolon style already in the tree). Markdown and YAML are
deliberately left alone: the pages are input to `just docs-check`, which matches
fenced blocks by exact info string, and the workflows are commented line by
line.

`nix flake check` runs the same config in check mode, so an unformatted tree is
a red CI job rather than a surprise diff.

## What CI checks

The `nix` job in `.github/workflows/ci.yml`:

- `nix flake check` — treefmt over the tree, and the dev shell's tools built
  and run (`moon version`, `just`, `node`, `anvil`, `python3`)
- `nix develop --command …` — `moon update`, `just fmt-check`, `just check`,
  with nothing on `PATH` but what the shell put there

It repeats work the main job does, on purpose: what is under test is the shell,
not the checks. A flake that nothing runs stops working within weeks, and the
failure it then produces lands on whoever tried to onboard.

## What this is not

The SDK itself is not built as a nix package. It is published to
[mooncakes.io](https://mooncakes.io/docs/poteto0/endor) and consumed with
`moon add`, so a derivation would be a second distribution channel with no
users. The overlay does provide `buildMoonPackage` if that ever changes.

[overlay]: https://github.com/moonbit-community/moonbit-overlay
[versions]: https://github.com/moonbit-community/moonbit-overlay/tree/master/versions/toolchains
