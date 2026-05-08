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
          # Pin gcc-14. nixpkgs-unstable's default gcc is gcc-15, which
          # breaks ncurses-6.5's C++ bindings (NCURSES_BOOL=unsigned char
          # vs libstdc++-15's distinct-bool type traits). gcc-13 was
          # tried first but lacks the C23 <stdckdint.h> header that
          # sed-4.9's gnulib unconditionally includes when GCC >= 10.1.
          # gcc-14.3 ships <stdckdint.h> and has libstdc++-14 (no
          # ncurses ABI clash). gcc-11/12 are removed from nixpkgs.
          # CI uses ubuntu:jammy with gcc-11 and somehow works around
          # the stdckdint issue (likely via a libc-supplied freestanding
          # header) but reproducing that path locally is more invasive
          # than just bumping our toolchain a little.
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
