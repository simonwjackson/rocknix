# ROCKNIX cemu-sa package contract translated for the Layer 14 Nix guest.
#
# Keep this manifest aligned with:
#   projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk
# It is intentionally data-only so static checks and package derivations can
# share the same source/patch/runtime expectations.

{
  pname = "cemu-rocknix-package";
  version = "2.999.0-rocknix-package";

  source = {
    owner = "cemu-project";
    repo = "Cemu";
    rev = "6f6c1299e29fa6e1062ae283a035b4ef787cc397";
    shortRev = "6f6c129";
    hash = "sha256-fl6XRSjizErR7rgdTCPrgMtOjfT5apdWxqDLW0b9fYM=";
    fetchSubmodules = true;
  };

  patches = [
    {
      name = "000-build-fixes.patch";
      file = ./000-build-fixes.patch;
      upstreamPath = "projects/ROCKNIX/packages/emulators/standalone/cemu-sa/patches/000-build-fixes.patch";
    }
    {
      name = "002-opt-seeprom-mlc01-keys-dir.patch";
      file = ./002-opt-seeprom-mlc01-keys-dir.patch;
      upstreamPath = "projects/ROCKNIX/packages/emulators/standalone/cemu-sa/patches/002-opt-seeprom-mlc01-keys-dir.patch";
    }
    {
      name = "003-disable-cmake-interprocedural-optimization.patch";
      file = ./003-disable-cmake-interprocedural-optimization.patch;
      upstreamPath = "projects/ROCKNIX/packages/emulators/standalone/cemu-sa/patches/003-disable-cmake-interprocedural-optimization.patch";
    }
  ];

  # ROCKNIX package.mk pre_configure_target() semantics.
  preConfigureEdits = [
    "delete find_package(cubeb) from CMakeLists.txt to force bundled Cubeb"
    "replace glm::glm with glm in src/Common/CMakeLists.txt and src/input/CMakeLists.txt"
    "append -fpch-preprocess to CXXFLAGS"
    "append -Wno-changes-meaning to CMAKE_CXX_FLAGS"
  ];

  cmakeFlags = [
    "-DENABLE_VCPKG=OFF"
    "-DENABLE_DISCORD_RPC=OFF"
    "-DENABLE_SDL=ON"
    "-DENABLE_CUBEB=ON"
    "-DENABLE_WXWIDGETS=ON"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DENABLE_FERAL_GAMEMODE=OFF"
    "-DENABLE_WAYLAND=ON"
    "-DENABLE_OPENGL=ON"
    "-DENABLE_VULKAN=ON"
  ];

  runtimeData = [
    "share/Cemu/gameProfiles/default"
    "share/Cemu/resources/sharedFonts/CafeCn.ttf"
    "share/Cemu/config/SM8550/settings.xml"
  ];

  expected = {
    bundledCubeb = true;
    noDynamicCubeb = true;
    executableElfType = "EXEC preferred; DYN requires explicit fingerprint explanation";
    buildHost = "fuji or another aarch64 builder, not Thor";
  };

  knownIntentionalNixDeltas = [
    "Nix store output uses $out/share/Cemu instead of ROCKNIX /usr/share/Cemu"
    "Guest launchers provide runtime settings/controller semantics instead of installing host /usr/bin/start_cemu.sh"
    "ROCKNIX Mesa passthrough remains diagnostic-only and is not part of the package closure"
  ];
}
