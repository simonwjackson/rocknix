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

# Layer 5 profile contract: the profile.d snippet must expose the root Nix
# profile before Layer 4 and portable paths, and must be idempotent.
PROFILE_ENV="${TMP_DIR}/profile-env"
HOME="${TMP_DIR}/home" PATH="/usr/bin:/usr/sbin" /bin/sh -c \
  '. "'"${PKG_DIR}/profile.d/998-nix-integration.conf"'"; . "'"${PKG_DIR}/profile.d/998-nix-integration.conf"'"; printf "%s\n" "$PATH"' \
  >"${PROFILE_ENV}"
PROFILE_PATH=$(cat "${PROFILE_ENV}")
case "${PROFILE_PATH}" in
  "${TMP_DIR}/home/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/storage/bin:"*) ;;
  *) echo "FAIL: profile.d PATH order unexpected: ${PROFILE_PATH}" >&2; exit 1 ;;
esac
case "${PROFILE_PATH}" in
  *".nix-profile/bin"*".nix-profile/bin"*) echo "FAIL: profile.d duplicated .nix-profile path" >&2; exit 1 ;;
esac

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
mkdir -p "${TMP_DIR}/layer8-doctor-config"
printf 'experimental-features = nix-command flakes\nbuild-users-group =\n' >"${TMP_DIR}/layer8-doctor-config/nix.conf"
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline --dev-shell-smoke >/tmp/nix-doctor-smoke.log
grep -q 'Layer 8 daemon state: inactive' /tmp/nix-doctor-smoke.log
grep -q 'Layer 8 daemon eligibility:' /tmp/nix-doctor-smoke.log
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${NIX_WRAPPER_DIR}/nix-doctor" --offline --dev-shell-smoke >/tmp/nix-doctor-wrapper-smoke.log
"${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer8-nixctl-status.log
grep -q 'Layer 8 (experimental daemon) status' /tmp/nix-layer8-nixctl-status.log
grep -q 'fallback:   Layer 4 single-user/root Nix remains primary' /tmp/nix-layer8-nixctl-status.log
NIX_LAYER8_SYSTEMD_DIR="${PKG_DIR}/system.d" \
  "${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer8-unit-status.log
grep -q 'socket:     .*nix-daemon.socket' /tmp/nix-layer8-unit-status.log
grep -q 'service:    .*nix-daemon.service' /tmp/nix-layer8-unit-status.log
FAKE_NSPAWN="${TMP_DIR}/systemd-nspawn"
cat >"${FAKE_NSPAWN}" <<'EOF'
#!/bin/sh
echo 'systemd-nspawn smoke-test'
EOF
chmod 0755 "${FAKE_NSPAWN}"
mkdir -p "${TMP_DIR}/layer9-root/etc" "${TMP_DIR}/layer9-state"
NIX_LAYER9_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${TMP_DIR}/layer9-root" \
NIX_LAYER9_STATE_DIR="${TMP_DIR}/layer9-state" \
NIX_LAYER9_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer9-proof-ready-status.log
grep -q 'Layer 9 (nspawn guest proof) status' /tmp/nix-layer9-proof-ready-status.log
grep -q 'state:      proof-ready' /tmp/nix-layer9-proof-ready-status.log
grep -q 'fallback:   host Layers 4/8 remain the recovery path' /tmp/nix-layer9-proof-ready-status.log
NIX_LAYER9_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${TMP_DIR}/layer9-root" \
NIX_LAYER9_STATE_DIR="${TMP_DIR}/layer9-state" \
NIX_LAYER9_SKIP_KERNEL_CHECK=1 \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer9-doctor-proof-ready.log
grep -q 'Layer 9 nspawn guest state: proof-ready' /tmp/nix-layer9-doctor-proof-ready.log
grep -q 'Layer 9 nspawn eligibility: available: nspawn guest proof prerequisites present' /tmp/nix-layer9-doctor-proof-ready.log
NIX_LAYER9_NSPAWN_BIN="${TMP_DIR}/missing-nspawn" \
NIX_LAYER9_GUEST_ROOT="${TMP_DIR}/missing-root" \
NIX_LAYER9_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer9-unsupported-status.log
grep -q 'state:      unsupported' /tmp/nix-layer9-unsupported-status.log
mkdir -p "${TMP_DIR}/layer8-empty-config"
printf 'experimental-features = nix-command flakes\nbuild-users-group =\n' >"${TMP_DIR}/layer8-empty-config/nix.conf"
if NIX_LAYER8_SYSTEMD_DIR="${PKG_DIR}/system.d" \
  NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-empty-config/nix.conf" \
  "${PKG_DIR}/scripts/nixctl" daemon preflight >/tmp/nix-layer8-preflight.log 2>&1; then
  echo 'expected Layer 8 preflight to fail with empty build-users-group' >&2
  exit 1
fi
grep -q 'daemon preflight failed:' /tmp/nix-layer8-preflight.log
FAKE_SYSTEMCTL="${TMP_DIR}/systemctl"
cat >"${FAKE_SYSTEMCTL}" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${NIX_SYSTEMCTL_LOG}"
case "$1" in
  is-active) echo inactive; exit 3 ;;
  enable|disable|stop) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod 0755 "${FAKE_SYSTEMCTL}"
mkdir -p "${TMP_DIR}/layer8-rollback-state"
printf 'active\n' >"${TMP_DIR}/layer8-rollback-state/state"
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-rollback-state" \
NIX_SYSTEMCTL="${FAKE_SYSTEMCTL}" \
NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl.log" \
  "${PKG_DIR}/scripts/nixctl" daemon rollback >/tmp/nix-layer8-rollback.log
