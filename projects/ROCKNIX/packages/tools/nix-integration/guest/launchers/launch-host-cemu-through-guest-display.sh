#!/bin/sh
# launch-host-cemu-through-guest-display.sh -- diagnostic host-control launcher.
#
# Runs on the ROCKNIX host. It launches host /usr/bin/cemu through the
# guest-visible Wayland display shape so Cemu host control can be compared with
# a guest-native Cemu candidate in remote-cemu-live-campaign.sh.
set -eu

PROFILE="${1:-${PROFILE:-720p-45}}"
RUN_DIR="${RUN_DIR:-/storage/.guest/runs/host-cemu-control-manual}"
ROM="${CEMU_ROM:-/storage/roms/wiiu/The Legend of Zelda - Breath of the Wild (USA) (DLC) (v208).wua}"
SETTINGS="/storage/.config/Cemu/settings.xml"
MANGOHUD_CONF="${MANGOHUD_CONFIGFILE:-/storage/.config/MangoHud/MangoHud.conf}"
P3="/sys/devices/system/cpu/cpufreq/policy3"
P7="/sys/devices/system/cpu/cpufreq/policy7"
GPU="/sys/class/devfreq/3d00000.gpu"
OUT_W="1920"
OUT_H="1080"
FILTER="${HOST_CEMU_FILTER:-fsr}"
LOG="${RUN_DIR}/host-cemu-stdout.log"

find_cemu_pid() {
  # `pgrep -x cemu | head -1 || ...` is unsafe because `head` succeeds even
  # when pgrep prints nothing. Use ps' exact comm field and prefer the host
  # executable so host-control cannot accidentally pin an unrelated guest Cemu.
  ps -eo pid=,comm=,args= | awk '
    $2 == "cemu" && $0 ~ /\/usr\/bin\/cemu/ { print $1; found=1; exit }
    $2 == "Cemu" && found != 1 { candidate=$1 }
    END { if (!found && candidate != "") print candidate }
  '
}

case "$PROFILE" in
  potato-30|360p-30)
    CEMU_RES="640x360"; NESTED_W=640; NESTED_H=360; FPS_MODE=30; GS_REFRESH=60
    P3_MAX=1401600; P7_MAX=1478400; GPU_GOV=simple_ondemand; GPU_MIN=220000000; GPU_MAX=475000000
    ;;
  540p-30)
    CEMU_RES="960x540"; NESTED_W=960; NESTED_H=540; FPS_MODE=30; GS_REFRESH=60
    P3_MAX=1401600; P7_MAX=1478400; GPU_GOV=simple_ondemand; GPU_MIN=220000000; GPU_MAX=550000000
    ;;
  540p-45)
    CEMU_RES="960x540"; NESTED_W=960; NESTED_H=540; FPS_MODE=45; GS_REFRESH=120
    P3_MAX=1785600; P7_MAX=1843200; GPU_GOV=performance; GPU_MIN=220000000; GPU_MAX=680000000
    ;;
  720p-30)
    CEMU_RES="1280x720 (HD, Default)"; NESTED_W=1280; NESTED_H=720; FPS_MODE=30; GS_REFRESH=60
    P3_MAX=1401600; P7_MAX=1478400; GPU_GOV=simple_ondemand; GPU_MIN=220000000; GPU_MAX=615000000
    ;;
  720p-45)
    CEMU_RES="1280x720 (HD, Default)"; NESTED_W=1280; NESTED_H=720; FPS_MODE=45; GS_REFRESH=120
    P3_MAX=2054400; P7_MAX=2092800; GPU_GOV=performance; GPU_MIN=220000000; GPU_MAX=680000000
    ;;
  900p-30)
    CEMU_RES="1600x900 (HD+)"; NESTED_W=1600; NESTED_H=900; FPS_MODE=30; GS_REFRESH=60
    P3_MAX=1401600; P7_MAX=1478400; GPU_GOV=simple_ondemand; GPU_MIN=220000000; GPU_MAX=680000000
    ;;
  native-30|1080p-30)
    CEMU_RES="1920x1080 (Full HD)"; NESTED_W=1920; NESTED_H=1080; FPS_MODE=30; GS_REFRESH=60
    P3_MAX=1401600; P7_MAX=1478400; GPU_GOV=simple_ondemand; GPU_MIN=220000000; GPU_MAX=680000000
    ;;
  *)
    echo "unknown host-control profile: $PROFILE" >&2
    exit 2
    ;;
esac

case "$FPS_MODE" in
  30) FPS_LIMIT="30FPS Limit"; FRAMERATE_LIMIT="30FPS (ideal for 240/120/60Hz displays)" ;;
  45) FPS_LIMIT="45FPS Limit"; FRAMERATE_LIMIT="40FPS (ideal for 240/120/60Hz displays)" ;;
  *) echo "unsupported FPS_MODE: $FPS_MODE" >&2; exit 3 ;;
esac

mkdir -p "$RUN_DIR" "$(dirname "$MANGOHUD_CONF")"
cat > "$MANGOHUD_CONF" <<EOF
legacy_layout=0
fps
frametime
frame_timing
cpu_stats
gpu_stats
gpu_temp
cpu_temp
ram
vram
io_read
io_write
position=top-left
font_size=24
background_alpha=0.45
round_corners=8
output_folder=$RUN_DIR
autostart_log=1
log_duration=${HOST_CEMU_LOG_DURATION:-900}
EOF

