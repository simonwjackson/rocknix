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
{ lib, pkgs, ... }:

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

  # Layer 14 first-light autostart wiring (Thor validation 2026-05-08).
  #
  # We do NOT use services.greetd: greetd's PAM stack pulls in
  # pam_systemd.so which fails to dlopen inside nspawn ("failed to map
  # segment from shared object") because nspawn's seccomp/capability
  # profile blocks the mmap pattern PAM modules use. greetd then exits
  # cleanly but never spawns a session.
  #
  # Instead, ship a bare systemd service that runs sway directly.
  # wlroots's seatd backend (built into sway) takes /dev/dri/card0 and
  # /dev/tty1 master without needing PAM or logind sessions.
  #
  # Why no TTYPath / StandardInput=tty / PAMName: live validation on Thor
  # 2026-05-08 showed that the moment systemd is asked to claim a TTY for
  # the unit it tries to run a PAM auth pre-exec step that fails silently
  # inside nspawn (no logind, no pam_systemd) and the unit exits 127
  # before sway is even reached. wlroots's libseat backend acquires its
  # own VT directly from /dev/tty0 / /dev/tty1 (which the host nspawn
  # unit binds in) when sway initialises the DRM session, so there is no
  # need to hand the unit a TTY explicitly.
  systemd.services.rocknix-sway-kiosk = {
    description = "ROCKNIX Layer 14 sway kiosk session";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" "systemd-user-sessions.service" ];

    # sway's wrapper invokes dbus-run-session which spawns dbus-daemon.
    # Without dbus on the unit's PATH the wrapper fails with
    # "dbus-run-session: failed to execute message bus daemon
    # 'dbus-daemon': No such file or directory" before sway is reached.
    #
    # Sway client commands (foot, swaybg, swaylock) inherit sway's PATH;
    # add them here so `swaymsg exec foot` works without requiring the
    # caller to set absolute paths.
    path = with pkgs; [ dbus foot swaybg swaylock ];

    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 -o 0 -g 0 /run/user/0";
      ExecStart = "${pkgs.sway}/bin/sway -c /etc/sway/config";
      Restart = "on-failure";
      RestartSec = 3;
      StandardOutput = "journal";
      StandardError = "journal";
    };
    environment = {
      XDG_RUNTIME_DIR = "/run/user/0";
      WLR_NO_HARDWARE_CURSORS = "1";
      WLR_LIBINPUT_NO_DEVICES = "1";
      HOME = "/root";
      USER = "root";
    };
  };

  # Bake a Thor-aware sway config into /etc. Mirrors legacy ROCKNIX's
  # /storage/.config/sway/config so the panels render correctly on the
  # AYN Thor: DSI-2 is the main 1080x1920 panel (held landscape, panel
  # is physically portrait, so transform 90), DSI-1 is the smaller
  # 1080x1240 secondary panel which we leave disabled in main-space
  # for now (kept for future dual-screen apps).
  environment.etc."sway/config".text = ''
    # ROCKNIX Layer 14 sway config (Thor / SM8550).
    # Validated on Thor 2026-05-08: foot terminal renders readably in
    # landscape orientation on DSI-2 with these transforms.
    seat * hide_cursor 1000
    default_border none

    output DSI-2 transform 90
    output DSI-2 bg #000000 solid_color
    output DSI-2 allow_tearing yes
    output DSI-2 max_render_time off

    output DSI-1 disable

    # Both Thor touchscreens currently report identical libinput
    # identifiers (vendor:product:name = 0:0:generic_ft5x06_(8d))
    # because the ft5x06 driver doesn't synthesise distinct names per
    # i2c instance. sway 1.11 has no path-based input identifier syntax,
    # so we cannot per-device map them. Coarse workaround: pin all touch
    # input to DSI-2 (the active panel). Bottom-panel taps still produce
    # libinput events but are silently dropped at the wlroots routing
    # stage instead of landing on the wrong surface.
    #
    # See docs/brainstorms/2026-05-08-001-rocknix-thor-multi-touchscreen-routing.md
    # for the proper kernel-patch + DT fix.
    input type:touch map_to_output DSI-2
  '';
}