[ ! -e "${TMP_DIR}/layer8-rollback-state/state" ]
grep -q 'disable --now nix-daemon.socket' "${TMP_DIR}/systemctl.log"
grep -q 'stop nix-daemon.service' "${TMP_DIR}/systemctl.log"
grep -q 'Layer 8 daemon mode disabled' /tmp/nix-layer8-rollback.log
mkdir -p "${TMP_DIR}/layer8-active-state" "${TMP_DIR}/layer8-active-config"
printf 'active\n' >"${TMP_DIR}/layer8-active-state/state"
printf 'experimental-features = nix-command flakes\nbuild-users-group =\n' >"${TMP_DIR}/layer8-active-config/nix.conf"
if NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-active-state" \
  NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-active-config/nix.conf" \
  NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer8-active-missing.log 2>&1; then
  echo 'expected active Layer 8 state without prerequisites to fail doctor' >&2
  exit 1
fi
grep -q 'Layer 8 daemon active but prerequisites are missing' /tmp/nix-layer8-active-missing.log
mkdir -p "${TMP_DIR}/layer8-config"
printf 'build-users-group = nixbld\n' >"${TMP_DIR}/layer8-config/nix.conf"
printf 'nixbld:x:30000:nixbld1,nixbld2\n' >"${TMP_DIR}/layer8-config/group"
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-config/nix.conf" \
NIX_GROUP_FILE="${TMP_DIR}/layer8-config/group" \
NIX_LAYER8_SYSTEMD_DIR="${PKG_DIR}/system.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer8-build-group.log || true
grep -q 'Layer 8 build-users-group exists: nixbld' /tmp/nix-layer8-build-group.log
grep -q 'Layer 8 socket unit present: .*nix-daemon.socket' /tmp/nix-layer8-build-group.log
grep -q 'Layer 8 service unit present: .*nix-daemon.service' /tmp/nix-layer8-build-group.log
"${PKG_DIR}/scripts/nix-portable-install" status | grep -q 'nix-portable: installed'
grep -q 'What=/storage/.nix-root' "${PKG_DIR}/system.d/nix.mount"
grep -q 'Where=/nix' "${PKG_DIR}/system.d/nix.mount"
grep -q 'Before=nix.mount' "${PKG_DIR}/system.d/nix-storage-setup.service"
"${PKG_DIR}/scripts/nix-portable-install" remove >/tmp/nix-portable-remove-smoke.log
[ ! -e "${NIX_WRAPPER_DIR}/nix" ]
[ ! -e "${NIX_WRAPPER_DIR}/nix-dev-shell" ]
[ ! -e "${NIX_WRAPPER_DIR}/nix-doctor" ]
[ ! -d "${NIX_PORTABLE_DIR}" ]

# Layer 6 activation engine smoke against temp surfaces (safe for default CI).
L6_TMP="${TMP_DIR}/layer6"
L6_BUNDLE="${PKG_DIR}/tests/fixtures/layer6-user-env"
mkdir -p "${L6_TMP}/state" "${L6_TMP}/bin" "${L6_TMP}/profile.d"
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" preflight "${L6_BUNDLE}" >/tmp/nix-layer6-preflight-smoke.log
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" activate "${L6_BUNDLE}" >/tmp/nix-layer6-activate-smoke.log
[ -x "${L6_TMP}/bin/rocknix-layer6-smoke" ]
/bin/sh -c '. "'"${L6_TMP}/profile.d/999-rocknix-layer6-smoke"'"; "'"${L6_TMP}/bin/rocknix-layer6-smoke"'"' | grep -q 'rocknix-layer6-smoke:active'
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nixctl" status | grep -q 'Layer 6 (managed user environment) status'
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_PORTABLE_DIR="${NIX_PORTABLE_DIR}" \
NIX_WRAPPER_DIR="${NIX_WRAPPER_DIR}" \
NP_LOCATION="${NP_LOCATION}" \
NIX_PORTABLE_REQUIRED_MB=1 \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer6-doctor-smoke.log || true
# Doctor may fail because the fake portable layer was removed; assert Layer 6 checks ran.
grep -q 'Layer 6 state: active' /tmp/nix-layer6-doctor-smoke.log
printf 'user-file\n' >"${L6_TMP}/bin/rocknix-layer6-conflict"
mkdir -p "${L6_TMP}/conflict-bundle/files/bin"
printf '#!/bin/sh\necho conflict\n' >"${L6_TMP}/conflict-bundle/files/bin/rocknix-layer6-conflict"
chmod 0755 "${L6_TMP}/conflict-bundle/files/bin/rocknix-layer6-conflict"
printf 'bin|rocknix-layer6-conflict|files/bin/rocknix-layer6-conflict|0755\n' >"${L6_TMP}/conflict-bundle/manifest"
if NIX_LAYER6_STATE_DIR="${L6_TMP}/conflict-state" \
  NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" activate "${L6_TMP}/conflict-bundle" >/tmp/nix-layer6-conflict-smoke.log 2>&1; then
  echo 'expected Layer 6 conflict activation to fail' >&2
  exit 1
fi
grep -q 'target exists and is not owned by Layer 6' /tmp/nix-layer6-conflict-smoke.log
grep -q 'user-file' "${L6_TMP}/bin/rocknix-layer6-conflict"
mkdir -p "${L6_TMP}/empty-bundle"
: >"${L6_TMP}/empty-bundle/manifest"
if NIX_LAYER6_STATE_DIR="${L6_TMP}/empty-state" \
  NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" activate "${L6_TMP}/empty-bundle" >/tmp/nix-layer6-empty-smoke.log 2>&1; then
  echo 'expected Layer 6 empty activation to fail' >&2
  exit 1