python3 - <<PY
from pathlib import Path
import re
p=Path("$SETTINGS")
xml=p.read_text()
xml=re.sub(r"(<category>Resolution</category>\\s*<preset>)[^<]+(</preset>)", r"\\g<1>$CEMU_RES\\2", xml, count=1)
xml=re.sub(r"(<category>FPS Limit</category>\\s*<preset>)[^<]+(</preset>)", r"\\g<1>$FPS_LIMIT\\2", xml, count=1)
xml=re.sub(r"(<category>Framerate Limit</category>\\s*<preset>)[^<]+(</preset>)", r"\\g<1>$FRAMERATE_LIMIT\\2", xml, count=1)
xml=xml.replace("<open_pad>true</open_pad>", "<open_pad>false</open_pad>")
xml=xml.replace("<GX2DrawdoneSync>true</GX2DrawdoneSync>", "<GX2DrawdoneSync>false</GX2DrawdoneSync>")
xml=xml.replace("<vkAccurateBarriers>true</vkAccurateBarriers>", "<vkAccurateBarriers>false</vkAccurateBarriers>")
xml=xml.replace("<VSync>1</VSync>", "<VSync>0</VSync>")
p.write_text(xml)
PY

[ -f /storage/.config/Cemu/controllerProfiles/wii_u_pro_controller.xml ] && \
  cp /storage/.config/Cemu/controllerProfiles/wii_u_pro_controller.xml /storage/.config/Cemu/controllerProfiles/controller0.xml

echo schedutil > "$P3/scaling_governor" 2>/dev/null || echo ondemand > "$P3/scaling_governor" 2>/dev/null || true
echo schedutil > "$P7/scaling_governor" 2>/dev/null || echo ondemand > "$P7/scaling_governor" 2>/dev/null || true
echo "$P3_MAX" > "$P3/scaling_max_freq" 2>/dev/null || true
echo "$P7_MAX" > "$P7/scaling_max_freq" 2>/dev/null || true
echo "$GPU_GOV" > "$GPU/governor" 2>/dev/null || true
echo "$GPU_MIN" > "$GPU/min_freq" 2>/dev/null || true
echo "$GPU_MAX" > "$GPU/max_freq" 2>/dev/null || true

rm -f /storage/.config/Cemu/share/log.txt "$LOG"

# In thin-host mode the Wayland compositor runs in the guest mount namespace.
# Host controls can still connect through the guest process' /proc root path.
# Prefer an explicitly valid XDG_RUNTIME_DIR, then the old compatibility path,
# then the live guest namespace path.
if [ ! -S "${XDG_RUNTIME_DIR:-}/wayland-1" ] && [ -S /var/run/0-runtime-dir/wayland-1 ]; then
  XDG_RUNTIME_DIR=/var/run/0-runtime-dir
fi
if [ ! -S "${XDG_RUNTIME_DIR:-}/wayland-1" ]; then
  main="$(systemctl show -p MainPID --value rocknix-guest-v2.service 2>/dev/null || true)"
  child=""
  if [ -n "$main" ] && [ "$main" != "0" ]; then
    child="$(pgrep -P "$main" 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$child" ] && [ -S "/proc/$child/root/run/user/0/wayland-1" ]; then
    XDG_RUNTIME_DIR="/proc/$child/root/run/user/0"
  fi
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export DISPLAY="${DISPLAY:-:0.0}"
export GDK_BACKEND="${GDK_BACKEND:-wayland}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-pulseaudio}"
export HOME="${HOME:-/storage}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/storage/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/storage/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/storage/.cache}"

{
  echo "host-control launch: $(date -Iseconds)"
  echo "profile=$PROFILE cemu_res=$CEMU_RES fps=$FPS_MODE nested=${NESTED_W}x${NESTED_H} refresh=$GS_REFRESH"
  echo "RUN_DIR=$RUN_DIR"
  echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=$DISPLAY GDK_BACKEND=$GDK_BACKEND"
  echo "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_DATA_HOME=$XDG_DATA_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME"
  echo "ROM=$ROM"
} > "$RUN_DIR/host-control-contract.txt"

HOST_CEMU_CMD=${HOST_CEMU_CMD:-/usr/bin/cemu}
if [ "${HOST_CEMU_USE_START_SCRIPT:-0}" = "1" ]; then
  HOST_CEMU_CMD=/usr/bin/start_cemu.sh
fi

if [ "${HOST_CEMU_USE_GAMESCOPE:-1}" = "1" ]; then
  nohup gamescope --backend sdl -f --force-windows-fullscreen \
    -W "$OUT_W" -H "$OUT_H" -w "$NESTED_W" -h "$NESTED_H" -r "$GS_REFRESH" \
    -S fit -F "$FILTER" --sharpness 5 \
    -- env MANGOHUD=1 MANGOHUD_CONFIGFILE="$MANGOHUD_CONF" mangohud "$HOST_CEMU_CMD" --verbose -g "$ROM" \
    >"$LOG" 2>&1 &
else
  nohup env MANGOHUD=1 MANGOHUD_CONFIGFILE="$MANGOHUD_CONF" mangohud "$HOST_CEMU_CMD" --verbose -g "$ROM" \
    >"$LOG" 2>&1 &
fi

sleep 10
CEMU_PID="$(find_cemu_pid || true)"
if [ -n "$CEMU_PID" ]; then
  for tid in $(ls /proc/$CEMU_PID/task); do taskset -p 0xF8 "$tid" >/dev/null 2>&1 || true; done
  echo "$P3_MAX" > "$P3/scaling_max_freq" 2>/dev/null || true
  echo "$P7_MAX" > "$P7/scaling_max_freq" 2>/dev/null || true
  echo "$GPU_MAX" > "$GPU/max_freq" 2>/dev/null || true
fi

echo "host-control Cemu PID: ${CEMU_PID:-none}" | tee -a "$RUN_DIR/host-control-contract.txt"
[ -n "$CEMU_PID" ] || exit 4
