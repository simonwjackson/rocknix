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

# Compatibility adapter around the package-owned entry point. The product path
# is the main-space NixOS system package from nix-sm8550 (`bin/cemu`), not the
# real binary. CEMU_BIN remains a rollback/diagnostic override; the promoted
# profile is now a fallback for older live guests that have not switched yet.
# If an override points at `bin/Cemu` and the same output has `bin/cemu`,
# normalize back to the package wrapper so Vulkan loader setup stays
# package-owned.
SYSTEM_CEMU=${CEMU_SYSTEM_BIN:-/run/current-system/sw/bin/cemu}
PROMOTED_CEMU=${CEMU_PROMOTED_BIN:-/nix/var/nix/profiles/per-user/root/cemu-promoted/bin/cemu}
REQUESTED_CEMU=${CEMU_BIN:-$SYSTEM_CEMU}
if [ -z "${CEMU_BIN:-}" ] && [ ! -x "$REQUESTED_CEMU" ] && [ -x "$PROMOTED_CEMU" ]; then
  REQUESTED_CEMU=$PROMOTED_CEMU
fi
CEMU=$REQUESTED_CEMU
if [ "$(basename "$CEMU")" != "cemu" ] && [ -x "$(dirname "$CEMU")/cemu" ]; then
  CEMU="$(dirname "$CEMU")/cemu"
fi

ROM="${1:-}"
[ -z "$ROM" ] && { echo "usage: start_cemu_guest.sh <rom> [system]"; exit 2; }
if [ ! -x "$CEMU" ]; then
  if [ -z "${CEMU_BIN:-}" ]; then
    echo "System Cemu package is missing or not executable: $SYSTEM_CEMU" >&2
    echo "Rebuild/switch the main-space guest with nix-sm8550, promote a fallback with remote-cemu-promote.sh, or pass CEMU_BIN=/nix/store/.../bin/Cemu for diagnostics." >&2
  else
    echo "Cemu binary is not executable: $CEMU" >&2
  fi
  exit 127
fi

# Resolve profile/symlinked binaries back to the real store output before
# reading package metadata. Nix profile user-envs do not reliably expose
# the direct package's data files themselves.
CEMU_REAL="$(readlink -f "$CEMU" 2>/dev/null || printf '%s' "$CEMU")"
CEMU_OUT="$(dirname "$(dirname "$CEMU_REAL")")"
CEMU_DEFAULT_SETTINGS="${CEMU_OUT}/share/Cemu/config/SM8550/settings.xml"

# Display/audio/XDG defaults are owned by the Layer 14 guest session. A normal
# product launch reaches this script through swaymsg and therefore inherits
# them from rocknix-sway-kiosk. Debug shells must provide them explicitly rather
# than silently writing to root paths.
: "${XDG_RUNTIME_DIR:?missing XDG_RUNTIME_DIR; launch from guest session or export it explicitly}"
: "${WAYLAND_DISPLAY:?missing WAYLAND_DISPLAY; launch from guest session or export it explicitly}"
: "${HOME:?missing HOME; launch from guest session or export it explicitly}"
: "${XDG_CONFIG_HOME:?missing XDG_CONFIG_HOME; launch from guest session or export it explicitly}"
: "${XDG_DATA_HOME:?missing XDG_DATA_HOME; launch from guest session or export it explicitly}"
: "${XDG_CACHE_HOME:?missing XDG_CACHE_HOME; launch from guest session or export it explicitly}"
: "${SDL_AUDIODRIVER:?missing SDL_AUDIODRIVER; launch from guest session or export it explicitly}"

# ROCKNIX-era /storage config/save/key compatibility is a named guest adapter,
# not package-owned runtime logic. It is idempotent and only seeds fresh state.
LAUNCHER_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CEMU_DEFAULT_SETTINGS="$CEMU_DEFAULT_SETTINGS" "$LAUNCHER_DIR/cemu-storage-adapter.sh" >&2

# Capture stdout/stderr so we can see what cemu prints. Append, not
# overwrite, so multi-launch sessions still leave a trail.
LOG_OUT=/storage/.guest/runs/cemu-stdout.log
mkdir -p "$(dirname "$LOG_OUT")"
echo "[$(date)] launching cemu (guest) requested_binary=$REQUESTED_CEMU binary=$CEMU real_binary=$CEMU_REAL ROM: $ROM" | tee -a "$LOG_OUT" >&2
exec >>"$LOG_OUT" 2>&1
exec "$CEMU" --verbose -f -g "$ROM"
