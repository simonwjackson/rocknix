#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "${PKG_DIR}/../../../../.." && pwd)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

check_script() {
  path=$1
  [ -f "${path}" ] || fail "missing script: ${path}"
  [ -x "${path}" ] || fail "script is not executable: ${path}"
  sh -n "${path}" || fail "shell syntax failed: ${path}"
}

check_script "${PKG_DIR}/scripts/nix-doctor"
check_script "${PKG_DIR}/scripts/nix-layer-activate"
check_script "${PKG_DIR}/scripts/nixctl"

[ -f "${PKG_DIR}/package.mk" ] || fail "missing package.mk"
sh -n "${PKG_DIR}/package.mk" || fail "package.mk syntax failed"
grep -q 'PKG_NAME="nix-integration"' "${PKG_DIR}/package.mk" || fail "package.mk has wrong PKG_NAME"
grep -q 'PKG_TOOLCHAIN="manual"' "${PKG_DIR}/package.mk" || fail "package.mk should use manual toolchain"
! grep -q 'nix-portable' "${PKG_DIR}/package.mk" || fail "package.mk must not ship nix-portable tooling on image-first builds"
grep -q 'nix-doctor' "${PKG_DIR}/package.mk" || fail "package.mk does not install nix-doctor"
grep -q 'nix-layer-activate' "${PKG_DIR}/package.mk" || fail "package.mk does not install nix-layer-activate (Layer 6 activation engine)"
grep -q 'nixctl' "${PKG_DIR}/package.mk" || fail "package.mk does not install nixctl (Layer 4 front door)"
grep -q 'mkdir -p ${INSTALL}/nix' "${PKG_DIR}/package.mk" || fail "package.mk does not create /nix mountpoint"
grep -q 'enable_service nix-storage-setup.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix-storage-setup.service"
grep -q 'enable_service nix.mount' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix.mount"
grep -q 'NIX_DAEMON_SUPPORT=' "${PKG_DIR}/package.mk" || fail "package.mk missing opt-in Layer 8 daemon support gate"
grep -q 'add_group "${NIX_DAEMON_BUILD_GROUP}"' "${PKG_DIR}/package.mk" || fail "package.mk missing image-time nix daemon build group"
grep -q 'add_user "nixbld${i}"' "${PKG_DIR}/package.mk" || fail "package.mk missing image-time nix daemon build users"
grep -q 'NIX_DAEMON_BUILD_USER_COUNT=' "${PKG_DIR}/package.mk" || fail "package.mk missing daemon build user count"

PROFILE_SNIPPET="998-nix-integration.conf"
[ -f "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" ] || fail "missing profile integration"
sh -n "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile integration syntax failed"
! grep -q 'NP_RUNTIME' "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile.d must not configure nix-portable runtime"
grep -q '/nix/var/nix/profiles/default/bin' "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile.d missing Layer 4 PATH prefix (/nix/var/nix/profiles/default/bin)"
grep -q '\.nix-profile/bin' "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile.d missing Layer 5 PATH prefix (~/.nix-profile/bin)"
grep -q 'Layer 5: persistent Nix profiles' "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile.d missing Layer 5 profile contract documentation"

# ROCKNIX's /etc/profile.d/098-busybox resets PATH. The Nix profile snippet
# must sort after it, or the Layer 4/5 PATH prefixes are clobbered in login
# shells. This guards the exact issue found during first image validation.
case "${PROFILE_SNIPPET}" in
  99*|[1-9][0-9][0-9]*) ;;
  *) fail "profile snippet must sort after 098-busybox so PATH is not reset later: ${PROFILE_SNIPPET}" ;;
esac