fi
grep -q 'bundle manifest contains no activatable files' /tmp/nix-layer6-empty-smoke.log
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" deactivate >/tmp/nix-layer6-deactivate-smoke.log
[ ! -e "${L6_TMP}/bin/rocknix-layer6-smoke" ]
[ ! -e "${L6_TMP}/profile.d/999-rocknix-layer6-smoke" ]

# Layer 7 app experiment smoke against temp surfaces (safe for default CI).
L7_TMP="${TMP_DIR}/layer7"
L7_HOME="${L7_TMP}/home"
L7_BUNDLE="${PKG_DIR}/tests/fixtures/layer7-apps/browser"
mkdir -p "${L7_TMP}/state" "${L7_TMP}/bin" "${L7_TMP}/profile.d" "${L7_HOME}/.nix-profile/bin"
printf '#!/bin/sh\necho fake chromium\n' >"${L7_HOME}/.nix-profile/bin/chromium"
chmod 0755 "${L7_HOME}/.nix-profile/bin/chromium"
NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" activate "${L7_BUNDLE}" >/tmp/nix-layer7-activate-smoke.log
[ -x "${L7_TMP}/bin/rocknix-layer7-browser" ]
HOME="${L7_HOME}" \
ROCKNIX_LAYER7_BROWSER_STATE_DIR="${L7_HOME}/.local/share/nix-apps/layer7/browser" \
  "${L7_TMP}/bin/rocknix-layer7-browser" --check >/tmp/nix-layer7-launcher-check.log
grep -q 'rocknix-layer7-browser:ready' /tmp/nix-layer7-launcher-check.log
grep -q '.nix-profile/bin/chromium' /tmp/nix-layer7-launcher-check.log
if HOME="${L7_HOME}" \
  ROCKNIX_LAYER7_BROWSER_APP="missing-layer7-browser" \
  "${L7_TMP}/bin/rocknix-layer7-browser" --check >/tmp/nix-layer7-missing-check.log 2>&1; then
  echo 'expected Layer 7 missing app check to fail' >&2
  exit 1
fi
grep -q "Layer 7 app binary 'missing-layer7-browser' not found" /tmp/nix-layer7-missing-check.log
mkdir -p "${L7_TMP}/unsafe-bin"
printf '#!/bin/sh\necho unsafe chromium\n' >"${L7_TMP}/unsafe-bin/chromium"
chmod 0755 "${L7_TMP}/unsafe-bin/chromium"
if HOME="${L7_HOME}" \
  ROCKNIX_LAYER7_BROWSER_BIN_PATH="${L7_TMP}/unsafe-bin/chromium" \
  "${L7_TMP}/bin/rocknix-layer7-browser" --check >/tmp/nix-layer7-unsafe-bin.log 2>&1; then
  echo 'expected Layer 7 unsafe binary check to fail' >&2
  exit 1
fi
grep -q 'not Nix-backed' /tmp/nix-layer7-unsafe-bin.log
HOME="${L7_HOME}" \
NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer7-nixctl-status.log
grep -q 'Layer 7 (app/UI experiment) status' /tmp/nix-layer7-nixctl-status.log
grep -q 'origin:   Nix profile/store' /tmp/nix-layer7-nixctl-status.log
HOME="${L7_HOME}" \
NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_PORTABLE_DIR="${NIX_PORTABLE_DIR}" \
NIX_WRAPPER_DIR="${NIX_WRAPPER_DIR}" \
NP_LOCATION="${NP_LOCATION}" \
NIX_PORTABLE_REQUIRED_MB=1 \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer7-doctor-smoke.log || true
grep -q 'Layer 7 ready: launcher active with Nix-backed app binary' /tmp/nix-layer7-doctor-smoke.log
if HOME="${L7_HOME}" \
  NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
  NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
  NIX_LAYER7_APP_STATE_DIR="/storage/games-internal/roms/steam" \
  NIX_PORTABLE_DIR="${NIX_PORTABLE_DIR}" \
  NIX_WRAPPER_DIR="${NIX_WRAPPER_DIR}" \
  NP_LOCATION="${NP_LOCATION}" \
  NIX_PORTABLE_REQUIRED_MB=1 \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer7-unsafe-state.log 2>&1; then
  echo 'expected Layer 7 unsafe state path doctor check to fail' >&2
  exit 1
fi
grep -q 'Layer 7 app state path outside allowed experiment roots' /tmp/nix-layer7-unsafe-state.log
NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" deactivate >/tmp/nix-layer7-deactivate-smoke.log
[ ! -e "${L7_TMP}/bin/rocknix-layer7-browser" ]
[ ! -e "${L7_TMP}/profile.d/999-rocknix-layer7-browser" ]

printf 'nix-integration runtime smoke passed\n'

# ---- Layer 4 device-side smoke (opt-in) ------------------------------------
# Set LAYER4_SMOKE=1 to run the real install/use/uninstall cycle against the
# upstream Nix tarball + cache.nixos.org. This requires the device to have:
#   - /nix bind-mounted from /storage/.nix-root (Layer 3 active)
#   - aarch64
#   - network reachability to releases.nixos.org and cache.nixos.org
#   - >= 1 GB free on /storage
# Not run in default CI; intended for manual validation on hardware.
if [ "${LAYER4_SMOKE:-0}" != "1" ] && [ "${LAYER5_SMOKE:-0}" != "1" ] && [ "${LAYER6_SMOKE:-0}" != "1" ] && [ "${LAYER7_SMOKE:-0}" != "1" ] && [ "${LAYER8_SMOKE:-0}" != "1" ] && [ "${LAYER9_SMOKE:-0}" != "1" ]; then
  printf 'nix-integration Layer 4 smoke: skipped (set LAYER4_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 5 smoke: skipped (set LAYER5_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 6 smoke: skipped (set LAYER6_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 7 smoke: skipped (set LAYER7_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 8 smoke: skipped (set LAYER8_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 9 smoke: skipped (set LAYER9_SMOKE=1 to enable)\n'
  exit 0
