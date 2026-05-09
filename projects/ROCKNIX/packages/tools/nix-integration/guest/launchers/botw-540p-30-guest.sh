#!/run/current-system/sw/bin/bash
# BOTW Cemu launcher for the Layer 14 Nix guest.
# Adapted from /storage/bin/botw-540p-fsr.sh:
#   - drops gamescope wrapper (cemu has native wayland fullscreen,
#     gamescope nested-in-sway is fragile in our guest)
#   - drops mangohud (lib coupling deferred)
#   - uses sed for settings.xml mutation (no python in guest)
#   - calls /storage/.guest/start_cemu_guest.sh (nix-built cemu)
# Settings: 960x540 internal, 30fps cap, conservative CPU/GPU caps.
set -eu

ROM="/storage/roms/wiiu/The Legend of Zelda - Breath of the Wild (USA) (DLC) (v208).wua"
SETTINGS="/storage/.config/Cemu/settings.xml"
LOG="/storage/.guest/runs/cemu-botw-540p-30.log"

# /sys -- writable from guest (we verified)
P3="/sys/devices/system/cpu/cpufreq/policy3"
P7="/sys/devices/system/cpu/cpufreq/policy7"
GPU="/sys/class/devfreq/3d00000.gpu"
P3_MAX="1401600"
P7_MAX="1478400"
GPU_MIN="220000000"
GPU_MAX="550000000"

mkdir -p "$(dirname "$LOG")"
: > "$LOG"
exec >>"$LOG" 2>&1

echo "[$(date)] BOTW 540p/30 guest launcher starting"

# Stop any existing cemu in the guest
pkill -9 -f "Cemu" 2>/dev/null || true
sleep 1

# Verify ROM
if [ ! -f "$ROM" ]; then
  echo "ERROR: ROM not found: $ROM"; exit 3
fi

# Mutate settings.xml: 540p / 30fps / sync flags off (sed, not python)
if [ -f "$SETTINGS" ]; then
  cp -a "$SETTINGS" "${SETTINGS}.bak.$$"
  sed -i \
    -e 's|<category>Resolution</category>\s*<preset>[^<]*</preset>|<category>Resolution</category><preset>960x540</preset>|' \
    -e 's|<category>FPS Limit</category>\s*<preset>[^<]*</preset>|<category>FPS Limit</category><preset>30FPS Limit</preset>|' \
    -e 's|<category>Framerate Limit</category>\s*<preset>[^<]*</preset>|<category>Framerate Limit</category><preset>30FPS (ideal for 240/120/60Hz displays)</preset>|' \
    -e 's|<open_pad>true</open_pad>|<open_pad>false</open_pad>|' \
    -e 's|<GX2DrawdoneSync>true</GX2DrawdoneSync>|<GX2DrawdoneSync>false</GX2DrawdoneSync>|' \
    -e 's|<vkAccurateBarriers>true</vkAccurateBarriers>|<vkAccurateBarriers>false</vkAccurateBarriers>|' \
    -e 's|<VSync>1</VSync>|<VSync>0</VSync>|' \
    "$SETTINGS"
  echo "settings.xml mutated"
fi

# Apply the wii_u_pro_controller profile if present
if [ -f /storage/.config/Cemu/controllerProfiles/wii_u_pro_controller.xml ]; then
  cp /storage/.config/Cemu/controllerProfiles/wii_u_pro_controller.xml \
     /storage/.config/Cemu/controllerProfiles/controller0.xml
fi

# CPU/GPU tuning
# Note: this writes to /sys directly from inside the guest.
# nspawn binds /sys/devices/system/cpu/cpufreq + /sys/class/devfreq rw.
echo schedutil > "$P3/scaling_governor" 2>/dev/null || \
  echo ondemand > "$P3/scaling_governor" 2>/dev/null || true
echo schedutil > "$P7/scaling_governor" 2>/dev/null || \
  echo ondemand > "$P7/scaling_governor" 2>/dev/null || true
echo "$P3_MAX" > "$P3/scaling_max_freq" 2>/dev/null || true
echo "$P7_MAX" > "$P7/scaling_max_freq" 2>/dev/null || true
echo simple_ondemand > "$GPU/governor" 2>/dev/null || true
echo "$GPU_MIN" > "$GPU/min_freq" 2>/dev/null || true
echo "$GPU_MAX" > "$GPU/max_freq" 2>/dev/null || true

# Launch via sway-kiosk so it inherits the wayland-1 socket
SOCK=$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1)
if [ -z "$SOCK" ]; then
  echo "ERROR: no sway socket"; exit 4
fi

SWAYSOCK="$SOCK" \
  /run/current-system/sw/bin/swaymsg "exec /storage/.guest/start_cemu_guest.sh '$ROM'" >/dev/null 2>&1

# Wait for cemu pid to settle and pin its threads to big cores 3-7
sleep 8
CEMU_PID=$(pgrep -f "Cemu -f -g" | head -1 || true)
if [ -n "$CEMU_PID" ]; then
  for tid in $(ls /proc/$CEMU_PID/task 2>/dev/null); do
    /run/current-system/sw/bin/taskset -p 0xF8 "$tid" >/dev/null 2>&1 || true
  done
  echo "BOTW 540p/30 launched. Cemu PID: $CEMU_PID"
else
  echo "WARN: cemu pid not found yet"
fi