# Verify nixctl declares the canonical subcommands and pinned-version constants.
grep -q 'NIX_VERSION_PINNED=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing NIX_VERSION_PINNED constant"
grep -q 'NIX_TARBALL_SHA256_PINNED=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing NIX_TARBALL_SHA256_PINNED constant"
grep -q 'NIX_USER_PROFILE_BIN=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 5 profile bin constant"
grep -q 'Layer 5 (persistent profile) status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl status missing Layer 5 section"
grep -q 'print_profile_conflicts' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 5 conflict reporting"
grep -q 'is_expected_nix_tool_shadow' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing expected Nix tool shadow allowlist"
grep -q 'check_layer5' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 5 checks"
grep -q 'check_profile_command_conflicts' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 5 conflict checks"
grep -q 'is_expected_nix_tool_shadow' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing expected Nix tool shadow allowlist"
grep -q 'Layer 6 (managed user environment) status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl status missing Layer 6 section"
grep -q 'cmd_user_env' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 6 user-env dispatch"
grep -q 'check_layer6' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 6 checks"
grep -q 'Layer 6 source missing' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 6 missing source/store-path checks"
grep -q 'Layer 7 (app/UI experiment) status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl status missing Layer 7 section"
grep -q 'layer7_binary_is_nix_backed' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 7 Nix-backed binary origin check"
grep -q 'check_layer7' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 7 checks"
grep -q 'Layer 7 ready' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 7 readiness output"
grep -q 'Layer 8 (experimental daemon) status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl status missing Layer 8 section"
grep -q 'print_layer8_status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 8 status reporter"
grep -q 'cmd_daemon' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 8 daemon lifecycle dispatch"
grep -q 'daemon preflight failed' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 8 daemon preflight gate"
grep -q 'Layer 8 daemon mode disabled' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 8 daemon disable path"
grep -q 'check_layer8' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 8 checks"
grep -q 'Layer 8 daemon eligibility' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 8 eligibility output"
grep -q 'Layer 4 single-user/root Nix remains' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 8 fallback guidance"
grep -q 'NIX_GROUP_FILE=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable group file for Layer 8"
grep -q 'NIX_GROUP_FILE=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable group file for Layer 8"
grep -q 'Layer 9 (nspawn guest proof) status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl status missing Layer 9 section"
grep -q 'print_layer9_status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 9 status reporter"
grep -q 'layer9_eligibility' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 9 eligibility reporter"
grep -q 'check_layer9' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 9 checks"
grep -q 'Layer 9 nspawn eligibility' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 9 eligibility output"
grep -q 'NIX_LAYER9_NSPAWN_BIN=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable nspawn binary for Layer 9"
grep -q 'NIX_LAYER9_NSPAWN_BIN=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable nspawn binary for Layer 9"
grep -q 'NIX_LAYER9_GUEST_ROOT=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable guest root for Layer 9"
grep -q 'NIX_LAYER9_GUEST_ROOT=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable guest root for Layer 9"
grep -q 'NIX_LAYER9_SKIP_KERNEL_CHECK=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable kernel check override for Layer 9"
grep -q 'NIX_LAYER9_SKIP_KERNEL_CHECK=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable kernel check override for Layer 9"
grep -q 'Layer 10 (managed nspawn guest operations) status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl status missing Layer 10 section"
grep -q 'cmd_guest' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest dispatch"
grep -q 'layer10_rootfs_mode' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 rootfs mode detection"
grep -q 'Layer 10 guest preflight passed' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest preflight"
grep -q 'cmd_guest_init' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest proof init"
grep -q 'cmd_guest_run' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest run"
grep -q 'cmd_guest_shell' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest shell"
grep -q 'cmd_guest_start' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest start"
grep -q 'cmd_guest_stop' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest stop"
grep -q 'cmd_guest_cleanup' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest cleanup"
grep -q -- '--register=no' "${PKG_DIR}/scripts/nixctl" || fail "nixctl Layer 10 guest run must avoid machined registration"
grep -q 'guest cleanup: refusing unsafe guest root' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 unsafe cleanup guard"
grep -q 'CPUWeight=${NIX_LAYER10_CPU_WEIGHT}' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 CPUWeight resource policy"
grep -q 'MemoryMax=${NIX_LAYER10_MEMORY_MAX}' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 MemoryMax resource policy"
! grep -q 'systemctl.*enable.*rocknix-guest' "${PKG_DIR}/scripts/nixctl" || fail "nixctl must not enable Layer 10 guest units"
grep -q 'NIX_LAYER10_TIMEOUT=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 10 timeout"
grep -q 'check_layer10' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 10 checks"
grep -q 'Layer 10 guest eligibility' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 10 eligibility output"
grep -q 'NIX_LAYER10_STATE_DIR=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 10 state dir"
grep -q 'NIX_LAYER10_STATE_DIR=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 10 state dir"
grep -q 'NIX_LAYER10_GUEST_ROOT=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 10 guest root"
grep -q 'NIX_LAYER10_GUEST_ROOT=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 10 guest root"
grep -q 'NIX_LAYER10_UNIT_NAME=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 10 unit name"
grep -q 'NIX_LAYER10_UNIT_NAME=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 10 unit name"
for sub in status install upgrade uninstall doctor user-env daemon guest; do
  # Subcommand can appear as 'sub)' (alone), 'sub|other)' (left of alt),
  # or '...|sub)' (right of alt). Match by requiring sub to be preceded by
  # start-of-line, whitespace, or '|' and followed by ')' or '|'.
  grep -qE "(^|[[:space:]]|\|)${sub}[|)]" "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing dispatch for subcommand: ${sub}"
