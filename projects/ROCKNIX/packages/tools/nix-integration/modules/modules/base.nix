{ lib, ... }:

{
  options.rocknix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable evaluation of ROCKNIX storage-scoped module output.";
    };
  };
}
