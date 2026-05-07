{ lib, pkgs, ... }:

{
  boot.isContainer = true;

  networking.hostName = "rocknix-guest";
  networking.useDHCP = false;

  services.openssh = {
    enable = true;
    ports = [ 2222 ];
    authorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  environment.etc."ssh/authorized_keys.d/root".text = "";

  users.mutableUsers = true;
  users.users.root.hashedPassword = "!";

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
