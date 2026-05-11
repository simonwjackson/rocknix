#!/bin/sh
# botw-guest.sh -- parametric BOTW launcher for the Layer 14 Nix guest
#
# Usage: botw-guest.sh <profile>
#
# Profiles (mirrors host /storage/bin/botw-*.sh table, sans gamescope):
#   potato-30   640x360   30FPS  cool / minimum draw
#   540p-30     960x540   30FPS  default cool profile (ex botw-540p-fsr)
#   540p-45     960x540   45FPS  high-FPS aggressive (ex botw-fast)
#   720p-30     1280x720  30FPS  cool 720p (ex botw-720p-fsr)
#   720p-45     1280x720  45FPS  high-FPS 720p (ex botw-balanced-fast)
#   900p-30     1600x900  30FPS  cool 900p (ex botw-fsr)
#   native-30   1920x1080 30FPS  no upscaling
#
# Differences vs the host scripts:
#   - No gamescope wrapper. Cemu fullscreens directly to sway. Nested
#     gamescope under sway crashes with C++ terminate; cemu's own
#     resolution pack already controls internal render res.
#   - No mangohud (deferred until we package it as nix).
#   - No python -- sed for settings.xml mutation. The XML mutator is
#     the same set of toggles for every profile (open_pad=false,
#     GX2DrawdoneSync=false, vkAccurateBarriers=false, VSync=0) so it
#     lives in one place.

set -eu

PATH=/run/current-system/sw/bin:/usr/bin:/bin
export PATH

PROFILE="${1:-540p-30}"
ROM="${CEMU_ROM:-/storage/roms/wiiu/The Legend of Zelda - Breath of the Wild (USA) (DLC) (v208).wua}"
SETTINGS="/storage/.config/Cemu/settings.xml"
P3="/sys/devices/system/cpu/cpufreq/policy3"
P7="/sys/devices/system/cpu/cpufreq/policy7"
GPU="/sys/class/devfreq/3d00000.gpu"
LOG_DIR="/storage/.guest/runs"
mkdir -p "$LOG_DIR"

# ---- profile table ----
# RES        = exact preset string in cemu's Resolution graphic pack
# FPS_LIMIT  = exact preset string in FPS Limit (game speed clamp)
# FRAMERATE  = exact preset string in Framerate Limit (display sync)
# P3_MAX     = scaling_max_freq for policy3 (medium cluster)
# P7_MAX     = scaling_max_freq for policy7 (big cluster)
# GPU_MIN/MAX (kHz, blank = leave alone)
# GPU_GOV    = simple_ondemand or performance

write_sysfs() {
  path="$1"
  value="$2"
  [ -e "$path" ] || return 0
  [ -w "$path" ] || return 0
  printf '%s\n' "$value" > "$path" 2>/dev/null || true
}

