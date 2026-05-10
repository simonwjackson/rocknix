{ lib
, baseCemu
}:

# Faithful ROCKNIX cemu-sa replication candidate for Layer 14 guest testing.
#
# This is intentionally a stricter candidate than `cemu-rocknix-style`:
# it starts from the ROCKNIX-style + classic-SDL candidate, removes the
# nixpkgs Cubeb input so Cemu must use its bundled submodule like ROCKNIX,
# and disables PIE for the executable link to test the host-observed
# `Type: EXEC` posture. Existing diagnostic candidates remain available so
# build/link regressions are isolated to this output.
baseCemu.overrideAttrs (old: let
  oldCmakeFlags = old.cmakeFlags or [ ];
  oldHardeningDisable = old.hardeningDisable or [ ];
  oldEnv = old.env or { };
  isCubeb = pkg: lib.getName pkg == "cubeb";
  withoutCubeb = inputs: lib.filter (pkg: !(isCubeb pkg)) inputs;
in {
  pname = "cemu-rocknix-faithful";
  version = "2.999.0-rocknix-faithful";
  __intentionallyOverridingVersion = true;

  nativeBuildInputs = withoutCubeb (old.nativeBuildInputs or [ ]);
  buildInputs = withoutCubeb (old.buildInputs or [ ]);

  cmakeFlags = oldCmakeFlags ++ [
    # Characterization gate: ROCKNIX host /usr/bin/cemu fingerprints as an
    # ELF EXEC binary while the nixpkgs wrapper target has been PIE/DYN. Keep
    # this scoped to executable links so shared-library builds are unaffected.
    "-DCMAKE_EXE_LINKER_FLAGS=-no-pie"
  ];

  env = oldEnv // {
    NIX_CFLAGS_COMPILE = lib.concatStringsSep " " (lib.filter (s: s != "") [
      (oldEnv.NIX_CFLAGS_COMPILE or "")
      "-Wno-changes-meaning"
      "-fpch-preprocess"
    ]);
    NIX_LDFLAGS = lib.concatStringsSep " " (lib.filter (s: s != "") [
      (oldEnv.NIX_LDFLAGS or "")
      "-no-pie"
    ]);
  };

  # Keep PIC enabled: Cemu still builds shared/object-library components under
  # Nix, and disabling PIC would re-open the imgui/aarch64 -mcmodel=large issue
  # handled in the base output. This nixpkgs hardening set does not expose a
  # separate `pie` flag, so non-PIE is tested through executable linker flags.
  hardeningDisable = lib.unique (oldHardeningDisable ++ [ "fortify" ]);

  preConfigure = ''
    ${old.preConfigure or ""}

    # Reassert the ROCKNIX cemu-sa pre_configure hooks after all inherited
    # substitutions. The important distinction here is that `cubeb` is also
    # removed from Nix inputs above, so deleting find_package(cubeb) forces the
    # bundled submodule path instead of accidentally finding nixpkgs Cubeb.
    sed -e '/find_package(cubeb)/d' -i CMakeLists.txt || true
    sed -e 's#glm::glm#glm#' -i src/Common/CMakeLists.txt src/input/CMakeLists.txt 2>/dev/null || true
  '';

  postInstall = (old.postInstall or "") + ''
    # Build-time parity assertions: do not publish a candidate that cannot
    # find the runtime data ROCKNIX installs under /usr/share/Cemu.
    test -f "$out/share/Cemu/gameProfiles/default/00050000101c9400.ini" || {
      echo "error: BOTW game profile missing from faithful Cemu output" >&2
      exit 1
    }
    test -f "$out/share/Cemu/resources/sharedFonts/CafeCn.ttf" || {
      echo "error: CafeCn.ttf shared font missing from faithful Cemu output" >&2
      exit 1
    }
  '';

  passthru = (old.passthru or { }) // {
    rocknixFaithful = {
      sourceCommit = "6f6c1299e29fa6e1062ae283a035b4ef787cc397";
      intent = "strict ROCKNIX cemu-sa parity candidate: classic SDL2, bundled Cubeb, non-PIE executable posture, installed runtime data";
      expectedFingerprint = {
        runtimeData = [
          "share/Cemu/gameProfiles/default/00050000101c9400.ini"
          "share/Cemu/resources/sharedFonts/CafeCn.ttf"
        ];
        noDynamicCubeb = true;
        executableElfType = "EXEC preferred; DYN is a parity failure unless documented by fingerprint";
      };
      knownRemainingDifferences = [
        "Nix toolchain/glibc/library closure"
        "Nix wrapper/RPATH behavior around the real .Cemu-wrapped binary"
        "Nix Mesa/Vulkan runtime unless launch harness selects a coherent diagnostic graphics stack"
      ];
    };
  };

  meta = old.meta // {
    description = "Cemu ROCKNIX-faithful cemu-sa parity candidate for Layer 14 guest testing";
  };
})
