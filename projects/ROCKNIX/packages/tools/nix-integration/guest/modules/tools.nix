{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    bashInteractive
    coreutils
    procps
    util-linux
  ];
}
