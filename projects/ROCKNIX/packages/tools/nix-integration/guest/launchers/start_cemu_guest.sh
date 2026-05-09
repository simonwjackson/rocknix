#!/run/current-system/sw/bin/bash
# Guest-native cemu launcher for the Layer 14 Nix guest.
# Adapted from /usr/bin/start_cemu.sh but:
#   - uses the nix-built cemu (no /usr/bin/cemu)
#   - skips host's /etc/profile sourcing
#   - skips set_kill (ROCKNIX rcompat helper)
#   - skips host mime-db bootstrap (cemu doesn't strictly need it)
# Sets up the canonical cemu home symlinks if missing, then execs cemu
# with the requested ROM. Designed to be a drop-in replacement for
# /usr/bin/start_cemu.sh inside the guest.
set -eu

# Use latest nix-built cemu (with screensaver-noop-linux patch).
CEMU=/nix/store/wl4g8jjlw6pck4sh4ayah9pdl03z8brp-cemu-2.999.0/bin/Cemu

ROM="${1:-}"
[ -z "$ROM" ] && { echo "usage: start_cemu_guest.sh <rom> [system]"; exit 2; }

CEMU_CONFIG_ROOT=/storage/.config/Cemu
CEMU_HOME_CONFIG="${CEMU_CONFIG_ROOT}/share"
CEMU_HOME_LOCAL=/storage/.local/share/Cemu
CEMU_HOME_ONLINE="${CEMU_HOME_CONFIG}/online"
CEMU_HOME_MLC01="${CEMU_HOME_CONFIG}/mlc01"
CEMU_HOME_KEYS="${CEMU_HOME_CONFIG}/keys"
CEMU_BIOS=/storage/roms/bios/cemu

mkdir -p "$CEMU_HOME_CONFIG"

# Cemu in nix doesn't follow XDG conventions; it expects either
# ~/.local/share/Cemu (writable settings + saves) or it'll create
# them. Mirror the host script's symlink scheme so settings.xml is
# read from CEMU_HOME_CONFIG.
if [ -d "$CEMU_HOME_LOCAL" ] && [ ! -L "$CEMU_HOME_LOCAL" ]; then
  cp -rf "$CEMU_HOME_LOCAL"/* "$CEMU_HOME_CONFIG"/ 2>/dev/null || true
  rm -rf "$CEMU_HOME_LOCAL"
fi
[ -L "$CEMU_HOME_LOCAL" ] || { mkdir -p "$(dirname "$CEMU_HOME_LOCAL")"; ln -sfn "$CEMU_HOME_CONFIG" "$CEMU_HOME_LOCAL"; }

for sub in online mlc01 keys; do
  src="${CEMU_HOME_CONFIG}/${sub}"
  dst="${CEMU_BIOS}/${sub}"
  mkdir -p "$dst"
  if [ -d "$src" ] && [ ! -L "$src" ]; then
    mv "$src"/* "$dst"/ 2>/dev/null || true
    rm -rf "$src"
  fi
  [ -L "$src" ] || ln -sfn "$dst" "$src"
done

# Settings.xml is at $CEMU_HOME_CONFIG/settings.xml -- but our binds
# put it at $CEMU_CONFIG_ROOT/settings.xml. Make sure the share/ dir
# also has it (cemu reads from share/).
if [ -f "${CEMU_CONFIG_ROOT}/settings.xml" ] && [ ! -e "${CEMU_HOME_CONFIG}/settings.xml" ]; then
  ln -sf "${CEMU_CONFIG_ROOT}/settings.xml" "${CEMU_HOME_CONFIG}/settings.xml"
fi

# Audio + display env -- inherit from caller; only fill defaults
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-pulseaudio}"
# nixpkgs SDL2 is sdl2-compat (SDL3 shim); SDL3's screensaver-inhibit
# path crashes in C++ regex code on first ROM load. Tell SDL to skip
# the inhibit entirely.
export SDL_VIDEO_ALLOW_SCREENSAVER=1
export SDL_HINT_VIDEO_ALLOW_SCREENSAVER=1
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export HOME="${HOME:-/storage}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/storage/.cache}"

# Force HOME to /storage so cemu's XDG paths point at shared config,
# regardless of caller env (sway-kiosk inherits HOME=/root).
export HOME=/storage
export XDG_CONFIG_HOME=/storage/.config
export XDG_DATA_HOME=/storage/.local/share

# Capture stdout/stderr so we can see what cemu prints. Append, not
# overwrite, so multi-launch sessions still leave a trail.
LOG_OUT=/storage/.guest/runs/cemu-stdout.log
mkdir -p "$(dirname "$LOG_OUT")"
echo "[$(date)] launching cemu (nix) with ROM: $ROM" | tee -a "$LOG_OUT" >&2
exec >>"$LOG_OUT" 2>&1
exec "$CEMU" --verbose -f -g "$ROM"
