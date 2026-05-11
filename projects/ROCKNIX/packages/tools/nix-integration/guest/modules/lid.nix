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
#   3. SIGSTOP every PID inside the sway-kiosk cgroup that is NOT sway
#      itself or one of its bar/bg helpers. Targets the actual battery
#      drain: apps that keep submitting frames after DPMS off (e.g.
#      glmark2 with --run-forever, cemu with --run-forever shaders).
#      The stopped PIDs are recorded in /run/rocknix-lid/stopped.pids
#      so lid-open only SIGCONTs the ones we paused (avoiding races
#      with new processes started during the closed window).
#   4. systemctl stop pipewire / wireplumber if active (releases the
#      audio DSP path; safe no-op if audio.nix isn't running yet).
#   5. nmcli radio wifi off  -- WILL DISCONNECT ACTIVE SSH. If you need
#      SSH to survive lid-cycle testing, touch the master kill switch:
#        touch /storage/.guest/lid-suspend.disabled
#      The whole handler is then a no-op until that file is removed.
#   6. rfkill block bluetooth.
#   7. echo powersave > scaling_governor  for every cpufreq policy.
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
    if systemctl --quiet is-active rocknix-pipewire.service 2>/dev/null; then
      echo active > "${stateDir}/pipewire.state"
    fi

    # ---- 2. DPMS off both panels via sway IPC ----
    SOCK=$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1)
    if [ -n "$SOCK" ]; then
      SWAYSOCK="$SOCK" swaymsg 'output * power off' >/dev/null 2>&1 || true
    fi

    # ---- 3. SIGSTOP non-keep PIDs inside the sway-kiosk cgroup ----
    # Allowlist (process /proc/PID/comm names we keep alive so sway can
    # repaint on lid-open instantly):
    #   sway, swaybg, swaybar, sway-bar-stat (truncated comm of
    #   sway-bar-status). Anything else in the cgroup gets SIGSTOPped:
    #   foot, fuzzel, glmark2-wayland, cemu, retroarch, etc. The
    #   stopped-PID list is recorded so lid-open only thaws those.
    SWAY_CG=/sys/fs/cgroup/system.slice/rocknix-sway-kiosk.service
    : > "${stateDir}/stopped.pids"
    if [ -r "$SWAY_CG/cgroup.procs" ]; then
      while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "")
        # NixOS wraps binaries: real comm is often `.swaybg-wrapped`
        # rather than `swaybg`. Match both forms.
        case "$comm" in
          sway|swaybg|swaybar|sway-bar-stat|sway-bar-statu|sd-pam) ;;
          .sway-wrapped|.swaybg-wrapped|.swaybar-wrapped) ;;
          dbus-daemon|dbus-run-sessio|dbus-run-session) ;;
          bash|sh) ;;
          *)
            if kill -STOP "$pid" 2>/dev/null; then
              echo "$pid $comm" >> "${stateDir}/stopped.pids"
            fi
            ;;
        esac
      done < "$SWAY_CG/cgroup.procs"
    fi

    # ---- 4. stop audio if running ----
    if [ -f "${stateDir}/pipewire.state" ]; then
      systemctl stop rocknix-pipewire-pulse.service rocknix-wireplumber.service rocknix-pipewire.service 2>/dev/null || true
    fi

    # ---- 5. Wi-Fi off (kills SSH if you're connected -- by design) ----
    nmcli radio wifi off 2>/dev/null || true

    # ---- 6. Bluetooth off ----
    /run/wrappers/bin/rfkill block bluetooth 2>/dev/null \
      || rfkill block bluetooth 2>/dev/null || true

    # ---- 7. CPU governors -> powersave ----
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
      systemctl start rocknix-pipewire.service rocknix-wireplumber.service rocknix-pipewire-pulse.service 2>/dev/null || true
      rm -f "${stateDir}/pipewire.state"
    fi

    # ---- 5. SIGCONT the apps we stopped on close ----
    # Only thaw PIDs we recorded -- a process that exited during the
    # closed window won't exist anymore and that's fine.
    if [ -f "${stateDir}/stopped.pids" ]; then
      while IFS=' ' read -r pid comm; do
        [ -n "$pid" ] || continue
        kill -CONT "$pid" 2>/dev/null || true
      done < "${stateDir}/stopped.pids"
      rm -f "${stateDir}/stopped.pids"
    fi

    # ---- 6. DPMS on (last so radios are up before the screen wakes) ----
    SOCK=$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1)
    if [ -n "$SOCK" ]; then
      SWAYSOCK="$SOCK" swaymsg 'output * power on' >/dev/null 2>&1 || true
    fi

    echo "$(date -Is) lid-open: completed" >> "$log"
  '';

  volumeControl = pkgs.writeShellScriptBin "rocknix-volume" ''
    set -u
    export PATH=${lib.makeBinPath (with pkgs; [ pipewire pulseaudio coreutils gnugrep ])}

    step="5%"
    case "''${1:-}" in
      up|+) delta="$step+" ;;
      down|-) delta="$step-" ;;
      *)
        echo "rocknix-volume: usage: $0 up|down" >&2
        exit 64
        ;;
    esac

    if wpctl status >/dev/null 2>&1; then
      wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "$delta"
      wpctl get-volume @DEFAULT_AUDIO_SINK@ >&2 || true
    elif pactl info >/dev/null 2>&1; then
      case "$delta" in
        *+) pactl set-sink-volume @DEFAULT_SINK@ +"$step" ;;
        *-) pactl set-sink-volume @DEFAULT_SINK@ -"$step" ;;
      esac
      pactl get-sink-volume @DEFAULT_SINK@ >&2 || true
    else
      echo "rocknix-volume: no PipeWire/PulseAudio control socket available" >&2
      exit 69
    fi
  '';

  powerToggle = pkgs.writeShellScriptBin "rocknix-power-toggle" ''
    set -u
    export PATH=${lib.makeBinPath (with pkgs; [ coreutils ])}

    flag="${stateDir}/power-fake-suspend-active.flag"
    mkdir -p "${stateDir}"

    if [ -e "${killSwitch}" ]; then
      echo "power-toggle: kill switch present (${killSwitch}); skipping" >&2
      exit 0
    fi

    if [ -f "$flag" ]; then
      rm -f "$flag"
      echo "power-toggle: resume" >&2
      ${lidOpen} || true
    else
      touch "$flag"
      echo "power-toggle: fake suspend" >&2
      ${lidClose} || true
    fi
  '';

  hardwareButtonHandler = pkgs.writeShellScriptBin "rocknix-hardware-button-handler" ''
    set -u
    export PATH=${lib.makeBinPath (with pkgs; [ evtest coreutils gnugrep ])}

    find_event_by_name() {
      wanted="$1"
      for name_file in /sys/class/input/event*/device/name; do
        [ -r "$name_file" ] || continue
        name=$(cat "$name_file" 2>/dev/null || true)
        [ "$name" = "$wanted" ] || continue
        event_dir=$(dirname "$(dirname "$name_file")")
        echo "/dev/input/$(basename "$event_dir")"
        return 0
      done
      return 1
    }

    watch_device() {
      label="$1"
      device="$2"
      if [ -z "$device" ]; then
        echo "hardware-button-handler: $label device not found" >&2
        return 0
      fi

      while true; do
        if [ ! -r "$device" ]; then
          echo "hardware-button-handler: $label $device not readable; retrying" >&2
          sleep 5
          continue
        fi

        echo "hardware-button-handler: watching $label on $device" >&2
        evtest "$device" 2>/dev/null | while IFS= read -r line; do
          case "$line" in
            *"type 1 (EV_KEY)"*"code 115 (KEY_VOLUMEUP)"*"value 1"*|*"type 1 (EV_KEY)"*"code 115 (KEY_VOLUMEUP)"*"value 2"*)
              echo "hardware-button-handler: volume up" >&2
              ${volumeControl}/bin/rocknix-volume up || true
              ;;
            *"type 1 (EV_KEY)"*"code 114 (KEY_VOLUMEDOWN)"*"value 1"*|*"type 1 (EV_KEY)"*"code 114 (KEY_VOLUMEDOWN)"*"value 2"*)
              echo "hardware-button-handler: volume down" >&2
              ${volumeControl}/bin/rocknix-volume down || true
              ;;
            *"type 1 (EV_KEY)"*"code 116 (KEY_POWER)"*"value 1"*)
              echo "hardware-button-handler: power press" >&2
              ${powerToggle}/bin/rocknix-power-toggle || true
              ;;
            *"type 5 (EV_SW)"*"code 0 (SW_LID)"*"value 1"*)
              echo "hardware-button-handler: lid close" >&2
              rm -f "${stateDir}/power-fake-suspend-active.flag"
              ${lidClose} || true
              ;;
            *"type 5 (EV_SW)"*"code 0 (SW_LID)"*"value 0"*)
              echo "hardware-button-handler: lid open" >&2
              rm -f "${stateDir}/power-fake-suspend-active.flag"
              ${lidOpen} || true
              ;;
          esac
        done

        echo "hardware-button-handler: $label watcher exited; restarting" >&2
        sleep 2
      done
    }

    power_device=$(find_event_by_name pmic_pwrkey || true)
    volume_down_device=$(find_event_by_name pmic_resin || true)
    gpio_keys_device=$(find_event_by_name gpio-keys || true)

    watch_device power "$power_device" &
    watch_device volume-down "$volume_down_device" &
    watch_device gpio-keys "$gpio_keys_device" &

    wait
  '';
