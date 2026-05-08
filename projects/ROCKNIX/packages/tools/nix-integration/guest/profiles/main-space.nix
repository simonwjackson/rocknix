# Layer 14 main-space profile.
#
# Composes:
#   - base (minimal NixOS container)
#   - tools (CLI utilities for the developer)
#   - ssh (Layer 12 opt-in SSH on port 2222)
#   - display (sway + Mesa freedreno/turnip)
#   - audio (pipewire + wireplumber + bluez + dbus)
#   - network (NetworkManager + nftables firewall, no resolvconf)
#
# Used by THIN_HOST=yes builds via nixosConfigurations.rocknix-guest-main-space
# in flake.nix.
{ lib, ... }:

{
  imports = [
    ../modules/base.nix
    ../modules/tools.nix
    ../modules/ssh.nix
    ../modules/display.nix
    ../modules/audio.nix
    ../modules/network.nix
  ];

  # Layer 14 hostname: distinguish from the Layer 10b minimal "rocknix-guest"
  # so machinectl/journal/etc. show the main-space identity clearly.
  networking.hostName = lib.mkForce "rocknix-nix";

  # Tier E2 surfaced tz-data.service 203/EXEC on every switch because
  # ROCKNIX's tz-data unit ExecStart=/bin/ln -sf /usr/share/zoneinfo/${TIMEZONE}
  # and the variable was empty. Setting time.timeZone declaratively here
  # avoids the noise (NixOS owns its own zoneinfo path).
  time.timeZone = "America/New_York";

  # Stop the rate-limited journal-flush noise that fires when the guest's
  # /run is tmpfs and journald can't pre-allocate.
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=64M
  '';
}
