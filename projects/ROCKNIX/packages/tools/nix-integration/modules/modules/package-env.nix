{ lib, ... }:

{
  options.rocknix.packageEnvs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        wrapper = lib.mkOption {
          type = lib.types.path;
          description = "Executable wrapper built by Nix and activated under /storage/bin.";
        };
      };
    });
    default = { };
    description = "Named package-like environments exposed as storage-local wrappers.";
  };
}
