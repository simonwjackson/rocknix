{ lib, ... }:

{
  options.rocknix.bridges = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        command = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Command executed inside the guest by the Layer 11 bridge.";
        };
      };
    });
    default = { };
    description = "Layer 11 one-shot guest-backed bridge declarations.";
  };
}