fi

# Device-side smokes use the real package script paths (not the fake-tarball
# harness above), so reset the per-test environment.
unset NIX_PORTABLE_DIR NIX_WRAPPER_DIR NP_LOCATION NIX_PORTABLE_URL
unset NIX_PORTABLE_SHA256 NIX_PORTABLE_REQUIRED_MB NIX_PORTABLE_SKIP_ARCH_CHECK

NIXCTL="${PKG_DIR}/scripts/nixctl"
DOCTOR="${PKG_DIR}/scripts/nix-doctor"
export NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate"
L4_LOG=/tmp/nix-integration-layer4-smoke.log
rm -f "${L4_LOG}"

log() {
  printf '[layer4-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L4_LOG}"
}

if [ "${LAYER4_SMOKE:-0}" = "1" ]; then
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
fi

# ---- Layer 5 device-side smoke (opt-in) ------------------------------------
# Set LAYER5_SMOKE=1 to validate persistent Nix profiles for CLI tools on
# hardware. Requires Layer 4 real Nix to already be installed. The default
# package is nixpkgs#hello because it is small and low-conflict.
if [ "${LAYER5_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER6_SMOKE:-0}" != "1" ] && [ "${LAYER7_SMOKE:-0}" != "1" ] && [ "${LAYER8_SMOKE:-0}" != "1" ] && [ "${LAYER9_SMOKE:-0}" != "1" ]; then
    exit 0
  fi
else

L5_LOG=/tmp/nix-integration-layer5-smoke.log
L5_PACKAGE="${LAYER5_SMOKE_PACKAGE:-nixpkgs#hello}"
L5_NAME="${LAYER5_SMOKE_NAME:-hello}"
L5_BIN="${LAYER5_SMOKE_BIN:-hello}"
rm -f "${L5_LOG}"

log5() {
  printf '[layer5-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L5_LOG}"
}

NIX_BIN=/nix/var/nix/profiles/default/bin/nix
[ -x "${NIX_BIN}" ] || { echo 'FAIL: Layer 5 smoke requires Layer 4 real Nix' >&2; exit 1; }
[ -d /nix ] || { echo 'FAIL: /nix missing' >&2; exit 1; }
awk '$2 == "/nix" {found=1} END {exit !found}' /proc/mounts 2>/dev/null \
  || { echo 'FAIL: /nix is not mounted' >&2; exit 1; }

log5 "pre-flight: inspect existing profile"
preexisting=0
if "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' profile list 2>/tmp/layer5-profile-list.err | grep -q "Name:[[:space:]]*${L5_NAME}"; then
  preexisting=1
  log5 "${L5_NAME} is already present; smoke will not remove it"
fi

if [ "${LAYER5_REBOOT_VERIFY:-}" = "verify" ]; then
  log5 'reboot verify: checking existing profile binary after reboot'
  . /etc/profile
  command -v "${L5_BIN}" >>"${L5_LOG}" 2>&1 \
    || { echo "FAIL: ${L5_BIN} not on PATH after reboot" >&2; exit 1; }
  "${L5_BIN}" --version >>"${L5_LOG}" 2>&1 || "${L5_BIN}" >>"${L5_LOG}" 2>&1 \
    || { echo "FAIL: ${L5_BIN} did not run after reboot" >&2; exit 1; }
  printf 'nix-integration Layer 5 reboot smoke passed\n'
  printf 'log: %s\n' "${L5_LOG}"
  exit 0
fi

log5 "install: nix profile install ${L5_PACKAGE}"
"${NIX_BIN}" --extra-experimental-features 'nix-command flakes' profile install "${L5_PACKAGE}" >>"${L5_LOG}" 2>&1 \
  || { echo "FAIL: nix profile install ${L5_PACKAGE} failed" >&2; exit 1; }

log5 'verify: binary exists via profile link and fresh profile-sourced shell'
[ -x "${HOME:-/storage}/.nix-profile/bin/${L5_BIN}" ] \
  || { echo "FAIL: profile binary missing: ${HOME:-/storage}/.nix-profile/bin/${L5_BIN}" >&2; exit 1; }
/bin/sh -c '. /etc/profile; command -v "'"${L5_BIN}"'"; "'"${L5_BIN}"'"' >>"${L5_LOG}" 2>&1 \
  || { echo "FAIL: ${L5_BIN} did not run from a fresh profile-sourced shell" >&2; exit 1; }

log5 'diagnostics: nixctl status and nix-doctor report Layer 5 state'
"${NIXCTL}" status >>"${L5_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 5 smoke' >&2; exit 1; }
grep -q 'Layer 5 (persistent profile) status' "${L5_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 5 section' >&2; exit 1; }
"${DOCTOR}" --offline >>"${L5_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 5 smoke' >&2; exit 1; }
grep -q 'Layer 5 profile link' "${L5_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 5 profile state' >&2; exit 1; }

