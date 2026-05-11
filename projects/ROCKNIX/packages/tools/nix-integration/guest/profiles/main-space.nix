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
    ../modules/lid.nix
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
    #
    # bashInteractive is required because sway's exec mechanism
    # (both `swaymsg exec` over IPC and `bindsym ... exec ...` keybinds)
    # calls `execlp("sh", "sh", "-c", cmd, NULL)`. Without bash on the
    # unit's PATH that lookup fails with ENOENT and sway logs
    # `[sway/commands/exec_always.c:65] execve failed: No such file or
    # directory` for every exec attempt. The systemd default service
    # PATH on NixOS does not include any shell. Verified live on Thor
    # 2026-05-08: PATH inspection of sway's /proc/<pid>/environ showed
    # only nix store package bin/ dirs, none containing `sh`.
    path = with pkgs; [ dbus foot swaybg swaylock bashInteractive ];

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
      # Session-owned defaults for graphical apps launched via swaymsg exec.
      # Cemu's launcher should not have to manufacture Wayland/audio/XDG
      # basics; those belong to the Layer 14 guest session.
      XDG_RUNTIME_DIR = "/run/user/0";
      WAYLAND_DISPLAY = "wayland-1";
      SDL_AUDIODRIVER = "pulseaudio";
      HOME = "/storage";
      XDG_CONFIG_HOME = "/storage/.config";
      XDG_DATA_HOME = "/storage/.local/share";
      XDG_CACHE_HOME = "/storage/.cache";
      # Temporary Cemu compatibility root for existing ROCKNIX BIOS/keys/MLC
      # state. cemu-storage-adapter.sh consumes this; the package wrapper does
      # not know about ROCKNIX /storage paths.
      CEMU_BIOS_ROOT = "/storage/roms/bios/cemu";
      # Measured SM8550 Cemu affinity policy. Runtime A/B harnesses can set
      # CEMU_AFFINITY_MASK=none to test scheduler behavior explicitly.
      CEMU_AFFINITY_MASK = "0xF8";

      WLR_NO_HARDWARE_CURSORS = "1";
      WLR_LIBINPUT_NO_DEVICES = "1";
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
    output DSI-2 scale 2.0
    output DSI-2 pos 0 0
    output DSI-2 bg #000000 solid_color
    output DSI-2 allow_tearing yes
    output DSI-2 max_render_time off

    # Thor's bottom panel: 1080x1240 native, same physical orientation
    # as DSI-2 (panel is portrait, device is held landscape). transform
    # 90 + scale 2.0 yields 620x540 logical, stacked under DSI-2's
    # 960x540 starting at y=540. Both panels share the device's full
    # physical width but the bottom panel is shorter, so its logical
    # width is narrower.
    output DSI-1 enable
    output DSI-1 transform 90
    output DSI-1 scale 2.0
    output DSI-1 pos 0 540
    output DSI-1 bg #000000 solid_color

    # Touch routing for Thor's dual-screen design.
    #
    # Default: pin all touch sources to the active (top) panel. This
    # is the safe behaviour on kernels that don't yet name the two
    # ft5x06 controllers distinctly -- without it, bottom-panel taps
    # would either be dropped or land on the wrong surface because
    # both controllers report identical libinput identifiers
    # (vendor:product:name = 0:0:generic_ft5x06_(8d)).
    input type:touch map_to_output DSI-2

    # After-patch identifiers (see SM8550 kernel patch
    # 0054-edt-ft5x06-honour-DT-input-name.patch and DT input-name
    # properties on the touchscreen@38 nodes in qcs8550-ayn-thor.dts):
    # the two controllers expose distinct names that sway can address
    # individually, and these per-device rules override the type:touch
    # default above (last-write-wins on map_to_output). On older
    # kernels both rules are no-ops because no input matches them.
    input "0:0:ft5x06-top"    map_to_output DSI-2
    input "0:0:ft5x06-bottom" map_to_output DSI-1
  '';
}
