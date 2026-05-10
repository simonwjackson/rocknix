#!/run/current-system/sw/bin/bash
# Launch Cemu inside Nix gamescope, matching the host BOTW FSR pipeline shape.
set -eu

export PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin:$PATH
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-pulseaudio}"
export SDL_VIDEO_ALLOW_SCREENSAVER=1
export SDL_HINT_VIDEO_ALLOW_SCREENSAVER=1
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export HOME=/storage
export XDG_CONFIG_HOME=/storage/.config
export XDG_DATA_HOME=/storage/.local/share
export XDG_CACHE_HOME=/storage/.cache

ROM="${1:-}"
[ -n "$ROM" ] || { echo "usage: start_cemu_guest_gamescope.sh <rom>" >&2; exit 2; }

GS_OUT_W="${GS_OUT_W:-1920}"
GS_OUT_H="${GS_OUT_H:-1080}"
GS_NESTED_W="${GS_NESTED_W:-640}"
GS_NESTED_H="${GS_NESTED_H:-360}"
GS_REFRESH="${GS_REFRESH:-60}"
GS_FILTER="${GS_FILTER:-fsr}"
GS_SHARPNESS="${GS_SHARPNESS:-5}"
GS_EXTRA="${GS_EXTRA:-}"
CEMU_START="${CEMU_START:-/storage/.guest/start_cemu_guest.sh}"

if ! command -v gamescope >/dev/null 2>&1; then
  echo "gamescope is not installed in the guest profile" >&2
  echo "run: nix profile install nixpkgs#gamescope" >&2
  exit 127
fi

LOG_OUT=/storage/.guest/runs/cemu-stdout.log
mkdir -p "$(dirname "$LOG_OUT")"
echo "[$(date)] launching gamescope ${GS_NESTED_W}x${GS_NESTED_H}->${GS_OUT_W}x${GS_OUT_H} ${GS_FILTER} cemu with ROM: $ROM" | tee -a "$LOG_OUT" >&2
exec >>"$LOG_OUT" 2>&1

if [ "${USE_MANGOHUD:-0}" = "1" ]; then
  export MANGOHUD=1
  export MANGOHUD_CONFIGFILE=${MANGOHUD_CONFIGFILE:-/storage/.config/MangoHud/MangoHud.conf}
  command -v mangohud >/dev/null 2>&1 || { echo "mangohud missing" >&2; exit 127; }
  exec gamescope --backend sdl -f --force-windows-fullscreen \
    -W "$GS_OUT_W" -H "$GS_OUT_H" -w "$GS_NESTED_W" -h "$GS_NESTED_H" \
    -r "$GS_REFRESH" -S fit -F "$GS_FILTER" --sharpness "$GS_SHARPNESS" $GS_EXTRA -- \
    env MANGOHUD=1 MANGOHUD_CONFIGFILE="$MANGOHUD_CONFIGFILE" mangohud "$CEMU_START" "$ROM"
fi

exec gamescope --backend sdl -f --force-windows-fullscreen \
  -W "$GS_OUT_W" -H "$GS_OUT_H" -w "$GS_NESTED_W" -h "$GS_NESTED_H" \
  -r "$GS_REFRESH" -S fit -F "$GS_FILTER" --sharpness "$GS_SHARPNESS" $GS_EXTRA -- \
  "$CEMU_START" "$ROM"
