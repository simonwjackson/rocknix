{ lib
, baseCemu
, SDL2_classic
}:

# Variant of the ROCKNIX-style candidate that forces classic SDL2 instead of
# nixpkgs' SDL2 -> sdl2-compat (SDL3 shim). This isolates the largest remaining
# runtime-stack mismatch seen in live BOTW runs.
let
  replaceSdl = inputs:
    map (pkg:
      if (pkg.pname or pkg.name or "") == "sdl2-compat"
      then SDL2_classic
      else pkg
    ) inputs;
in
baseCemu.overrideAttrs (old: {
  pname = "cemu-rocknix-style-classic-sdl";
  version = "2.999.0-rocknix-style-classic-sdl";
  __intentionallyOverridingVersion = true;

  nativeBuildInputs = replaceSdl (old.nativeBuildInputs or [ ]);
  buildInputs = replaceSdl (old.buildInputs or [ ]);

  passthru = (old.passthru or { }) // {
    classicSdl = {
      sourceCommit = "6f6c1299e29fa6e1062ae283a035b4ef787cc397";
      intent = "test Cemu with classic SDL2 instead of sdl2-compat/SDL3";
      replacedInput = "sdl2-compat";
      replacement = SDL2_classic.name;
    };
  };

  meta = old.meta // {
    description = "Cemu ROCKNIX-style Layer 14 candidate using classic SDL2";
  };
})
