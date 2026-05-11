{ lib, ... }:

{
  options.rocknix.guest.ssh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Configure Layer 12 guest SSH metadata.";
    };
    port = lib.mkOption {
      type = lib.types.ints.between 1024 65535;
      default = 2222;
      description = "Fixed validated Layer 12 SSH port. First implementation supports only 2222 at apply time.";
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.str;
      default = "/storage/.ssh/authorized_keys";
      description = "Operator-provided authorized_keys file for guest root SSH.";
    };
  };
}
