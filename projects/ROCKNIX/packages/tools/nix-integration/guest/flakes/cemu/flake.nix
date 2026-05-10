{
  description = "ROCKNIX Cemu package replica for Layer 14 Nix guest";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # ROCKNIX Cemu is built against classic SDL2. nixos-unstable aliases SDL2 to
  # sdl2-compat, so keep a narrow 24.11 input only for that build input.
  inputs.nixpkgs-sdl2-classic.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs, nixpkgs-sdl2-classic }: let
    forAllSystems = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f system);
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pkgsSdl2Classic = nixpkgs-sdl2-classic.legacyPackages.${system};
      cemuRocknixPackage = pkgs.callPackage ./rocknix-package.nix {
        SDL2_classic = pkgsSdl2Classic.SDL2;
      };
    in {
      default = cemuRocknixPackage;
      "cemu-rocknix-package" = cemuRocknixPackage;
    });
  };
}