case "$PROFILE" in
  potato-30)
    RES="640x360";        FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    P3_MAX=1401600;       P7_MAX=1478400
    GPU_MIN=220000000;    GPU_MAX=475000000;       GPU_GOV=simple_ondemand
    ;;
  540p-30)
    RES="960x540";        FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    P3_MAX=1401600;       P7_MAX=1478400
    GPU_MIN=220000000;    GPU_MAX=550000000;       GPU_GOV=simple_ondemand
    ;;
  540p-45)
    RES="960x540";        FPS_LIMIT="45FPS Limit"; FRAMERATE="40FPS (ideal for 240/120/60Hz displays)"
    # Live U3 validation in heavy Zora/rain scenes showed the old capped
    # high-FPS profile could sit around 30-35 FPS. Keep CPU unrestricted and
    # pin the GPU at its available max for subsequent peelback validation.
    P3_MAX=2803200;       P7_MAX=2956800
    GPU_MIN=680000000;    GPU_MAX=680000000;       GPU_GOV=simple_ondemand
    ;;
  720p-30)
    RES="1280x720 (HD, Default)"; FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    P3_MAX=1401600;       P7_MAX=1478400
    GPU_MIN=220000000;    GPU_MAX=615000000;       GPU_GOV=simple_ondemand
    ;;
  720p-45)
    RES="1280x720 (HD, Default)"; FPS_LIMIT="45FPS Limit"; FRAMERATE="40FPS (ideal for 240/120/60Hz displays)"
    P3_MAX=2803200;       P7_MAX=2956800
    GPU_MIN=680000000;    GPU_MAX=680000000;       GPU_GOV=simple_ondemand
    ;;
  900p-30)
    RES="1600x900 (HD+)"; FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    P3_MAX=1401600;       P7_MAX=1478400
    GPU_MIN=220000000;    GPU_MAX=680000000;       GPU_GOV=simple_ondemand
    ;;
  native-30)
    RES="1920x1080 (Full HD)"; FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    P3_MAX=1401600;       P7_MAX=1478400
    GPU_MIN=220000000;    GPU_MAX=680000000;       GPU_GOV=simple_ondemand
    ;;
  *)
    echo "Unknown profile: $PROFILE" >&2
    echo "Try: potato-30 540p-30 540p-45 720p-30 720p-45 900p-30 native-30" >&2
    exit 1
    ;;
esac

LOG="$LOG_DIR/cemu-botw-$PROFILE.log"
echo "[$(date)] BOTW profile=$PROFILE res=$RES fps=$FPS_LIMIT framerate=$FRAMERATE p3=$P3_MAX p7=$P7_MAX gpu=$GPU_GOV(${GPU_MIN:-_}->${GPU_MAX:-_})" | tee "$LOG"

# ---- settings.xml mutation ----
#
# The XML stores `<category>...</category>` and the matching
# `<preset>...</preset>` on adjacent lines with indentation between
# them. Standard sed is line-buffered so `[[:space:]]*` cannot cross
# the newline. We use `sed -z` (GNU extension) which slurps the
# whole file as one record so the pattern matches across lines.
if [ -f "$SETTINGS" ]; then
  cp -f "$SETTINGS" "$SETTINGS.bak.$$"
  sed -zi \
    -e "s|\(<category>Resolution</category>[[:space:]]*<preset>\)[^<]*\(</preset>\)|\1${RES}\2|" \
    -e "s|\(<category>FPS Limit</category>[[:space:]]*<preset>\)[^<]*\(</preset>\)|\1${FPS_LIMIT}\2|" \
    -e "s|\(<category>Framerate Limit</category>[[:space:]]*<preset>\)[^<]*\(</preset>\)|\1${FRAMERATE}\2|" \
    -e 's|<open_pad>true</open_pad>|<open_pad>false</open_pad>|' \
    -e 's|<GX2DrawdoneSync>true</GX2DrawdoneSync>|<GX2DrawdoneSync>false</GX2DrawdoneSync>|' \
    -e 's|<vkAccurateBarriers>true</vkAccurateBarriers>|<vkAccurateBarriers>false</vkAccurateBarriers>|' \
    -e 's|<VSync>1</VSync>|<VSync>0</VSync>|' \
    "$SETTINGS"

  # Verify the mutation actually took -- if it didn't, abort the
  # launch instead of running cemu with the wrong preset and giving
  # the user a confusing low-FPS experience.
  if ! grep -q "<preset>${RES}</preset>" "$SETTINGS"; then
    echo "FATAL: settings.xml Resolution preset did not become '${RES}'." >&2
    echo "       Restoring backup and aborting launch." >&2
    mv -f "$SETTINGS.bak.$$" "$SETTINGS"
    exit 2
  fi
fi

# Mirror controller profile (host script does this so a fresh boot
# picks up the wii_u_pro_controller mapping as controller0).
PROF_DIR=/storage/.config/Cemu/controllerProfiles
if [ -f "$PROF_DIR/wii_u_pro_controller.xml" ] && [ ! -f "$PROF_DIR/controller0.xml" ]; then
  cp "$PROF_DIR/wii_u_pro_controller.xml" "$PROF_DIR/controller0.xml" || true
