# ---- profile table ----
# RES        = exact preset string in cemu.s Resolution graphic pack
# FPS_LIMIT  = exact preset string in FPS Limit (game speed clamp)
# FRAMERATE  = exact preset string in Framerate Limit (display sync)
#
# Device performance policy lives in cemu-sm8550-performance.sh so BOTW
# remains a validation workload/helper rather than the owner of SM8550 policy.

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
LOG_DIR="/storage/.guest/runs"
mkdir -p "$LOG_DIR"
LAUNCHER_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PERF_HELPER="${CEMU_SM8550_PERF_HELPER:-$LAUNCHER_DIR/cemu-sm8550-performance.sh}"

# ---- profile table ----
# RES        = exact preset string in cemu's Resolution graphic pack
# FPS_LIMIT  = exact preset string in FPS Limit (game speed clamp)
# FRAMERATE  = exact preset string in Framerate Limit (display sync)
#
# Device performance policy lives in cemu-sm8550-performance.sh so BOTW
# remains a validation workload/helper rather than the owner of SM8550 policy.

case "$PROFILE" in
  potato-30)
    RES="640x360";        FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    ;;
  540p-30)
    RES="960x540";        FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    ;;
  540p-45)
    RES="960x540";        FPS_LIMIT="45FPS Limit"; FRAMERATE="40FPS (ideal for 240/120/60Hz displays)"
    ;;
  720p-30)
    RES="1280x720 (HD, Default)"; FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    ;;
  720p-45)
    RES="1280x720 (HD, Default)"; FPS_LIMIT="45FPS Limit"; FRAMERATE="40FPS (ideal for 240/120/60Hz displays)"
    ;;
  900p-30)
    RES="1600x900 (HD+)"; FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    ;;
  native-30)
    RES="1920x1080 (Full HD)"; FPS_LIMIT="30FPS Limit"; FRAMERATE="30FPS (ideal for 240/120/60Hz displays)"
    ;;
  *)
    echo "Unknown profile: $PROFILE" >&2
    echo "Try: potato-30 540p-30 540p-45 720p-30 720p-45 900p-30 native-30" >&2
    exit 1
    ;;
esac

LOG="$LOG_DIR/cemu-botw-$PROFILE.log"
PERF_DESC="$([ -x "$PERF_HELPER" ] && "$PERF_HELPER" describe "$PROFILE" 2>/dev/null || printf 'performance-helper=missing')"
echo "[$(date)] BOTW profile=$PROFILE res=$RES fps=$FPS_LIMIT framerate=$FRAMERATE $PERF_DESC" | tee "$LOG"

# ---- settings.xml mutation ----
#
# The XML stores `<category>...</category>` and the matching
# `<preset>...</preset>` on adjacent lines with indentation between
# them. BusyBox sed cannot match across newlines, so use Perl's regex
# engine to update the whole file as one string.
if [ -f "$SETTINGS" ]; then
  cp -f "$SETTINGS" "$SETTINGS.bak.$$"
  perl -0pi -e '
    BEGIN { our ($res, $fps_limit, $framerate) = splice @ARGV, 0, 3; }
    our ($res, $fps_limit, $framerate);
    s{(<category>Resolution</category>\s*<preset>)[^<]*(</preset>)}{$1$res$2}s;
    s{(<category>FPS Limit</category>\s*<preset>)[^<]*(</preset>)}{$1$fps_limit$2}s;
    s{(<category>Framerate Limit</category>\s*<preset>)[^<]*(</preset>)}{$1$framerate$2}s;
    s{<open_pad>true</open_pad>}{<open_pad>false</open_pad>}g;
    s{<GX2DrawdoneSync>true</GX2DrawdoneSync>}{<GX2DrawdoneSync>false</GX2DrawdoneSync>}g;
    s{<vkAccurateBarriers>true</vkAccurateBarriers>}{<vkAccurateBarriers>false</vkAccurateBarriers>}g;
    s{<VSync>1</VSync>}{<VSync>0</VSync>}g;
  ' "$RES" "$FPS_LIMIT" "$FRAMERATE" "$SETTINGS"

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

# ---- SM8550 device performance policy ----
if [ -x "$PERF_HELPER" ]; then
  CEMU_PERF_LOG="$LOG" "$PERF_HELPER" apply "$PROFILE" || true
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

# Wait until cemu has spawned, then let the SM8550 performance helper apply
# measured affinity/reassertion policy. Runtime A/B harnesses may set
# CEMU_AFFINITY_MASK=none or another taskset mask without rewriting this
# validation launcher.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  CEMU_PID="$(pgrep -x Cemu 2>/dev/null | head -1 || true)"
  [ -n "$CEMU_PID" ] || CEMU_PID="$(pgrep -x cemu 2>/dev/null | head -1 || true)"
  [ -n "$CEMU_PID" ] && break
  sleep 1
done

if [ -n "${CEMU_PID:-}" ] && [ -d "/proc/$CEMU_PID/task" ] && [ -x "$PERF_HELPER" ]; then
  CEMU_PERF_LOG="$LOG" "$PERF_HELPER" pin "$PROFILE" "$CEMU_PID" || true
fi

echo "[$(date)] BOTW $PROFILE launched. Cemu PID: ${CEMU_PID:-none}. Log: $LOG" | tee -a "$LOG"

# Block until cemu exits so the games-launcher loop pauses correctly.
if [ -n "${CEMU_PID:-}" ]; then
  while kill -0 "$CEMU_PID" 2>/dev/null; do
    sleep 5
  done
fi