if [ "${LAYER5_REBOOT_VERIFY:-}" = "prepare" ]; then
  log5 "leaving ${L5_NAME} installed for reboot verification"
  printf 'nix-integration Layer 5 smoke prepared for reboot verification\n'
  printf 'After reboot run: LAYER5_SMOKE=1 LAYER5_REBOOT_VERIFY=verify %s\n' "$0"
  printf 'log: %s\n' "${L5_LOG}"
  exit 0
fi

if [ "${preexisting}" -eq 0 ]; then
  log5 "cleanup: nix profile remove ${L5_NAME}"
  "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' profile remove "${L5_NAME}" >>"${L5_LOG}" 2>&1 \
    || { echo "FAIL: nix profile remove ${L5_NAME} failed" >&2; exit 1; }
else
  log5 "cleanup: leaving pre-existing ${L5_NAME} profile entry intact"
fi

printf 'nix-integration Layer 5 smoke passed\n'
printf 'log: %s\n' "${L5_LOG}"
fi

# ---- Layer 6 device-side smoke (opt-in) ------------------------------------
# Set LAYER6_SMOKE=1 to validate managed storage-local user-environment
# activation on hardware. Requires Layer 4/5 shell integration to be healthy.
if [ "${LAYER6_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER7_SMOKE:-0}" != "1" ] && [ "${LAYER8_SMOKE:-0}" != "1" ] && [ "${LAYER9_SMOKE:-0}" != "1" ]; then
    exit 0
  fi
else

L6_LOG=/tmp/nix-integration-layer6-smoke.log
L6_CACHE=/storage/.cache/nix-layer6-smoke-bundle
L6_BUNDLE="${L6_CACHE}/layer6-user-env"
rm -f "${L6_LOG}"
mkdir -p "${L6_CACHE}"
rm -rf "${L6_BUNDLE}"
cp -R "${PKG_DIR}/tests/fixtures/layer6-user-env" "${L6_BUNDLE}"

log6() {
  printf '[layer6-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L6_LOG}"
}

NIX_BIN=/nix/var/nix/profiles/default/bin/nix
[ -x "${NIX_BIN}" ] || { echo 'FAIL: Layer 6 smoke requires Layer 4 real Nix' >&2; exit 1; }
[ -d "${HOME:-/storage}/.nix-profile/bin" ] || { echo 'FAIL: Layer 6 smoke requires Layer 5 profile bin' >&2; exit 1; }
[ -w /storage ] || { echo 'FAIL: /storage is not writable' >&2; exit 1; }

if [ "${LAYER6_REBOOT_VERIFY:-}" = "verify" ]; then
  log6 'reboot verify: checking existing Layer 6 managed files after reboot'
  . /etc/profile
  command -v rocknix-layer6-smoke >>"${L6_LOG}" 2>&1 \
    || { echo 'FAIL: rocknix-layer6-smoke not on PATH after reboot' >&2; exit 1; }
  rocknix-layer6-smoke >>"${L6_LOG}" 2>&1 \
    || { echo 'FAIL: rocknix-layer6-smoke did not run after reboot' >&2; exit 1; }
  "${NIXCTL}" status >>"${L6_LOG}" 2>&1 \
    || { echo 'FAIL: nixctl status failed during Layer 6 reboot verify' >&2; exit 1; }
  "${DOCTOR}" --offline >>"${L6_LOG}" 2>&1 \
    || { echo 'FAIL: nix-doctor failed during Layer 6 reboot verify' >&2; exit 1; }
  if [ "${LAYER6_KEEP:-0}" != "1" ]; then
    "${NIXCTL}" user-env deactivate >>"${L6_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 6 deactivate failed after reboot verify' >&2; exit 1; }
  fi
  printf 'nix-integration Layer 6 reboot smoke passed\n'
  printf 'log: %s\n' "${L6_LOG}"
  exit 0
fi

log6 'pre-flight: Layer 6 activation bundle'
"${NIXCTL}" user-env preflight "${L6_BUNDLE}" >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 6 preflight failed' >&2; exit 1; }

log6 'activate: Layer 6 smoke bundle'
"${NIXCTL}" user-env activate "${L6_BUNDLE}" >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 6 activation failed' >&2; exit 1; }

log6 'verify: wrapper and profile snippet work in a fresh shell'
/bin/sh -c '. /etc/profile; command -v rocknix-layer6-smoke; rocknix-layer6-smoke' >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 6 managed wrapper did not run from a fresh shell' >&2; exit 1; }

grep -q 'rocknix-layer6-smoke:active' "${L6_LOG}" \
  || { echo 'FAIL: Layer 6 profile snippet did not set smoke environment' >&2; exit 1; }

log6 'diagnostics: nixctl status and nix-doctor report Layer 6 state'
"${NIXCTL}" status >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 6 smoke' >&2; exit 1; }
grep -q 'Layer 6 (managed user environment) status' "${L6_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 6 section' >&2; exit 1; }
"${DOCTOR}" --offline >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 6 smoke' >&2; exit 1; }
grep -q 'Layer 6 state: active' "${L6_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 6 active state' >&2; exit 1; }

log6 'conflict: non-owned target is refused and preserved'
printf 'user-owned\n' >/storage/bin/rocknix-layer6-conflict
mkdir -p /storage/.cache/nix-layer6-conflict/files/bin
printf '#!/bin/sh\necho conflict\n' >/storage/.cache/nix-layer6-conflict/files/bin/rocknix-layer6-conflict
chmod 0755 /storage/.cache/nix-layer6-conflict/files/bin/rocknix-layer6-conflict
printf 'bin|rocknix-layer6-conflict|files/bin/rocknix-layer6-conflict|0755\n' >/storage/.cache/nix-layer6-conflict/manifest
if "${NIXCTL}" user-env activate /storage/.cache/nix-layer6-conflict >>"${L6_LOG}" 2>&1; then
  echo 'FAIL: Layer 6 conflict activation unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'user-owned' /storage/bin/rocknix-layer6-conflict \
  || { echo 'FAIL: Layer 6 conflict target was modified' >&2; exit 1; }
