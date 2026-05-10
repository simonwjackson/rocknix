#!/run/current-system/sw/bin/bash
# Launch the normal guest Cemu wrapper under Nix MangoHud.
set -eu

export PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin:$PATH
export MANGOHUD=1
export MANGOHUD_CONFIGFILE=${MANGOHUD_CONFIGFILE:-/storage/.config/MangoHud/MangoHud.conf}

if ! command -v mangohud >/dev/null 2>&1; then
  echo "mangohud is not installed in the guest profile" >&2
  echo "run: nix profile install nixpkgs#mangohud" >&2
  exit 127
fi

CEMU_START="${CEMU_START:-/storage/.guest/start_cemu_guest.sh}"
exec mangohud "$CEMU_START" "$@"
