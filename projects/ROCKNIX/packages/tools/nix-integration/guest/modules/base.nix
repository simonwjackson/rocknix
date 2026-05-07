{ lib, pkgs, ... }:

{
  boot.isContainer = true;

  networking.hostName = "rocknix-guest";
  networking.useDHCP = false;

  environment.systemPackages = with pkgs; [
    bashInteractive
    coreutils
    procps
    util-linux
  ];

  systemd.services."getty@tty1".enable = lib.mkForce false;
  systemd.services."serial-getty@hvc0".enable = lib.mkForce false;
  systemd.services."serial-getty@ttyS0".enable = lib.mkForce false;

  documentation.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc.automatic = false;

  system.stateVersion = "25.11";
}