rm -f /storage/bin/rocknix-layer6-conflict
rm -rf /storage/.cache/nix-layer6-conflict

if [ "${LAYER6_REBOOT_VERIFY:-}" = "prepare" ]; then
  log6 'leaving Layer 6 smoke bundle active for reboot verification'
  printf 'nix-integration Layer 6 smoke prepared for reboot verification\n'
  printf 'After reboot run: LAYER6_SMOKE=1 LAYER6_REBOOT_VERIFY=verify %s\n' "$0"
  printf 'log: %s\n' "${L6_LOG}"
  exit 0
fi

log6 'cleanup: deactivate Layer 6 smoke bundle'
"${NIXCTL}" user-env deactivate >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 6 deactivate failed' >&2; exit 1; }
[ ! -e /storage/bin/rocknix-layer6-smoke ] \
  || { echo 'FAIL: Layer 6 wrapper still present after deactivate' >&2; exit 1; }
[ ! -e /storage/.config/profile.d/999-rocknix-layer6-smoke ] \
  || { echo 'FAIL: Layer 6 profile snippet still present after deactivate' >&2; exit 1; }

printf 'nix-integration Layer 6 smoke passed\n'
printf 'log: %s\n' "${L6_LOG}"
fi

# ---- Layer 7 device-side smoke (opt-in) ------------------------------------
# Set LAYER7_SMOKE=1 to validate the first Nix-managed app launcher on
# hardware. This smoke intentionally checks readiness and activation; actual
# visual confirmation remains operator-observed because CI cannot inspect the
# handheld screen.
if [ "${LAYER7_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER8_SMOKE:-0}" != "1" ] && [ "${LAYER9_SMOKE:-0}" != "1" ]; then
    exit 0
  fi
else

L7_LOG=/tmp/nix-integration-layer7-smoke.log
L7_CACHE=/storage/.cache/nix-layer7-browser-bundle
L7_BUNDLE="${L7_CACHE}/browser"
L7_BIN="${LAYER7_SMOKE_BIN:-chromium}"
L7_LAUNCHER=/storage/bin/rocknix-layer7-browser
rm -f "${L7_LOG}"
mkdir -p "${L7_CACHE}"
rm -rf "${L7_BUNDLE}"
cp -R "${PKG_DIR}/tests/fixtures/layer7-apps/browser" "${L7_BUNDLE}"

log7() {
  printf '[layer7-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L7_LOG}"
}

[ -d "${HOME:-/storage}/.nix-profile/bin" ] || { echo 'FAIL: Layer 7 smoke requires Layer 5 profile bin' >&2; exit 1; }
[ -x "${HOME:-/storage}/.nix-profile/bin/${L7_BIN}" ] || { echo "FAIL: Layer 7 smoke requires ${L7_BIN} in the Nix user profile" >&2; exit 1; }
[ -w /storage ] || { echo 'FAIL: /storage is not writable' >&2; exit 1; }

if [ "${LAYER7_REBOOT_VERIFY:-}" != "verify" ] && [ "${LAYER7_ALLOW_ACTIVE_LAYER6:-0}" != "1" ]; then
  existing_state=$(${NIX_LAYER6_ACTIVATE} status 2>/dev/null | awk '/state:/ {print $2; exit}' || echo absent)
  if [ "${existing_state}" = "active" ]; then
    echo 'FAIL: Layer 7 smoke requires no pre-existing active Layer 6 bundle; deactivate it first or set LAYER7_ALLOW_ACTIVE_LAYER6=1' >&2
    exit 1
  fi
fi

if [ "${LAYER7_REBOOT_VERIFY:-}" = "verify" ]; then
  log7 'reboot verify: checking existing Layer 7 launcher after reboot'
  . /etc/profile
  [ -x "${L7_LAUNCHER}" ] || { echo 'FAIL: Layer 7 launcher missing after reboot' >&2; exit 1; }
  ROCKNIX_LAYER7_BROWSER_APP="${L7_BIN}" "${L7_LAUNCHER}" --check >>"${L7_LOG}" 2>&1 \
    || { echo 'FAIL: Layer 7 launcher readiness failed after reboot' >&2; exit 1; }
  "${NIXCTL}" status >>"${L7_LOG}" 2>&1 \
    || { echo 'FAIL: nixctl status failed during Layer 7 reboot verify' >&2; exit 1; }
  "${DOCTOR}" --offline >>"${L7_LOG}" 2>&1 \
    || { echo 'FAIL: nix-doctor failed during Layer 7 reboot verify' >&2; exit 1; }
  if [ "${LAYER7_KEEP:-0}" != "1" ]; then
    "${NIXCTL}" user-env deactivate >>"${L7_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 7 deactivate failed after reboot verify' >&2; exit 1; }
  fi
  printf 'nix-integration Layer 7 reboot smoke passed\n'
  printf 'log: %s\n' "${L7_LOG}"
  exit 0
fi

log7 'pre-flight: Layer 7 browser activation bundle'
"${NIXCTL}" user-env preflight "${L7_BUNDLE}" >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 7 preflight failed' >&2; exit 1; }

log7 'activate: Layer 7 browser launcher bundle'
"${NIXCTL}" user-env activate "${L7_BUNDLE}" >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 7 activation failed' >&2; exit 1; }

