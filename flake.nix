{
  description = "endor.mbt — development environment (MoonBit, just, Node, Anvil)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # MoonBit is not in nixpkgs: the compiler upstream open-sourced only builds
    # the wasm-gc backend, and this SDK pins `js`. So the toolchain comes from
    # the community overlay of the *official binaries* — the same tarballs
    # `cli.moonbitlang.com/install/unix.sh` unpacks, patchelf'd for nix.
    moonbit-overlay = {
      url = "github:moonbit-community/moonbit-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      # it formats itself with treefmt too; one copy in the lock file is enough
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      moonbit-overlay,
      treefmt-nix,
    }:
    let
      # The toolchain CI installs, in the overlay's spelling: upstream's
      # `0.10.6+80dc50f24` plus the revision of `core` that release ships with,
      # which is the overlay's own coordinate and has no counterpart in
      # `.github/actions/setup`. `just nix-pin-check` compares everything up to
      # that last `+` against `MOONBIT_INSTALL_VERSION` there, so the two
      # pins cannot drift apart silently — which is the whole point of pinning
      # (#76): a nightly release that changes `moon fmt` or `moon info` output
      # must not reach a developer before it reaches CI, or the other way
      # around.
      moonbitVersion = "0.10.6+80dc50f24+c19f78e";

      # `v0.10.6+80dc50f24+c19f78e` is not an attribute name; the overlay
      # escapes it. See its README.
      moonbitAttr = builtins.replaceStrings [ "." "+" ] [ "_" "-" ] "v${moonbitVersion}";

      # what the overlay publishes binaries for at this version. There is no
      # `aarch64-linux` MoonBit release to mirror, and the pinned version has no
      # `x86_64-darwin` tarball either — listing a system whose toolchain
      # cannot be fetched would trade a clear "no such system" for a download
      # that fails halfway.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # `f` is called with the system and its nixpkgs, so an output that has to
      # name the system (`checks`, which reads `treefmtEval`) does not have to
      # dig it back out of `pkgs`.
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f system (
            import nixpkgs {
              inherit system;
              overlays = [ moonbit-overlay.overlays.default ];
            }
          )
        );

      treefmtEval = forAllSystems (_system: pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);
    in
    {
      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            name = "endor";

            packages = [
              # `moon`, `moonc` and the bundled `core`. The overlay wraps `moon`
              # with MOON_TOOLCHAIN_ROOT rather than MOON_HOME, so `~/.moon` stays
              # writable and `moon update` / `moon add` still work from inside the
              # shell — the registry checkout is not part of this closure.
              pkgs.moonbit-bin.moonbit.${moonbitAttr}

              pkgs.just

              # `moon test --target js` runs the generated JS under node, and the
              # documentation site is npm. Same major version CI installs.
              pkgs.nodejs_22

              # `anvil`, for `just anvil` + `just e2e`. `forge` and `cast` come
              # with it; nothing here uses them.
              pkgs.foundry

              # `just docs-dev` and `just example` serve over `http.server`
              pkgs.python3

              # `just archive-check` and `docs-check` are bash + coreutils, and
              # `require-node` polls the RPC endpoint with curl
              pkgs.curl

              # `nix fmt` without the flake — same binary, same config
              treefmtEval.${system}.config.build.wrapper
            ];

            shellHook = ''
              echo "endor.mbt: $(moon version) · just $(just --version | cut -d' ' -f2) · node $(node --version)"
              echo "  first time here: \`moon update\` (fills ~/.moon's registry), then \`just ci-check\`"
            '';
          };
        }
      );

      # `nix fmt`. Everything but `.mbt`, which is `moon fmt` (`just fmt`) —
      # see treefmt.nix.
      formatter = forAllSystems (system: _pkgs: treefmtEval.${system}.config.build.wrapper);

      checks = forAllSystems (
        system: pkgs: {
          formatting = treefmtEval.${system}.config.build.check self;

          # that the shell's PATH really carries what the justfile calls. The
          # closure is built by `nix flake check` reaching this; running the
          # binaries is what catches an overlay that resolved but cannot exec.
          devShell-tools =
            pkgs.runCommand "endor-devshell-tools"
              {
                nativeBuildInputs = self.devShells.${system}.default.nativeBuildInputs;
              }
              ''
                export HOME=$TMPDIR
                moon version --all
                just --version
                node --version
                anvil --version
                python3 --version
                touch $out
              '';
        }
      );
    };
}
