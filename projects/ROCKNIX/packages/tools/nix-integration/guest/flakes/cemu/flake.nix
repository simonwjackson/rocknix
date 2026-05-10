{
  description = "cemu (Wii U emulator) with aarch64 dynarec backend, pinned to ROCKNIX commit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # nixos-unstable aliases SDL2 to sdl2-compat (SDL3 shim). Keep an
  # older nixpkgs input solely for a diagnostic classic-SDL2 Cemu build.
  inputs.nixpkgs-sdl2-classic.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs, nixpkgs-sdl2-classic }: let
    forAllSystems = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f system);
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pkgsSdl2Classic = nixpkgs-sdl2-classic.legacyPackages.${system};
      cemu = (pkgs.cemu.override {
        wxwidgets_3_2 = pkgs.wxwidgets_3_3;
        # Newer cemu uses fmt::format_string::get() (fmt >= 10).
        fmt_9 = pkgs.fmt_11;
      }).overrideAttrs (old: {
        # ROCKNIX-pinned commit (2026-04-22) -- has BackendAArch64
        # Keep the version string in MAJOR.MINOR form so the upstream
        # preConfigure's version parser is happy.
        version = "2.999.0";
        src = pkgs.fetchFromGitHub {
          owner = "cemu-project";
          repo = "Cemu";
          rev = "6f6c1299e29fa6e1062ae283a035b4ef787cc397";
          # Submodules required: xbyak_aarch64 (AArch64 JIT helper),
          # ZArchive, cubeb, Vulkan-Headers, imgui, metal-cpp.
          fetchSubmodules = true;
          hash = "sha256-fl6XRSjizErR7rgdTCPrgMtOjfT5apdWxqDLW0b9fYM=";
        };
        # ROCKNIX's vendored aarch64 build fixes:
        #   - NEON intrinsic types (vreinterpretq_u8_u16/_u32 wrappers)
        #   - explicit OpenSSL link for CemuBin
        #   - sharpyuv link in wxgui
        #   - -mcmodel=large for imgui on aarch64
        # Plus ROCKNIX's Cemu user-data layout patch and disabling LTO/IPO
        # (cemu's IPO doesn't work cleanly with our toolchain).
        patches = [
          ./000-build-fixes.patch
          ./002-opt-seeprom-mlc01-keys-dir.patch
          ./003-disable-cmake-interprocedural-optimization.patch
          # nixpkgs SDL2 is sdl2-compat (SDL3 shim); SDL3's video-init
          # path crashes on aarch64 inside cemu's ScreenSaver::SetInhibit
          # on first ROM load. Bypass the call on Linux, mirroring
          # cemu's existing macOS workaround.
          ./004-screensaver-noop-linux.patch
        ];
        # Need libwebp's sharpyuv added to inputs (referenced by build-fixes patch).
        buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.libwebp ];
        # Cemu's BackendAArch64.cpp declares fields with the same name as
        # xbyak_aarch64 classes (VReg, QReg, ...). GCC 15 makes
        # -Wchanges-meaning an error by default. ROCKNIX silences it.
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE = "-Wno-changes-meaning";
        };
        # Don't replace the bundled imgui submodule with nixpkgs' pinned
        # imgui-1.91.3: that one already removed ImGuiIO::ImeWindowHandle
        # which this cemu commit still references in src/imgui/imgui_extension.cpp.
        # The submodule we fetched is the version cemu actually targets.
        preConfigure = ''
          substituteInPlace CMakeLists.txt \
            --replace-fail "EMULATOR_VERSION_MAJOR \"0\"" "EMULATOR_VERSION_MAJOR \"2\"" || true
          substituteInPlace CMakeLists.txt \
            --replace-fail "EMULATOR_VERSION_MINOR \"0\"" "EMULATOR_VERSION_MINOR \"999\"" || true
          substituteInPlace dependencies/gamemode/lib/gamemode_client.h \
            --replace-fail "libgamemode.so.0" "${pkgs.gamemode.lib}/lib/libgamemode.so.0" || true
          # ROCKNIX patch adds -mcmodel=large for aarch64 imgui, but that's
          # incompatible with -fPIC (NixOS' default hardening). Drop it: with
          # IPO/LTO disabled by the other patch, the small code model is fine.
          substituteInPlace src/imgui/CMakeLists.txt \
            --replace-fail "target_compile_options(imguiImpl PRIVATE -mcmodel=large)" \
              "# -mcmodel=large incompatible with -fPIC; dropped" || true
        '';
        # Install the same runtime data directories that ROCKNIX cemu-sa
        # copies from the build tree to /usr/share/Cemu. Without these, BOTW
        # logs `gameprofile path: (not present)` and the shared Cafe fonts are
        # missing, which is not a faithful ROCKNIX Cemu runtime.
        postInstall = (old.postInstall or "") + ''
          cemuDataDir="$out/share/Cemu"
          mkdir -p "$cemuDataDir"

          for dataDirName in gameProfiles resources; do
            dataDir=""
            for candidate in \
              "$PWD/bin/$dataDirName" \
              "$PWD/../bin/$dataDirName" \
              "$PWD/../../source/bin/$dataDirName" \
              "$NIX_BUILD_TOP/$sourceRoot/bin/$dataDirName"
            do
              if [ -d "$candidate" ]; then
                dataDir="$candidate"
                break
              fi
            done

            if [ -z "$dataDir" ]; then
              dataDir=$(find "$PWD" -path "*/bin/$dataDirName" -type d -print -quit 2>/dev/null || true)
            fi

            if [ -z "$dataDir" ]; then
              echo "error: Cemu runtime data directory not found: $dataDirName" >&2
              exit 1
            fi

            rm -rf "$cemuDataDir/$dataDirName"
            cp -r "$dataDir" "$cemuDataDir/"
          done
        '';

        # NixOS' default 'pic' hardening flag enforces -fPIC; keep it but
        # disable 'fortify' which sometimes interacts badly with PCH builds.
        hardeningDisable = (old.hardeningDisable or [ ]) ++ [ "fortify" ];
        # Allow building/running on aarch64-linux
        meta = old.meta // {
          platforms = [ "x86_64-linux" "aarch64-linux" ];
        };
      });
      cemuRocknixStyle = pkgs.callPackage ./rocknix-style.nix {
        baseCemu = cemu;
      };
      cemuRocknixStyleClassicSdl = pkgs.callPackage ./rocknix-style-classic-sdl.nix {
        baseCemu = cemuRocknixStyle;
        SDL2_classic = pkgsSdl2Classic.SDL2;
      };
      cemuRocknixFaithful = pkgs.callPackage ./rocknix-faithful.nix {
        baseCemu = cemuRocknixStyleClassicSdl;
      };
      cemuRocknixPackage = pkgs.callPackage ./rocknix-package.nix {
        SDL2_classic = pkgsSdl2Classic.SDL2;
      };
    in {
      default = self.packages.${system}.cemu;
      inherit cemu;
      "cemu-rocknix-style" = cemuRocknixStyle;
      "cemu-rocknix-style-classic-sdl" = cemuRocknixStyleClassicSdl;
      "cemu-rocknix-faithful" = cemuRocknixFaithful;
      "cemu-rocknix-package" = cemuRocknixPackage;
    });
  };
}
