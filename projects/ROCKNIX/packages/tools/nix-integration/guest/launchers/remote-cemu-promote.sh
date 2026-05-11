#!/bin/sh
# remote-cemu-promote.sh -- promote an imported direct ROCKNIX Cemu package.
#
# Runs on the ROCKNIX host. The target Cemu closure must already be present in
# the Layer 14 guest Nix store. This script enters the guest namespace and
# installs the package output into a dedicated Nix profile so the normal guest
# launcher can use a stable path without baking a raw /nix/store hash into the
# product launcher.
set -eu

PATH=/run/current-system/sw/bin:/usr/bin:/bin:/storage/.guest:$PATH
export PATH

PROMOTED_PROFILE="${CEMU_PROMOTED_PROFILE:-/nix/var/nix/profiles/per-user/root/cemu-promoted}"
CEMU_BIN_INPUT="${1:-${CEMU_BIN:-}}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

usage() {
  cat >&2 <<EOF
usage: remote-cemu-promote.sh /nix/store/...-cemu-rocknix-package-.../bin/cemu
       remote-cemu-promote.sh /nix/store/...-cemu-rocknix-package-.../bin/Cemu

The closure must already be imported into the guest store. The promoted package-owned entry point is:
  ${PROMOTED_PROFILE}/bin/cemu
EOF
}

guest_pid() {
  main="$(systemctl show -p MainPID --value rocknix-guest-v2.service 2>/dev/null || true)"
  [ -n "$main" ] && [ "$main" != "0" ] || return 1
  pgrep -P "$main" 2>/dev/null | head -1
}

run_guest() {
  seconds="$1"
  shift
  gp="$(guest_pid)" || return 1
  timeout "$seconds" nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "$1"
}

quote_sh() {
  printf "%s" "$1" | sed "s/'/'\\''/g; 1s/^/'/; \$s/\$/'/"
}

[ -n "$CEMU_BIN_INPUT" ] || { usage; exit 2; }

cemu_q="$(quote_sh "$CEMU_BIN_INPUT")"
profile_q="$(quote_sh "$PROMOTED_PROFILE")"

log "promoting Cemu into guest profile: $PROMOTED_PROFILE"
run_guest 120 "set -eu
PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin
cemu=$cemu_q
profile=$profile_q
[ -x \"\$cemu\" ] || { echo \"Cemu binary is not executable in guest: \$cemu\" >&2; exit 127; }
real=\$(readlink -f \"\$cemu\" 2>/dev/null || printf '%s' \"\$cemu\")
out=\$(dirname \"\$(dirname \"\$real\")\")
[ -d \"\$out/nix-support/rocknix-cemu-build\" ] || { echo \"refusing to promote non-direct-package Cemu output: \$out\" >&2; exit 3; }
[ -f \"\$out/nix-support/rocknix-cemu-build/vulkan-loader-lib-path\" ] || { echo \"direct Cemu output lacks vulkan-loader-lib-path evidence: \$out\" >&2; exit 3; }
mkdir -p \"\$(dirname \"\$profile\")\"
nix profile install --profile \"\$profile\" \"\$out\"
[ -x \"\$profile/bin/cemu\" ] || { echo \"promotion did not produce package entry point \$profile/bin/cemu\" >&2; exit 4; }
[ -x \"\$profile/bin/Cemu\" ] || { echo \"promotion did not produce compatibility binary \$profile/bin/Cemu\" >&2; exit 4; }
promoted_real=\$(readlink -f \"\$profile/bin/cemu\" 2>/dev/null || true)
printf '%s\n' \
  \"profile=\$profile\" \
  \"cemu=\$profile/bin/cemu\" \
  \"compat_cemu=\$profile/bin/Cemu\" \
  \"source=\$out\" \
  \"real=\$promoted_real\" \
  \"vulkan_loader_lib_path=\$(cat \"\$out/nix-support/rocknix-cemu-build/vulkan-loader-lib-path\")\"
"
log "promotion complete: ${PROMOTED_PROFILE}/bin/cemu"
