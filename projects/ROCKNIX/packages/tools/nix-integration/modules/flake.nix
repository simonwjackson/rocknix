{
  description = "ROCKNIX storage-scoped declarative module evaluator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      evalRocknix = { system, module }:
        let
          pkgs = import nixpkgs { inherit system; };
        in import ./lib/eval-rocknix.nix {
          inherit pkgs;
          lib = pkgs.lib;
          modules = [ module ];
        };
    in {
      lib = {
        inherit evalRocknix;
      };

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          hostTools = evalRocknix { inherit system; module = ./examples/host-tools.nix; };
          guestSsh = evalRocknix { inherit system; module = ./examples/guest-ssh.nix; };
          bridge = evalRocknix { inherit system; module = ./examples/bridge-nix-version.nix; };
          writeManifest = name: manifest: pkgs.writeText name manifest;
        in {
          example-host-tools-manifest = writeManifest "rocknix-host-tools-module-manifest" hostTools.activationManifest;
          example-guest-ssh-manifest = writeManifest "rocknix-guest-ssh-module-manifest" guestSsh.activationManifest;
          example-bridge-manifest = writeManifest "rocknix-bridge-module-manifest" bridge.activationManifest;
          default = writeManifest "rocknix-empty-module-manifest" "";
        });
    };
}
