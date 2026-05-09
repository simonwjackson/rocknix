# Layer 14 lid-switch handler -- "fake suspend" for AYN Thor.
#
# Real PM_SUSPEND is disabled on SM8550 by the ROCKNIX 030-suspend_mode
# quirk (`suspendmode off`). The host's input_sense + rocknix-fake-suspend
# pipeline doesn't apply in Layer 14 main-space mode because the ROCKNIX
# userland is dormant -- ES, host inputsense, host audio services are
# all stopped. This module replaces that pipeline with a guest-native
# version that targets every battery-draining knob reachable from inside
# the nspawn.
#
# Knob reachability (verified 2026-05-08 on Thor):
#   reachable + writable: cpufreq governor (policy0/3/7), nmcli radio,
#                         rfkill, bluetoothctl, swaymsg DPMS, pipewire
#                         systemd units (when audio.nix runs them).
#   reachable RO only:    backlight brightness, cpu hotplug (online).
#                         These are skipped; DPMS off the displays
#                         turns the panels off via DRM, which is
#                         equivalent for battery purposes.
#
# Lid close pipeline (each step independent, errors swallowed so
# downstream steps still run):
#   1. Snapshot governors + nmcli wifi state + rfkill bluetooth state
#      to /run/rocknix-lid/ so lid-open can restore.
#   2. swaymsg 'output * power off' on both DSI panels.
#   3. systemctl stop pipewire / wireplumber if active (releases the
#      audio DSP path; safe no-op if audio.nix isn't running yet).
#   4. nmcli radio wifi off  -- WILL DISCONNECT ACTIVE SSH. If you need
#      SSH to survive lid-cycle testing, touch the master kill switch:
#        touch /storage/.config/rocknix/lid-suspend.disabled
#      The whole handler is then a no-op until that file is removed.
#   5. rfkill block bluetooth.
#   6. echo powersave > scaling_governor  for every cpufreq policy.
#
# Lid open: reverse in opposite order, restoring snapshotted state from
# /run/rocknix-lid/. swaymsg 'output * power on' last so the screen
# wakes after the radios are back.
{ pkgs, lib, ... }:

let
  # Kill switch lives in /storage/.guest/ which is bind-mounted RW from
  # the host (per rocknix-guest-v2.service). This is the ONLY part of
  # /storage that's shared across the host/guest boundary -- /storage
  # in the guest is otherwise the guest rootfs's own /storage, not the
  # host's. So putting the kill switch here means you can disable the
  # handler from a host SSH session even when the guest is unreachable.
  #
  # To disable:  ssh root@thor 'touch /storage/.guest/lid-suspend.disabled'
  # To re-enable: ssh root@thor 'rm /storage/.guest/lid-suspend.disabled'
  killSwitch = "/storage/.guest/lid-suspend.disabled";
  stateDir = "/run/rocknix-lid";

  lidClose = pkgs.writeShellScript "rocknix-lid-close" ''
    set -u
    export PATH=${lib.makeBinPath (with pkgs; [
      sway
      coreutils
      gnused
      gnugrep
      networkmanager
      util-linux
      systemd
    ])}

    if [ -e "${killSwitch}" ]; then
      echo "lid-close: kill switch present (${killSwitch}); skipping" >&2
      exit 0
    fi

    mkdir -p "${stateDir}"
    log="${stateDir}/log"

    # ---- 1. snapshot pre-close state ----
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -d "$p" ] || continue
      cp "$p/scaling_governor" "${stateDir}/$(basename "$p").governor" 2>/dev/null || true
    done
    nmcli -t -f WIFI radio 2>/dev/null | head -1 > "${stateDir}/wifi.state" || true
    rfkill list bluetooth 2>/dev/null > "${stateDir}/bt.state" || true
    if systemctl --quiet is-active pipewire.service 2>/dev/null; then
      echo active > "${stateDir}/pipewire.state"
    fi

    # ---- 2. DPMS off both panels via sway IPC ----
    SOCK=$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1)
    if [ -n "$SOCK" ]; then
      SWAYSOCK="$SOCK" swaymsg 'output * power off' >/dev/null 2>&1 || true
    fi

    # ---- 3. stop audio if running ----
    if [ -f "${stateDir}/pipewire.state" ]; then
      systemctl stop pipewire.service wireplumber.service 2>/dev/null || true
    fi

    # ---- 4. Wi-Fi off (kills SSH if you're connected -- by design) ----
    nmcli radio wifi off 2>/dev/null || true

    # ---- 5. Bluetooth off ----
    /run/wrappers/bin/rfkill block bluetooth 2>/dev/null \
      || rfkill block bluetooth 2>/dev/null || true

    # ---- 6. CPU governors -> powersave ----
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -d "$p" ] || continue
      if [ -w "$p/scaling_governor" ]; then
        echo powersave > "$p/scaling_governor" 2>/dev/null || true
      fi
    done

    echo "$(date -Is) lid-close: completed" >> "$log"
  '';

  lidOpen = pkgs.writeShellScript "rocknix-lid-open" ''
    set -u
    export PATH=${lib.makeBinPath (with pkgs; [
      sway
      coreutils
      gnused
      gnugrep
      networkmanager
      util-linux
      systemd
    ])}

    if [ -e "${killSwitch}" ]; then
      echo "lid-open: kill switch present; skipping" >&2
      exit 0
    fi

    log="${stateDir}/log"

    # ---- 1. CPU governors restore ----
    for f in "${stateDir}"/policy*.governor; do
      [ -f "$f" ] || continue
      gov=$(cat "$f")
      pol=$(basename "$f" .governor)
      if [ -w "/sys/devices/system/cpu/cpufreq/$pol/scaling_governor" ]; then
        echo "$gov" > "/sys/devices/system/cpu/cpufreq/$pol/scaling_governor" 2>/dev/null || true
      fi
    done

    # ---- 2. Bluetooth restore -- only unblock if it was unblocked before ----
    if [ -f "${stateDir}/bt.state" ] && \
        ! grep -q 'Soft blocked: yes' "${stateDir}/bt.state"; then
      /run/wrappers/bin/rfkill unblock bluetooth 2>/dev/null \
        || rfkill unblock bluetooth 2>/dev/null || true
    fi

    # ---- 3. Wi-Fi restore -- only re-enable if it was enabled before ----
    if [ -f "${stateDir}/wifi.state" ] && \
        grep -q enabled "${stateDir}/wifi.state"; then
      nmcli radio wifi on 2>/dev/null || true
    fi

    # ---- 4. Audio restore ----
    if [ -f "${stateDir}/pipewire.state" ]; then
      systemctl start pipewire.service wireplumber.service 2>/dev/null || true
      rm -f "${stateDir}/pipewire.state"
    fi

    # ---- 5. DPMS on (last so radios are up before the screen wakes) ----
    SOCK=$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1)
    if [ -n "$SOCK" ]; then
      SWAYSOCK="$SOCK" swaymsg 'output * power on' >/dev/null 2>&1 || true
    fi

    echo "$(date -Is) lid-open: completed" >> "$log"
  '';

  lidHandler = pkgs.writeShellScript "rocknix-lid-handler" ''
    set -u
    export PATH=${lib.makeBinPath (with pkgs; [ evtest coreutils gnugrep ])}

    DEVICE=/dev/input/event6
    if [ ! -r "$DEVICE" ]; then
      echo "lid-handler: $DEVICE not readable; exiting" >&2
      exit 1
    fi

    echo "lid-handler: watching $DEVICE for SW_LID transitions" >&2

    # evtest emits lines like:
    #   Event: time 1234.567890, type 5 (EV_SW), code 0 (SW_LID), value 1
    # value 1 = closed, value 0 = open.
    evtest "$DEVICE" 2>/dev/null | while IFS= read -r line; do
      case "$line" in
        *"type 5 (EV_SW)"*"code 0 (SW_LID)"*"value 1"*)
          echo "lid-handler: CLOSE event" >&2
          ${lidClose} || true
          ;;
        *"type 5 (EV_SW)"*"code 0 (SW_LID)"*"value 0"*)
          echo "lid-handler: OPEN event" >&2
          ${lidOpen} || true
          ;;
      esac
    done
  '';
in
{
  environment.systemPackages = with pkgs; [
    evtest
    util-linux  # for rfkill
  ];

  # CRITICAL: disable logind's built-in lid/power/suspend handling so the
  # guest's logind does NOT try to react to SW_LID events flowing through
  # the bound /dev/input/event6. Default NixOS logind has
  # HandleLidSwitch=suspend; in nspawn, suspend isn't supported, but the
  # error handling escalates and the cumulative effect on Thor 2026-05-08
  # was a full container shutdown on the next lid edge. Our
  # rocknix-lid-handler is the SINGLE owner of lid semantics in Layer 14.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "ignore";
    HandleSuspendKey = "ignore";
  };

  systemd.services.rocknix-lid-handler = {
    description = "ROCKNIX Layer 14 lid-switch handler (fake suspend)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" "rocknix-sway-kiosk.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lidHandler}";
      Restart = "on-failure";
      RestartSec = "5s";
      # No sandboxing -- needs to write /sys cpufreq, run nmcli/rfkill,
      # touch /run state, talk to systemd. Keep it simple.
    };
  };
}