log7 'verify: launcher readiness uses Nix profile binary'
ROCKNIX_LAYER7_BROWSER_APP="${L7_BIN}" "${L7_LAUNCHER}" --check >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 7 launcher readiness check failed' >&2; exit 1; }
grep -q 'rocknix-layer7-browser:ready' "${L7_LOG}" \
  || { echo 'FAIL: Layer 7 launcher did not report ready' >&2; exit 1; }

log7 'diagnostics: nixctl status and nix-doctor report Layer 7 state'
NIX_LAYER7_APP_BIN="${L7_BIN}" "${NIXCTL}" status >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 7 smoke' >&2; exit 1; }
grep -q 'Layer 7 (app/UI experiment) status' "${L7_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 7 section' >&2; exit 1; }
NIX_LAYER7_APP_BIN="${L7_BIN}" "${DOCTOR}" --offline >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 7 smoke' >&2; exit 1; }
grep -q 'Layer 7 ready' "${L7_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 7 readiness' >&2; exit 1; }

if [ "${LAYER7_REBOOT_VERIFY:-}" = "prepare" ]; then
  log7 'leaving Layer 7 launcher active for reboot verification'
  printf 'nix-integration Layer 7 smoke prepared for reboot verification\n'
  printf 'After reboot run: LAYER7_SMOKE=1 LAYER7_REBOOT_VERIFY=verify %s\n' "$0"
  printf 'log: %s\n' "${L7_LOG}"
  exit 0
fi

log7 'cleanup: deactivate Layer 7 launcher bundle'
"${NIXCTL}" user-env deactivate >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 7 deactivate failed' >&2; exit 1; }
[ ! -e /storage/bin/rocknix-layer7-browser ] \
  || { echo 'FAIL: Layer 7 launcher still present after deactivate' >&2; exit 1; }
[ ! -e /storage/.config/profile.d/999-rocknix-layer7-browser ] \
  || { echo 'FAIL: Layer 7 profile snippet still present after deactivate' >&2; exit 1; }

printf 'nix-integration Layer 7 smoke passed\n'
printf 'log: %s\n' "${L7_LOG}"
fi

# ---- Layer 8 device-side smoke (opt-in) ------------------------------------
# Set LAYER8_SMOKE=1 to validate experimental nix-daemon mode on hardware.
# Requires Layer 4 real Nix, image-time daemon build identities/config, and
# opt-in daemon units. Default CI never starts systemd units.
if [ "${LAYER8_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER9_SMOKE:-0}" != "1" ]; then
    exit 0
  fi
else

L8_LOG=/tmp/nix-integration-layer8-smoke.log
rm -f "${L8_LOG}"

log8() {
  printf '[layer8-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L8_LOG}"
}

NIX_BIN=/nix/var/nix/profiles/default/bin/nix
[ -x "${NIX_BIN}" ] || { echo 'FAIL: Layer 8 smoke requires Layer 4 real Nix' >&2; exit 1; }
[ -x /nix/var/nix/profiles/default/bin/nix-daemon ] || { echo 'FAIL: Layer 8 smoke requires nix-daemon in the Nix default profile' >&2; exit 1; }
awk '$2 == "/nix" {found=1} END {exit !found}' /proc/mounts 2>/dev/null \
  || { echo 'FAIL: /nix is not mounted' >&2; exit 1; }

if [ "${LAYER8_REBOOT_VERIFY:-}" = "verify" ]; then
  log8 'reboot verify: checking daemon mode after reboot'
  "${NIXCTL}" daemon status >>"${L8_LOG}" 2>&1 \
    || { echo 'FAIL: nixctl daemon status failed during Layer 8 reboot verify' >&2; exit 1; }
  NIX_REMOTE=daemon "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' store ping >>"${L8_LOG}" 2>&1 \
    || { echo 'FAIL: daemon store ping failed after reboot' >&2; exit 1; }
  "${DOCTOR}" --offline >>"${L8_LOG}" 2>&1 \
    || { echo 'FAIL: nix-doctor failed during Layer 8 reboot verify' >&2; exit 1; }
  if [ "${LAYER8_KEEP:-0}" != "1" ]; then
    "${NIXCTL}" daemon disable >>"${L8_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 8 daemon disable failed after reboot verify' >&2; exit 1; }
  fi
  printf 'nix-integration Layer 8 reboot smoke passed\n'
  printf 'log: %s\n' "${L8_LOG}"
  exit 0
fi

log8 'pre-flight: Layer 8 daemon prerequisites'
"${NIXCTL}" daemon preflight >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 8 daemon preflight failed' >&2; exit 1; }

log8 'enable: Layer 8 daemon socket'
"${NIXCTL}" daemon enable >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 8 daemon enable failed' >&2; exit 1; }

log8 'verify: client talks to daemon'
NIX_REMOTE=daemon "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' store ping >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: daemon store ping failed' >&2; exit 1; }

log8 'verify: trivial cached package through daemon'
NIX_REMOTE=daemon "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' run nixpkgs#hello >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: daemon nix run hello smoke failed' >&2; exit 1; }

grep -q 'Hello, world!' "${L8_LOG}" \
  || { echo 'FAIL: daemon hello smoke did not print expected output' >&2; exit 1; }

log8 'diagnostics: nixctl status and nix-doctor report Layer 8 state'
"${NIXCTL}" status >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 8 smoke' >&2; exit 1; }
grep -q 'Layer 8 (experimental daemon) status' "${L8_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 8 section' >&2; exit 1; }
"${DOCTOR}" --offline >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 8 smoke' >&2; exit 1; }
grep -q 'Layer 8 daemon state' "${L8_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 8 state' >&2; exit 1; }

