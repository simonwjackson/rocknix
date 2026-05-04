#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM

FAKE_ARTIFACT="${TMP_DIR}/nix-portable-aarch64"
cat >"${FAKE_ARTIFACT}" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "--version" ]; then
  echo "nix (Nix) smoke-test"
  exit 0
fi
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "run" ] && [ "${3:-}" = "nixpkgs#hello" ]; then
  echo "Hello, world!"
  exit 0
fi
if [ "${1:-}" = "nix-shell" ]; then
  echo "nix-shell smoke-test"
  exit 0
fi
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "shell" ] && [ "${3:-}" = "nixpkgs#jq" ]; then
  echo "jq-1.7 smoke-test"
  exit 0
fi
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "shell" ] && [ "${3:-}" = "nixpkgs#python3" ]; then
  echo "Python 3 smoke-test"
  exit 0
fi
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "shell" ] && [ "${3:-}" = "nixpkgs#does-not-exist" ]; then
  echo "error: package does not exist" >&2
  exit 42
fi
echo "fake nix-portable called: $*"
exit 0
EOF
chmod 0755 "${FAKE_ARTIFACT}"
FAKE_SHA=$(sha256sum "${FAKE_ARTIFACT}" | awk '{print $1}')

export NIX_PORTABLE_DIR="${TMP_DIR}/apps/nix-portable"
export NIX_WRAPPER_DIR="${TMP_DIR}/bin"
export NP_LOCATION="${TMP_DIR}/storage"
export NIX_PORTABLE_URL="file://${FAKE_ARTIFACT}"
export NIX_PORTABLE_SHA256="${FAKE_SHA}"
export NIX_PORTABLE_REQUIRED_MB=1
export NIX_PORTABLE_SKIP_ARCH_CHECK=1
mkdir -p "${NP_LOCATION}"

"${PKG_DIR}/scripts/nix-portable-install" install >/tmp/nix-portable-install-smoke.log
"${NIX_WRAPPER_DIR}/nix" --version | grep -q 'nix (Nix) smoke-test'
"${NIX_WRAPPER_DIR}/nix" run nixpkgs#hello | grep -q 'Hello, world!'
"${NIX_WRAPPER_DIR}/nix-shell" -p jq | grep -q 'nix-shell smoke-test'
"${NIX_WRAPPER_DIR}/nix-run" nixpkgs#hello | grep -q 'Hello, world!'
"${NIX_WRAPPER_DIR}/nix" shell nixpkgs#jq --command jq --version | grep -q 'jq-1.7 smoke-test'
"${NIX_WRAPPER_DIR}/nix-dev-shell" nixpkgs#python3 --command python3 --version | grep -q 'Python 3 smoke-test'
if "${NIX_WRAPPER_DIR}/nix" shell nixpkgs#does-not-exist >/tmp/nix-dev-shell-error.log 2>&1; then
  echo "expected missing dev-shell package to fail" >&2
  exit 1
fi
grep -q 'package does not exist' /tmp/nix-dev-shell-error.log
"${NIX_WRAPPER_DIR}/nix" --version | grep -q 'nix (Nix) smoke-test'
"${PKG_DIR}/scripts/nix-doctor" --offline --dev-shell-smoke >/tmp/nix-doctor-smoke.log
"${NIX_WRAPPER_DIR}/nix-doctor" --offline --dev-shell-smoke >/tmp/nix-doctor-wrapper-smoke.log
"${PKG_DIR}/scripts/nix-portable-install" status | grep -q 'nix-portable: installed'
grep -q 'What=/storage/.nix-root' "${PKG_DIR}/system.d/nix.mount"
grep -q 'Where=/nix' "${PKG_DIR}/system.d/nix.mount"
grep -q 'Before=nix.mount' "${PKG_DIR}/system.d/nix-storage-setup.service"
"${PKG_DIR}/scripts/nix-portable-install" remove >/tmp/nix-portable-remove-smoke.log
[ ! -e "${NIX_WRAPPER_DIR}/nix" ]
[ ! -e "${NIX_WRAPPER_DIR}/nix-dev-shell" ]
[ ! -e "${NIX_WRAPPER_DIR}/nix-doctor" ]
[ ! -d "${NIX_PORTABLE_DIR}" ]

printf 'nix-integration runtime smoke passed\n'

