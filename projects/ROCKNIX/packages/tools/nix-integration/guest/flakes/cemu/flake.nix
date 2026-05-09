{
  description = "cemu (Wii U emulator) with aarch64 dynarec backend, pinned to ROCKNIX commit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: let
    forAllSystems = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f system);
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = self.packages.${system}.cemu;
      # Newer cemu requires wxWidgets >= 3.3; nixpkgs cemu uses 3_2.
      # Override wxwidgets first so we can swap in 3_3 below.
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
        # Plus disabling LTO/IPO (cemu's IPO doesn't work cleanly with our toolchain).
        patches = [
          ./000-build-fixes.patch
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
        # NixOS' default 'pic' hardening flag enforces -fPIC; keep it but
        # disable 'fortify' which sometimes interacts badly with PCH builds.
        hardeningDisable = (old.hardeningDisable or [ ]) ++ [ "fortify" ];
        # Allow building/running on aarch64-linux
        meta = old.meta // {
          platforms = [ "x86_64-linux" "aarch64-linux" ];
        };
      });
    });
  };
}