if [ "${LAYER8_REBOOT_VERIFY:-}" = "prepare" ]; then
  log8 'leaving Layer 8 daemon active for reboot verification'
  printf 'nix-integration Layer 8 smoke prepared for reboot verification\n'
  printf 'After reboot run: LAYER8_SMOKE=1 LAYER8_REBOOT_VERIFY=verify %s\n' "$0"
  printf 'log: %s\n' "${L8_LOG}"
  exit 0
fi

log8 'cleanup: disable Layer 8 daemon mode'
"${NIXCTL}" daemon disable >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 8 daemon disable failed' >&2; exit 1; }

printf 'nix-integration Layer 8 smoke passed\n'
printf 'log: %s\n' "${L8_LOG}"
fi

# ---- Layer 9 device-side smoke (opt-in) ------------------------------------
# Set LAYER9_SMOKE=1 to validate a manually started systemd-nspawn guest proof
# on hardware. Requires a Layer 9-enabled image and a pre-staged guest rootfs.
# The smoke does not download or generate the rootfs and never enables a unit.
if [ "${LAYER9_SMOKE:-0}" != "1" ]; then
  exit 0
fi

L9_LOG=/tmp/nix-integration-layer9-smoke.log
L9_NSPAWN="${LAYER9_NSPAWN_BIN:-${NIX_LAYER9_NSPAWN_BIN:-/usr/bin/systemd-nspawn}}"
L9_ROOT="${LAYER9_GUEST_ROOT:-${NIX_LAYER9_GUEST_ROOT:-/storage/machines/rocknix-guest}}"
L9_TIMEOUT="${LAYER9_TIMEOUT:-30}"
L9_PROOF_COMMAND="${LAYER9_PROOF_COMMAND:-printf 'layer9-guest-proof\\n'; if command -v nix >/dev/null 2>&1; then nix --version; fi}"
rm -f "${L9_LOG}"

log9() {
  printf '[layer9-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L9_LOG}"
}

layer9_guest_running() {
  ps -ef 2>/dev/null | grep '[s]ystemd-nspawn' | grep -F -- "${L9_ROOT}" >/dev/null 2>&1
}

layer9_no_enabled_unit() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled systemd-nspawn@rocknix-guest.service >/dev/null 2>&1; then
      return 1
    fi
  fi
  return 0
}

[ -x "${L9_NSPAWN}" ] || { echo "FAIL: Layer 9 smoke requires executable systemd-nspawn at ${L9_NSPAWN}" >&2; exit 1; }
[ -d "${L9_ROOT}" ] || { echo "FAIL: Layer 9 smoke requires staged guest rootfs at ${L9_ROOT}" >&2; exit 1; }
[ -d "${L9_ROOT}/etc" ] || [ -d "${L9_ROOT}/usr" ] || [ -d "${L9_ROOT}/nix" ] \
  || { echo "FAIL: Layer 9 guest root does not look proof-ready: ${L9_ROOT}" >&2; exit 1; }
command -v timeout >/dev/null 2>&1 \
  || { echo 'FAIL: Layer 9 smoke requires timeout to keep the guest proof bounded' >&2; exit 1; }
layer9_no_enabled_unit \
  || { echo 'FAIL: Layer 9 found an enabled systemd-nspawn guest unit before smoke' >&2; exit 1; }

log9 'pre-flight: Layer 9 nspawn diagnostics'
NIX_LAYER9_NSPAWN_BIN="${L9_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${L9_ROOT}" \
  "${NIXCTL}" status >>"${L9_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 9 preflight' >&2; exit 1; }
grep -q 'Layer 9 (nspawn guest proof) status' "${L9_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 9 section' >&2; exit 1; }
NIX_LAYER9_NSPAWN_BIN="${L9_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${L9_ROOT}" \
  "${DOCTOR}" --offline >>"${L9_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 9 preflight' >&2; exit 1; }
grep -q 'Layer 9 nspawn guest state' "${L9_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 9 state' >&2; exit 1; }

log9 'start: bounded systemd-nspawn guest proof command'
timeout "${L9_TIMEOUT}" "${L9_NSPAWN}" --quiet --register=no --directory="${L9_ROOT}" /bin/sh -lc "${L9_PROOF_COMMAND}" >>"${L9_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 9 nspawn proof command failed' >&2; layer9_guest_running && pkill -f "systemd-nspawn.*${L9_ROOT}" 2>/dev/null || true; exit 1; }
grep -q 'layer9-guest-proof' "${L9_LOG}" \
  || { echo 'FAIL: Layer 9 guest proof marker missing' >&2; exit 1; }

log9 'cleanup: verify no guest process or enabled guest unit remains'
if layer9_guest_running; then
  pkill -f "systemd-nspawn.*${L9_ROOT}" 2>/dev/null || true
  sleep 1
fi
layer9_guest_running \
  && { echo 'FAIL: Layer 9 guest process still running after proof' >&2; exit 1; }
layer9_no_enabled_unit \
  || { echo 'FAIL: Layer 9 found enabled systemd-nspawn guest unit after smoke' >&2; exit 1; }

log9 'diagnostics: post-proof host Layer 9 status remains readable'
NIX_LAYER9_NSPAWN_BIN="${L9_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${L9_ROOT}" \
  "${NIXCTL}" status >>"${L9_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed after Layer 9 proof' >&2; exit 1; }

printf 'nix-integration Layer 9 smoke passed\n'
printf 'log: %s\n' "${L9_LOG}"
