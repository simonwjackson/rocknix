{ ... }:

let
  hello = builtins.toFile "rocknix-module-hello" ''
    #!/bin/sh
    echo rocknix-module-hello
  '';
  profile = builtins.toFile "999-rocknix-module-example" ''
    export ROCKNIX_MODULE_EXAMPLE=1
  '';
in {
  rocknix.files.bin.rocknix-module-hello = {
    source = hello;
    mode = "0755";
  };

  rocknix.files.profile."999-rocknix-module-example" = {
    source = profile;
    mode = "0644";
  };
}
