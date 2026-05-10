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

# Default to the promoted direct ROCKNIX package profile. This avoids
# baking a stale /nix/store hash into the product launcher while keeping
# CEMU_BIN available for parity/rollback diagnostics.
PROMOTED_CEMU=${CEMU_PROMOTED_BIN:-/nix/var/nix/profiles/per-user/root/cemu-promoted/bin/Cemu}
CEMU=${CEMU_BIN:-$PROMOTED_CEMU}

ROM="${1:-}"
[ -z "$ROM" ] && { echo "usage: start_cemu_guest.sh <rom> [system]"; exit 2; }
if [ ! -x "$CEMU" ]; then
  if [ -z "${CEMU_BIN:-}" ] && [ "$CEMU" = "$PROMOTED_CEMU" ]; then
    echo "Promoted Cemu profile is missing or not executable: $PROMOTED_CEMU" >&2
    echo "Promote an imported direct package with remote-cemu-promote.sh, or pass CEMU_BIN=/nix/store/.../bin/Cemu for diagnostics." >&2
  else
    echo "Cemu binary is not executable: $CEMU" >&2
  fi
  exit 127
fi

CEMU_CONFIG_ROOT=/storage/.config/Cemu
CEMU_HOME_CONFIG="${CEMU_CONFIG_ROOT}/share"
CEMU_HOME_LOCAL=/storage/.local/share/Cemu
CEMU_HOME_ONLINE="${CEMU_HOME_CONFIG}/online"
CEMU_HOME_MLC01="${CEMU_HOME_CONFIG}/mlc01"
CEMU_HOME_KEYS="${CEMU_HOME_CONFIG}/keys"
CEMU_BIOS=/storage/roms/bios/cemu

mkdir -p "$CEMU_HOME_CONFIG"

# A direct ROCKNIX-package Cemu output carries the same SM8550 default
# settings.xml that cemu-sa installs to /usr/config/Cemu. Seed only clean
# guests; never overwrite user/device-mutated settings.
# Resolve profile/symlinked binaries back to the real store output before
# reading package metadata. Nix profile user-envs do not reliably expose
# the direct package's nix-support evidence files themselves.
CEMU_REAL="$(readlink -f "$CEMU" 2>/dev/null || printf '%s' "$CEMU")"
CEMU_OUT="$(dirname "$(dirname "$CEMU_REAL")")"
CEMU_DEFAULT_SETTINGS="${CEMU_OUT}/share/Cemu/config/SM8550/settings.xml"
CEMU_VULKAN_LOADER_LIB_PATH="${CEMU_OUT}/nix-support/rocknix-cemu-build/vulkan-loader-lib-path"
if [ ! -f "${CEMU_CONFIG_ROOT}/settings.xml" ] && [ -f "$CEMU_DEFAULT_SETTINGS" ]; then
  cp "$CEMU_DEFAULT_SETTINGS" "${CEMU_CONFIG_ROOT}/settings.xml"
fi
if [ -f "$CEMU_VULKAN_LOADER_LIB_PATH" ]; then
  export LD_LIBRARY_PATH="$(cat "$CEMU_VULKAN_LOADER_LIB_PATH")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

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
echo "[$(date)] launching cemu (guest) binary=$CEMU real_binary=$CEMU_REAL ROM: $ROM" | tee -a "$LOG_OUT" >&2
exec >>"$LOG_OUT" 2>&1
exec "$CEMU" --verbose -f -g "$ROM"
