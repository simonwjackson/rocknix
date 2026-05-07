{ pkgs, ... }:
let
  hello = pkgs.writeShellScript "rocknix-fixture-module-hello" ''
    echo rocknix-fixture-module-hello
  '';
  profile = pkgs.writeText "999-rocknix-fixture-module" ''
    export ROCKNIX_FIXTURE_MODULE=1
  '';
in {
  rocknix.files.bin.rocknix-fixture-module-hello.source = hello;
  rocknix.files.bin.rocknix-fixture-module-hello.mode = "0755";
  rocknix.files.profile."999-rocknix-fixture-module".source = profile;
  rocknix.files.profile."999-rocknix-fixture-module".mode = "0644";
}
