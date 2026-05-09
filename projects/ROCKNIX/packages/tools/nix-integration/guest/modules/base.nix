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

  # Disable build sandboxing inside the guest: systemd-nspawn does not
  # expose the kernel namespaces (CLONE_NEWUSER + CLONE_NEWNS in the
  # right combo) that nix's sandboxed-builds path requires. With sandbox
  # on, every `nixos-rebuild switch` from inside the guest aborts with
  # "this system does not support the kernel namespaces that are
  # required for sandboxing; use --no-sandbox to disable sandboxing."
  #
  # Validated on Thor 2026-05-08: sandbox=true -> rebuild aborts before
  # the activation step; sandbox=false -> rebuild completes, including
  # building the system closure derivation.
  nix.settings.sandbox = false;

  system.stateVersion = "25.11";
}