in
{
  environment.systemPackages = with pkgs; [
    evtest
    util-linux  # for rfkill
    volumeControl
    powerToggle
  ];

  # CRITICAL: disable logind's built-in lid/power/suspend handling so the
  # guest's logind does NOT try to react to SW_LID or KEY_POWER events flowing
  # through the bound /dev/input devices. Default NixOS logind has
  # HandleLidSwitch=suspend; in nspawn, suspend isn't supported, but the
  # error handling escalates and the cumulative effect on Thor 2026-05-08
  # was a full container shutdown on the next lid edge. Our
  # rocknix-hardware-button-handler is the SINGLE owner of lid/power/volume
  # semantics in Layer 14.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "ignore";
    HandleSuspendKey = "ignore";
  };

  systemd.services.rocknix-hardware-button-handler = {
    description = "ROCKNIX Layer 14 hardware button handler (volume, power, lid)";
    wantedBy = [ "multi-user.target" ];
    # Order after the root-scoped audio services this module's audio.nix
    # sibling actually provides. The legacy NixOS-managed unit names
    # (pipewire.service / pipewire-pulse.service) are inactive in
    # main-space mode because we own pipewire/wireplumber/pipewire-pulse
    # as separate root-scoped units anchored to /run/user/0. If the
    # handler started before those, the first volume button press would
    # race the socket creation and `wpctl status` would fail with
    # "no PipeWire/PulseAudio control socket available".
    after = [
      "systemd-user-sessions.service"
      "rocknix-sway-kiosk.service"
      "rocknix-pipewire.service"
      "rocknix-pipewire-pulse.service"
      "rocknix-wireplumber.service"
    ];
    # rocknix-volume invokes wpctl / pactl, which both probe the
    # PipeWire socket at $XDG_RUNTIME_DIR/pipewire-0 and the Pulse
    # socket at $PULSE_SERVER. The handler unit runs as root with the
    # systemd minimal environment by default; without these vars its
    # children fail with "no PipeWire/PulseAudio control socket
    # available" even though the sockets exist under /run/user/0/.
    # Same triplet the rocknix-pipewire* services use for their own
    # anchor (see modules/audio.nix). Verified on Thor 2026-05-11.
    environment = {
      XDG_RUNTIME_DIR = "/run/user/0";
      PULSE_SERVER = "unix:/run/user/0/pulse/native";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/0/bus";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${hardwareButtonHandler}/bin/rocknix-hardware-button-handler";
      Restart = "on-failure";
      RestartSec = "5s";
      # No sandboxing -- needs to read /dev/input, write /sys cpufreq, run
      # nmcli/rfkill, touch /run state, talk to systemd, and control audio.
      # Keep it simple.
    };
  };
}
