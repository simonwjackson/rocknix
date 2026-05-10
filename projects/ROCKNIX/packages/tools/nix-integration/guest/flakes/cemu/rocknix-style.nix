{ lib
, baseCemu
}:

# ROCKNIX-style Cemu candidate for Layer 14 build-parity testing.
#
# This intentionally stays a Nix derivation: it does not bind host /usr,
# does not preload the host Vulkan loader, and does not use host Mesa shims.
# It narrows the build-system delta against the ROCKNIX cemu-sa package so
# runtime tests can determine whether the nixpkgs-derived build semantics are
# responsible for the BOTW gameplay slowdown.
baseCemu.overrideAttrs (old: let
  oldCmakeFlags = old.cmakeFlags or [ ];
  oldHardeningDisable = old.hardeningDisable or [ ];
in {
  pname = "cemu-rocknix-style";
  version = "2.999.0-rocknix-style";
  __intentionallyOverridingVersion = true;

  cmakeFlags = oldCmakeFlags ++ [
    "-DENABLE_VCPKG=OFF"
    "-DENABLE_DISCORD_RPC=OFF"
    "-DENABLE_SDL=ON"
    "-DENABLE_CUBEB=ON"
    "-DENABLE_WXWIDGETS=ON"
    "-DENABLE_FERAL_GAMEMODE=OFF"
    "-DENABLE_WAYLAND=ON"
    "-DENABLE_OPENGL=ON"
    "-DENABLE_VULKAN=ON"
    "-DCMAKE_BUILD_TYPE=Release"
  ];

  # ROCKNIX appends -fpch-preprocess and silences GCC 15's
  # -Wchanges-meaning diagnostics. Keep the existing current-guest flag and
  # add the ROCKNIX PCH flag for this candidate.
  env = (old.env or { }) // {
    NIX_CFLAGS_COMPILE = lib.concatStringsSep " " (lib.filter (s: s != "") [
      ((old.env or { }).NIX_CFLAGS_COMPILE or "")
      "-Wno-changes-meaning"
      "-fpch-preprocess"
    ]);
  };

  # The current guest Cemu already disables fortify. Keep PIC intact;
  # disabling PIC would reintroduce the imgui -mcmodel=large problem.
  hardeningDisable = lib.unique (oldHardeningDisable ++ [ "fortify" ]);

  preConfigure = ''
    ${old.preConfigure or ""}

    # Mirror ROCKNIX cemu-sa/package.mk pre_configure_target hooks where
    # they are still applicable on top of the nixpkgs derivation.
    sed -e '/find_package(cubeb)/d' -i CMakeLists.txt || true
    sed -e 's#glm::glm#glm#' -i src/Common/CMakeLists.txt src/input/CMakeLists.txt 2>/dev/null || true
  '';

  passthru = (old.passthru or { }) // {
    rocknixStyle = {
      sourceCommit = "6f6c1299e29fa6e1062ae283a035b4ef787cc397";
      intent = "candidate build that mirrors ROCKNIX cemu-sa CMake flags without host runtime binds";
      knownRemainingDifferences = [
        "Nix toolchain/glibc/library closure"
        "nixpkgs SDL2 may still resolve to sdl2-compat on this nixpkgs pin"
        "Nix wrapper and RPATH/link closure"
        "Nix Mesa/Vulkan runtime unless launch harness selects another coherent guest stack"
      ];
    };
  };

  meta = old.meta // {
    description = "Cemu ROCKNIX-style build-parity candidate for Layer 14 guest testing";
  };
})