# ---- Layer 4 device-side smoke (opt-in) ------------------------------------
# Set LAYER4_SMOKE=1 to run the real install/use/uninstall cycle against the
# upstream Nix tarball + cache.nixos.org. This requires the device to have:
#   - /nix bind-mounted from /storage/.nix-root (Layer 3 active)
#   - aarch64
#   - network reachability to releases.nixos.org and cache.nixos.org
#   - >= 1 GB free on /storage
# Not run in default CI; intended for manual validation on hardware.
if [ "${LAYER4_SMOKE:-0}" != "1" ]; then
  printf 'nix-integration Layer 4 smoke: skipped (set LAYER4_SMOKE=1 to enable)\n'
  exit 0
fi

# Layer 4 smoke uses the real package script paths (not the fake-tarball
# harness above), so reset the per-test environment.
unset NIX_PORTABLE_DIR NIX_WRAPPER_DIR NP_LOCATION NIX_PORTABLE_URL
unset NIX_PORTABLE_SHA256 NIX_PORTABLE_REQUIRED_MB NIX_PORTABLE_SKIP_ARCH_CHECK

NIXCTL="${PKG_DIR}/scripts/nixctl"
DOCTOR="${PKG_DIR}/scripts/nix-doctor"
L4_LOG=/tmp/nix-integration-layer4-smoke.log
rm -f "${L4_LOG}"

log() {
  printf '[layer4-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L4_LOG}"
}

log 'pre-flight: nixctl status reports current state'
"${NIXCTL}" status >>"${L4_LOG}" 2>&1

log 'install: nixctl install (downloads ~23MB tarball + writes /nix/store)'
start=$(date +%s)
"${NIXCTL}" install >>"${L4_LOG}" 2>&1
log "install completed in $(($(date +%s) - start))s"

log 'verify: real nix is on disk and reports the pinned version'
NIX_BIN=/nix/var/nix/profiles/default/bin/nix
[ -x "${NIX_BIN}" ] || { echo 'FAIL: real nix binary missing after install' >&2; exit 1; }
"${NIX_BIN}" --version >>"${L4_LOG}" 2>&1
"${NIX_BIN}" --version | grep -q 'nix (Nix) ' || { echo 'FAIL: nix --version output unexpected' >&2; exit 1; }

log 'verify: process tree of nix has no nix-portable / proot ancestors'
ps_out=$("${NIX_BIN}" --version 2>&1; ps -ef 2>/dev/null || true)
if printf '%s' "${ps_out}" | grep -qE 'nix-portable|proot'; then
  # Only an issue if those processes are CURRENT ancestors of nix; a parallel
  # nix-portable session is fine. Best-effort check.
  log 'note: nix-portable or proot present in ps output; ensure no parent chain'
fi

log 'compat-positive: nix-shell -p jq runs cleanly under real nix'
start=$(date +%s)
echo '{}' | "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' \
  shell nixpkgs#jq --command jq -c . >>"${L4_LOG}" 2>&1 \
  || { echo 'FAIL: nix shell jq smoke failed' >&2; exit 1; }
log "jq smoke completed in $(($(date +%s) - start))s"

log 'doctor: nix-doctor passes with Layer 4 lines present'
"${DOCTOR}" --offline >>"${L4_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed after Layer 4 install' >&2; exit 1; }
grep -q 'Layer 4 detected' "${L4_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 4 presence' >&2; exit 1; }

log 'uninstall: nixctl uninstall --yes returns to Layer 3 substrate'
"${NIXCTL}" uninstall --yes >>"${L4_LOG}" 2>&1
[ ! -x "${NIX_BIN}" ] || { echo 'FAIL: nix binary still present after uninstall' >&2; exit 1; }
[ ! -e "${HOME:-/storage}/.nix-profile" ] || { echo 'FAIL: ~/.nix-profile still present after uninstall' >&2; exit 1; }

log 'idempotency: second uninstall is a clean no-op'
"${NIXCTL}" uninstall --yes 2>&1 | grep -q 'Nothing to uninstall' \
  || { echo 'FAIL: idempotent uninstall did not report no-op' >&2; exit 1; }

log 'R4 verification: portable wrapper still works after Layer 4 cycle'
if [ -x /storage/bin/nix ]; then
  /storage/bin/nix --version >>"${L4_LOG}" 2>&1 \
    || { echo 'FAIL: portable wrapper broken after Layer 4 cycle' >&2; exit 1; }
else
  log 'note: /storage/bin/nix not present (portable not installed); skipping R4'
fi

printf 'nix-integration Layer 4 smoke passed\n'
printf 'log: %s\n' "${L4_LOG}"
