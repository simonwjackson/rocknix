{ lib, ... }:

let
  fileSpec = lib.types.submodule {
    options = {
      source = lib.mkOption {
        type = lib.types.path;
        description = "Store path or local file copied into a storage-owned surface.";
      };
      mode = lib.mkOption {
        type = lib.types.strMatching "[0-7][0-7][0-7][0-7]";
        default = "0755";
        description = "File mode for the activated storage target.";
      };
    };
  };
in {
  options.rocknix.files = {
    bin = lib.mkOption {
      type = lib.types.attrsOf fileSpec;
      default = { };
      description = "Files activated under /storage/bin.";
    };
    profile = lib.mkOption {
      type = lib.types.attrsOf fileSpec;
      default = { };
      description = "Files activated under /storage/.config/profile.d.";
    };
  };
}
