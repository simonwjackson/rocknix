#!/run/current-system/sw/bin/bash
# Launch a caller-selected guest Cemu binary through the normal Layer 14
# Cemu environment setup. Intended for build-parity A/B tests.
set -eu

if [ -z "${CEMU_BIN:-}" ]; then
  echo "usage: CEMU_BIN=/nix/store/.../bin/Cemu start_cemu_guest_candidate.sh <rom> [system]" >&2
  exit 2
fi

if [ ! -x "$CEMU_BIN" ]; then
  echo "CEMU_BIN is not executable: $CEMU_BIN" >&2
  exit 127
fi

export CEMU_BIN
exec /storage/.guest/start_cemu_guest.sh "$@"