done

grep -q 'surface|name|source|mode' "${PKG_DIR}/scripts/nix-layer-activate" || fail "nix-layer-activate missing manifest contract"
grep -q 'target exists and is not owned by Layer 6' "${PKG_DIR}/scripts/nix-layer-activate" || fail "nix-layer-activate missing conflict refusal"
[ -f "${PKG_DIR}/docs/layer6-activation-contract.md" ] || fail "missing Layer 6 activation contract doc"
grep -q '/storage/bin' "${PKG_DIR}/docs/layer6-activation-contract.md" || fail "Layer 6 contract missing storage bin surface"
grep -q '/storage/.config/profile.d' "${PKG_DIR}/docs/layer6-activation-contract.md" || fail "Layer 6 contract missing profile.d surface"
[ -f "${PKG_DIR}/docs/layer7-app-experiment-contract.md" ] || fail "missing Layer 7 app experiment contract doc"
grep -q 'standard `nix profile`' "${PKG_DIR}/docs/layer7-app-experiment-contract.md" || fail "Layer 7 contract missing standard nix profile split"
grep -q '/storage/.local/share/nix-apps/layer7' "${PKG_DIR}/docs/layer7-app-experiment-contract.md" || fail "Layer 7 contract missing safe app state root"
grep -q '/storage/.cache/nix-apps/layer7' "${PKG_DIR}/docs/layer7-app-experiment-contract.md" || fail "Layer 7 contract missing safe app cache root"
grep -q 'Nix-backed binary' "${PKG_DIR}/docs/layer7-app-experiment-contract.md" || fail "Layer 7 contract missing Nix-backed binary proof"
[ -f "${PKG_DIR}/docs/layer9-nspawn-guest-contract.md" ] || fail "missing Layer 9 nspawn guest contract doc"
grep -q '/storage/machines/rocknix-guest' "${PKG_DIR}/docs/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing guest root path"
grep -q '/dev/dri' "${PKG_DIR}/docs/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing GPU passthrough prohibition"
grep -q 'PipeWire' "${PKG_DIR}/docs/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing audio passthrough prohibition"
grep -q '/dev/input' "${PKG_DIR}/docs/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing input passthrough prohibition"
grep -q 'Fallback does' "${PKG_DIR}/docs/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing fallback boundary"
grep -q 'Guest state can be stopped and removed without touching host Nix state' "${PKG_DIR}/docs/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing cleanup boundary"
[ -f "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" ] || fail "missing Layer 10 guest lifecycle contract doc"
grep -q '/storage/.config/nix-integration/layer10' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing state dir path"
grep -q '/storage/machines/rocknix-guest' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing guest root path"
grep -q -- '--register=no' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing no-machined nspawn flag"
grep -q 'machinectl' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing no machinectl dependency"
grep -q 'proof' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing proof rootfs mode"
grep -q 'bootable' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing bootable rootfs mode"
grep -q 'must not call `systemctl enable`' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing no-autostart policy"
grep -q '/dev/dri' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing GPU passthrough prohibition"
grep -q 'PipeWire' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing audio passthrough prohibition"
grep -q '/dev/input' "${PKG_DIR}/docs/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing input passthrough prohibition"
[ -f "${PKG_DIR}/system.d/nix-storage-setup.service" ] || fail "missing nix-storage-setup.service"
[ -f "${PKG_DIR}/system.d/nix.mount" ] || fail "missing nix.mount"
[ -f "${PKG_DIR}/system.d/nix-daemon.socket" ] || fail "missing Layer 8 nix-daemon.socket"
[ -f "${PKG_DIR}/system.d/nix-daemon.service" ] || fail "missing Layer 8 nix-daemon.service"
grep -q 'RequiresMountsFor=/storage' "${PKG_DIR}/system.d/nix-storage-setup.service" || fail "setup service does not require /storage"
grep -q '/storage/.nix-root' "${PKG_DIR}/system.d/nix-storage-setup.service" || fail "setup service does not prepare storage-backed Nix root"
grep -q 'DefaultDependencies=no' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount should avoid early local-fs ordering"
grep -q 'What=/storage/.nix-root' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount has wrong source"
grep -q 'Where=/nix' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount has wrong target"
grep -q 'Options=bind' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount is not a bind mount"
grep -q 'Before=nix-daemon.service' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount must order before nix-daemon.service"
grep -q 'Requires=nix.mount' "${PKG_DIR}/system.d/nix-daemon.socket" || fail "nix-daemon.socket must require nix.mount"
grep -q 'After=nix.mount' "${PKG_DIR}/system.d/nix-daemon.socket" || fail "nix-daemon.socket must start after nix.mount"
grep -q 'ConditionPathIsMountPoint=/nix' "${PKG_DIR}/system.d/nix-daemon.socket" || fail "nix-daemon.socket must require mounted /nix"
grep -q 'ListenStream=/nix/var/nix/daemon-socket/socket' "${PKG_DIR}/system.d/nix-daemon.socket" || fail "nix-daemon.socket has wrong socket path"
grep -q 'Requires=nix.mount' "${PKG_DIR}/system.d/nix-daemon.service" || fail "nix-daemon.service must require nix.mount"
grep -q 'After=nix.mount' "${PKG_DIR}/system.d/nix-daemon.service" || fail "nix-daemon.service must start after nix.mount"
grep -q 'ConditionPathIsMountPoint=/nix' "${PKG_DIR}/system.d/nix-daemon.service" || fail "nix-daemon.service must require mounted /nix"
grep -q 'NIX_CONF_DIR=/storage/.config/nix-daemon' "${PKG_DIR}/system.d/nix-daemon.service" || fail "nix-daemon.service missing storage-backed config path"
grep -q 'ExecStart=/nix/var/nix/profiles/default/bin/nix-daemon --daemon' "${PKG_DIR}/system.d/nix-daemon.service" || fail "nix-daemon.service has wrong ExecStart"
! grep -q 'enable_service nix-daemon' "${PKG_DIR}/package.mk" || fail "package.mk must not enable Layer 8 daemon units by default"