fi

# ---- CPU / GPU governors ----
if [ -d "$P3" ]; then
  write_sysfs "$P3/scaling_governor" schedutil
  write_sysfs "$P3/scaling_max_freq" "$P3_MAX"
fi
if [ -d "$P7" ]; then
  write_sysfs "$P7/scaling_governor" schedutil
  write_sysfs "$P7/scaling_max_freq" "$P7_MAX"
fi
# GPU sysfs is bind-mounted but read-only inside nspawn (sysfs RO by
# default). Writes here always fail. The companion script
#   /storage/.guest/host-tune.sh <profile>
# runs on the HOST and applies the same governor + freq table to
# /sys/class/devfreq/3d00000.gpu where the writes actually take.
# We still attempt the writes here so the values land if anything
# changes the bind in the future -- but failures are silent.
if [ -d "$GPU" ]; then
  write_sysfs "$GPU/governor" "$GPU_GOV"
  [ -n "$GPU_MIN" ] && write_sysfs "$GPU/min_freq" "$GPU_MIN"
  [ -n "$GPU_MAX" ] && write_sysfs "$GPU/max_freq" "$GPU_MAX"
fi

# ---- launch via swaymsg so cemu inherits sway's wayland env ----
export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=wayland-1

# Make sure cemu lands on DSI-2 (top main screen). Workspace 1 is on
# DSI-2 by sway's default placement; focus it before exec.
SOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.0.*.sock 2>/dev/null | head -1 || true)
if [ -n "$SOCK" ]; then
  if command -v timeout >/dev/null 2>&1; then
    SWAYSOCK="$SOCK" timeout 5s swaymsg "focus output DSI-2" >/dev/null 2>&1 || true
    SWAYSOCK="$SOCK" timeout 5s swaymsg "exec /storage/.guest/start_cemu_guest.sh '$ROM'" >/dev/null 2>&1 || true
  else
    SWAYSOCK="$SOCK" swaymsg "focus output DSI-2" >/dev/null 2>&1 || true
    SWAYSOCK="$SOCK" swaymsg "exec /storage/.guest/start_cemu_guest.sh '$ROM'" >/dev/null 2>&1 || true
  fi
fi

# Wait until cemu has spawned, then optionally pin its threads. Default
# matches the historically tested big-core mask. Runtime A/B harnesses may
# set CEMU_AFFINITY_MASK=none or another taskset mask to test scheduler
# behavior without rewriting this launcher.
CEMU_AFFINITY_MASK="${CEMU_AFFINITY_MASK:-0xF8}"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  CEMU_PID="$(pgrep -x Cemu 2>/dev/null | head -1 || true)"
  [ -n "$CEMU_PID" ] || CEMU_PID="$(pgrep -x cemu 2>/dev/null | head -1 || true)"
  [ -n "$CEMU_PID" ] && break
  sleep 1
done

if [ -n "${CEMU_PID:-}" ] && [ -d "/proc/$CEMU_PID/task" ]; then
  if [ "$CEMU_AFFINITY_MASK" != "none" ]; then
    for tid in /proc/"$CEMU_PID"/task/*; do
      taskset -p "$CEMU_AFFINITY_MASK" "$(basename "$tid")" >/dev/null 2>&1 || true
    done
  fi
  # Reassert max freqs in case kernel scaled them back during launch.
  [ -d "$P3" ] && write_sysfs "$P3/scaling_max_freq" "$P3_MAX"
  [ -d "$P7" ] && write_sysfs "$P7/scaling_max_freq" "$P7_MAX"
fi

echo "[$(date)] BOTW $PROFILE launched. Cemu PID: ${CEMU_PID:-none}. Log: $LOG" | tee -a "$LOG"

# Block until cemu exits so the games-launcher loop pauses correctly.
if [ -n "${CEMU_PID:-}" ]; then
  while kill -0 "$CEMU_PID" 2>/dev/null; do
    sleep 5
  done
fi
