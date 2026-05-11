{
  description = "ROCKNIX build environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkRocknixBuildInputs = pkgs:
        let
          perlWithModules = pkgs.perl.withPackages (ps: with ps; [
            JSON
            ParseYapp
            XMLParser
          ]);
        in with pkgs; [
          # Core build tools checked by scripts/checkdeps
          bashInteractive
          bc
          bzip2
          curl
          diffutils
          file
          gawk
          # NOTE: this FHS env is NOT what runs the actual cold-start
          # build. `scripts/local-image-build` invokes CI's ubuntu:jammy
          # container instead, because every nixpkgs gcc breaks a
          # different host-phase package against the rocknix package set:
          #   gcc-13.4: sed-4.9 (no <stdckdint.h>, gnulib needs it)
          #   gcc-14.3: sed-4.9 (acl.h uses bool with no <stdbool.h>)
          #   gcc-15.2: ncurses-6.5 (NCURSES_BOOL=unsigned char vs
          #                          libstdc++-15 distinct-bool traits)
          # CI uses ubuntu:jammy with the default `gcc` package =
          # gcc-11.4, and rocknix is only validated against that. We
          # pin gcc-14 here purely so this FHS env is still usable for
          # ad-hoc inspection (running scripts/build_distro by hand,
          # running tests under projects/.../tests/, etc.); the actual
          # build path now goes through podman + ./Dockerfile.
          gcc14
          gnumake
          gnupatch
          gperf
          gzip
          lzop
          patchutils
          perlWithModules
          rdfind
          rsync
          gnused
          gnutar
          unzip
          wget
          xmlstarlet
          xz
          zip
          zstd

          # Extra tools commonly needed by the ROCKNIX build scripts
          binutils
          cacert
          cpio
          coreutils
          findutils
          git
          jdk_headless
          libxslt
          ncurses.dev
          glibc.dev
          python3
          rpcsvc-proto
          which

          # Font tools checked on Linux hosts
          bdftopcf
          mkfontdir
          mkfontscale
        ];
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          rocknixBuildInputs = mkRocknixBuildInputs pkgs;
        in {
          default = self.packages.${system}.rocknix-env;

          rocknix-env = pkgs.buildFHSEnv {
            name = "rocknix-env";
            targetPkgs = _: rocknixBuildInputs;
            runScript = "bash";
            # Some NixOS systems have automount-style /net trees that bubblewrap
            # cannot reliably re-bind. ROCKNIX builds do not need /net.
            extraPreBwrapCmds = ''
              ignored+=(/net)
            '';
            # ROCKNIX's checkdeps wants /nix itself to be writable. Keep the
            # host store visible for Nix-provided tools, but make /nix a
            # writable tmpfs inside the FHS shell.
            extraBwrapArgs = [
              "--tmpfs" "/nix"
              "--ro-bind" "/nix/store" "/nix/store"
            ];
            profile = ''
              export PROJECT="''${PROJECT:-ROCKNIX}"
              export ARCH="''${ARCH:-aarch64}"
              export LC_ALL="''${LC_ALL:-C.UTF-8}"
            '';
          };
        });

      apps = forAllSystems (system: {
        default = self.apps.${system}.rocknix-env;
        rocknix-env = {
          type = "app";
          program = "${self.packages.${system}.rocknix-env}/bin/rocknix-env";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          rocknixBuildInputs = mkRocknixBuildInputs pkgs;
        in {
          default = pkgs.mkShell {
            packages = rocknixBuildInputs ++ [ self.packages.${system}.rocknix-env ];
            shellHook = ''
              echo "ROCKNIX build tools are on PATH."
              echo "For full /usr/include compatibility, run: rocknix-env"
              echo "Then build, for example: DEVICE=SM8550 make image"
            '';
          };
        });
    };
}