SYSTEMD_PKG="${REPO_ROOT}/projects/ROCKNIX/packages/sysutils/systemd/package.mk"
[ -f "${SYSTEMD_PKG}" ] || fail "missing ROCKNIX systemd package.mk"
grep -q 'NIX_INTEGRATION_SUPPORT=' "${REPO_ROOT}/projects/ROCKNIX/options" || fail "missing NIX_INTEGRATION_SUPPORT build option"
grep -q 'NIX_NSPAWN_SUPPORT=' "${REPO_ROOT}/projects/ROCKNIX/options" || fail "missing NIX_NSPAWN_SUPPORT build option"
grep -q 'nix-integration' "${REPO_ROOT}/projects/ROCKNIX/packages/virtual/image/package.mk" || fail "image package does not include nix-integration gate"
grep -q 'NIX_NSPAWN_SUPPORT=' "${SYSTEMD_PKG}" || fail "systemd package missing Layer 9 nspawn support gate"
grep -q 'if \[ "${NIX_NSPAWN_SUPPORT}" != "yes" \]' "${SYSTEMD_PKG}" || fail "systemd package must remove nspawn only when Layer 9 support is disabled"
grep -q 'safe_remove ${INSTALL}/usr/bin/systemd-nspawn' "${SYSTEMD_PKG}" || fail "systemd package missing nspawn binary removal fallback"
grep -q 'safe_remove ${INSTALL}/usr/lib/systemd/system/systemd-nspawn@.service' "${SYSTEMD_PKG}" || fail "systemd package missing nspawn unit removal fallback"
! grep -qE 'enable_service .*nspawn' "${SYSTEMD_PKG}" || fail "systemd package must not enable nspawn services by default"

[ ! -e "${REPO_ROOT}/nix-on-rocknix-bootstrap.sh" ] || fail "standalone nix-portable bootstrap should not exist in image-first flow"

[ -f "${PKG_DIR}/tests/fixtures/layer6-user-env/manifest" ] || fail "missing Layer 6 smoke fixture manifest"
grep -q 'bin|rocknix-layer6-smoke' "${PKG_DIR}/tests/fixtures/layer6-user-env/manifest" || fail "Layer 6 smoke fixture missing bin target"
grep -q 'profile.d|999-rocknix-layer6-smoke' "${PKG_DIR}/tests/fixtures/layer6-user-env/manifest" || fail "Layer 6 smoke fixture missing profile.d target"
[ -f "${PKG_DIR}/tests/fixtures/layer7-apps/browser/manifest" ] || fail "missing Layer 7 browser fixture manifest"
grep -q 'bin|rocknix-layer7-browser' "${PKG_DIR}/tests/fixtures/layer7-apps/browser/manifest" || fail "Layer 7 fixture missing browser launcher target"
grep -q 'profile.d|999-rocknix-layer7-browser' "${PKG_DIR}/tests/fixtures/layer7-apps/browser/manifest" || fail "Layer 7 fixture missing browser profile.d target"
check_script "${PKG_DIR}/tests/fixtures/layer7-apps/browser/files/bin/rocknix-layer7-browser"
sh -n "${PKG_DIR}/tests/fixtures/layer7-apps/browser/files/profile.d/999-rocknix-layer7-browser" || fail "Layer 7 profile snippet syntax failed"

[ -f "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" ] || fail "missing runtime smoke test"
sh -n "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke syntax failed"
grep -q 'LAYER8_SMOKE=1' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 8 opt-in flag"
grep -q 'LAYER8_REBOOT_VERIFY' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 8 reboot verification"
grep -q 'NIX_REMOTE=daemon' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing daemon client proof"
grep -q 'nix-integration Layer 8 smoke passed' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 8 success marker"
grep -q 'LAYER9_SMOKE=1' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 9 opt-in flag"
grep -q 'LAYER9_GUEST_ROOT' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 9 guest root override"
grep -q 'systemd-nspawn guest proof' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 9 nspawn proof description"
grep -q -- '--register=no' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke must run nspawn without machined registration"
grep -q 'layer9-guest-proof' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 9 proof marker"
grep -q 'nix-integration Layer 9 smoke passed' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 9 success marker"

printf 'nix-integration static checks passed\n'
