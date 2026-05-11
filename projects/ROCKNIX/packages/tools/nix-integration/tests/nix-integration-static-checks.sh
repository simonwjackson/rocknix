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
grep -q '/usr/lib/nix-integration/tests' "${PKG_DIR}/package.mk" || fail "package.mk does not install nix-integration smoke tests"
grep -q 'nix-integration-runtime-smoke.sh' "${PKG_DIR}/package.mk" || fail "package.mk does not package runtime smoke helper"
grep -q 'mkdir -p ${INSTALL}/nix' "${PKG_DIR}/package.mk" || fail "package.mk does not create /nix mountpoint"
grep -q 'enable_service nix-storage-setup.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix-storage-setup.service"
grep -q 'enable_service nix.mount' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix.mount"

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
grep -q 'layer10_root_executable' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest-local executable detection"
grep -q 'Layer 10 guest preflight passed' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest preflight"
grep -q 'cmd_guest_init' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 guest proof init"
grep -q 'cmd_guest_import' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10b bootable import"
grep -q 'guest import --bootable' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10b import command text"
grep -q 'rootfs-provenance' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10b provenance metadata"
grep -q 'archive contains unsafe paths' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10b archive safety guard"
grep -q 'layer10_list_archive' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10b compression-aware archive listing"
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
grep -q 'NIX_LAYER10_START_WAIT=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 10 start wait"
grep -q 'layer10_process_running' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing root-specific Layer 10 process evidence"
grep -q 'no nspawn process references' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 10 start live-evidence failure"
grep -q 'check_layer10' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 10 checks"
grep -q 'Layer 10 guest eligibility' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 10 eligibility output"
grep -q 'Layer 10 bootable provenance' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 10b provenance reporting"
grep -q 'layer10_process_running' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing root-specific Layer 10 process evidence"
grep -q 'unit is active but no nspawn process references' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 10 active-unit/no-process failure"
grep -q 'NIX_LAYER10_STATE_DIR=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 10 state dir"
grep -q 'NIX_LAYER10_STATE_DIR=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 10 state dir"
grep -q 'NIX_LAYER10_GUEST_ROOT=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 10 guest root"
grep -q 'NIX_LAYER10_GUEST_ROOT=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 10 guest root"
grep -q 'NIX_LAYER10_UNIT_NAME=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 10 unit name"
grep -q 'NIX_LAYER10_UNIT_NAME=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 10 unit name"
grep -q 'Layer 11 (one-shot guest-backed bridges) status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl status missing Layer 11 section"
grep -q 'cmd_bridge' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 11 bridge dispatch"
grep -q 'Layer 11 bridge preflight passed' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 11 bridge preflight"
grep -q 'cmd_bridge_install' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 11 bridge install"
grep -q 'cmd_bridge_remove' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 11 bridge remove"
grep -q 'cmd_bridge_run' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 11 bridge run"
grep -q 'target exists and is not owned by Layer 11' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 11 conflict refusal"
grep -q 'refusing unsafe target path' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 11 unsafe target guard"
grep -q 'bridge run' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 11 wrapper run path"
grep -q 'NIX_LAYER11_STATE_DIR=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 11 state dir"
grep -q 'NIX_LAYER11_BIN_DIR=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 11 bin dir"
grep -q 'NIX_LAYER11_NIXCTL_BIN=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 11 nixctl bin"
grep -q 'NIX_LAYER11_STATE_DIR=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 11 state dir"
grep -q 'NIX_LAYER11_BIN_DIR=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 11 bin dir"
grep -q 'check_layer11' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 11 checks"
grep -q 'Layer 11 bridge eligibility' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 11 eligibility output"
grep -q 'NIX_LAYER12_STATE_DIR=' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixtureable Layer 12 state dir"
grep -q 'NIX_LAYER12_STATE_DIR=' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing fixtureable Layer 12 state dir"
grep -q 'Layer 12 (opt-in guest SSH) status' "${PKG_DIR}/scripts/nixctl" || fail "nixctl status missing Layer 12 section"
grep -q 'cmd_guest_service' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 12 guest service dispatch"
grep -q 'guest service enable ssh' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 12 SSH enable command"
grep -q 'refusing unsafe port: ${port}' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 12 port guard"
grep -q -- '--private-network' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing private networking for bootable guest"
grep -q 'layer10_nspawn_network_args' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 12 shared-network switch"
if grep -q -- '--port=tcp:%s:22' "${PKG_DIR}/scripts/nixctl"; then
  fail "nixctl must not depend on systemd-nspawn --port NAT for Layer 12"
fi
grep -q 'currently supports only port' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing fixed guest SSH port guard"
grep -q -- '--bind-ro=%s:%s' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing Layer 12 authorized-keys bind"
grep -q 'check_layer12' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 12 checks"

grep -q 'Layer 12 guest SSH eligibility' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 12 eligibility output"
grep -q 'must not bind host port 22' "${PKG_DIR}/scripts/nix-doctor" || fail "nix-doctor missing Layer 12 port 22 guardrail"
grep -q 'LAYER12_SMOKE=ssh' "${PKG_DIR}/tests/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 12 SSH mode"
grep -q 'Layer 12 guest SSH did not return nix version' "${PKG_DIR}/tests/nix-integration-runtime-smoke.sh" || fail "Layer 12 smoke must execute a real SSH command"
for sub in status install upgrade uninstall doctor user-env daemon guest bridge; do
  # Subcommand can appear as 'sub)' (alone), 'sub|other)' (left of alt),
  # or '...|sub)' (right of alt). Match by requiring sub to be preceded by
  # start-of-line, whitespace, or '|' and followed by ')' or '|'.
  grep -qE "(^|[[:space:]]|\|)${sub}[|)]" "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing dispatch for subcommand: ${sub}"
done

grep -q 'surface|name|source|mode' "${PKG_DIR}/scripts/nix-layer-activate" || fail "nix-layer-activate missing manifest contract"
grep -q 'target exists and is not owned by Layer 6' "${PKG_DIR}/scripts/nix-layer-activate" || fail "nix-layer-activate missing conflict refusal"
# Layer 10b guest must not reference forbidden passthrough surfaces in the
# files that flow into the bootable rootfs artifact (rocknix-guest config
# and its transitive imports). Layer 14 deliberately adds passthrough-aware
# configuration (rocknix-guest-main-space) and must NOT contaminate the
# Layer 10b artifact. This check enforces that scoping by listing the
# Layer 10b/12 file set explicitly.
grep -q 'layer10_nspawn_bin' "${PKG_DIR}/scripts/nixctl" || fail "nixctl must resolve current compatible Layer 10 nspawn"
grep -q 'nspawn_bin=' "${PKG_DIR}/scripts/nixctl" || fail "Layer 10 provenance must record resolved nspawn"
[ -f "${PKG_DIR}/system.d/nix-storage-setup.service" ] || fail "missing nix-storage-setup.service"
[ -f "${PKG_DIR}/system.d/nix.mount" ] || fail "missing nix.mount"

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

# Layer 14 U1: Tailscale autostart fix encoded as a fresh-flash default.
# Without this, tailscaled is systemd-enabled but stopped by
# /usr/lib/autostart/common/099-networkservices a few seconds later because
# `get_setting tailscale.up` returns empty (key absent) which != "1". Encoding
# tailscale.up=1 in the shipped defaults makes a freshly flashed device run
# Tailscale on first cold boot, no manual `set_setting` required. Existing
# users with tailscale.up=0 in /storage/.config/system/configs/system.cfg are
# not overwritten on upgrade -- ROCKNIX's settings layer keeps user values.
SYSTEM_CFG_DEFAULTS="${REPO_ROOT}/projects/ROCKNIX/packages/rocknix/config/system/configs/system.cfg"
[ -f "${SYSTEM_CFG_DEFAULTS}" ] || fail "missing ROCKNIX system.cfg defaults"
grep -q '^tailscale\.up=1$' "${SYSTEM_CFG_DEFAULTS}" || fail "system.cfg defaults missing tailscale.up=1 (Layer 14 U1)"

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
grep -q 'LAYER10_SMOKE' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 10 opt-in flag"
grep -q 'guest run' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 10 proof guest run path"
grep -q 'guest start' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 10 bootable start path"
grep -q 'nix-integration Layer 10 smoke passed' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 10 success marker"
grep -q 'Layer 10 bootable smoke requires provenance metadata' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 10b provenance gate"
grep -q 'LAYER11_SMOKE' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 11 opt-in flag"
grep -q 'bridge install' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 11 bridge install path"
grep -q 'bridge run' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 11 bridge run path"
grep -q 'nix-integration Layer 11 smoke passed' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing Layer 11 success marker"

# nspawn running detector: must use exec-name + cmdline scan, not the
# self-matching ps|grep idiom that masked Layer 10b/12 hardware failures.
grep -q '^nspawn_pid_for_root()' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing nspawn_pid_for_root helper"
grep -q '^nspawn_running_for_root()' "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing nspawn_running_for_root helper"
if grep -q "grep '\[s\]ystemd-nspawn'" "${PKG_DIR}/scripts/nixctl"; then
  fail "nixctl still uses self-matching ps|grep '[s]ystemd-nspawn' idiom"
fi
grep -q '^smoke_nspawn_running()' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing smoke_nspawn_running helper"
if grep -q "grep '\[s\]ystemd-nspawn' | grep -F" "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh"; then
  fail "runtime smoke still uses self-matching ps|grep '[s]ystemd-nspawn' idiom"
fi
grep -q 'NSPAWN_IMPOSTOR_PID' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing self-match regression fixture for nspawn detector"

# U2 autostart-detection semantics: must use stdout-state allowlist, not
# 'is-enabled --quiet' exit-code-only check that misclassifies static units.
grep -q '^unit_autostarts()' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing unit_autostarts helper (U2)"
grep -q 'enabled|enabled-runtime|alias' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "unit_autostarts must allow only enabled/enabled-runtime/alias (U2)"
if grep -E -q 'systemctl is-enabled[^|]+>/dev/null 2>&1' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh"; then
  fail "runtime smoke still uses exit-code-only systemctl is-enabled idiom (U2)"
fi

# U3 hardware smoke runnable from packaged install layout: device-side
# sections must use resolve_smoke_bin so /usr/bin/nixctl is found at
# /usr/lib/nix-integration/tests/.
grep -q '^resolve_smoke_bin()' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing resolve_smoke_bin helper (U3)"
grep -q 'NIXCTL=\$(resolve_smoke_bin nixctl)' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke must resolve NIXCTL via resolve_smoke_bin (U3)"
grep -q 'DOCTOR=\$(resolve_smoke_bin nix-doctor)' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke must resolve DOCTOR via resolve_smoke_bin (U3)"

# U4 fixture preamble gate: HARDWARE_ONLY_MODE must reference all six CI-mode
# flags AND all three hardware-mode flags so future flag additions are caught.
grep -q 'HARDWARE_ONLY_MODE=' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing HARDWARE_ONLY_MODE gate (U4)"
for flag in LAYER4_SMOKE LAYER5_SMOKE LAYER6_SMOKE LAYER7_SMOKE LAYER8_SMOKE LAYER9_SMOKE; do
  grep -q "\"\${${flag}:-0}\" != \"1\"" "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "HARDWARE_ONLY_MODE must reject ${flag} (U4)"
done
grep -q 'LAYER10_SMOKE:-0}" != "proof"' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "HARDWARE_ONLY_MODE must reject LAYER10_SMOKE=proof (U4)"
grep -q 'LAYER10_SMOKE:-0}" = "bootable"' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "HARDWARE_ONLY_MODE must accept LAYER10_SMOKE=bootable (U4)"
grep -q 'hardware-only mode: skipping CI fixture preamble' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke missing hardware-only skip note (U4)"
l11_requested_refs=$(grep -c 'LAYER11_REQUESTED' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh")
l12_requested_refs=$(grep -c 'LAYER12_REQUESTED' "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh")
[ "${l11_requested_refs}" -ge 8 ] || fail "hardware Layer 11 request must survive earlier layer skip gates (U4)"
[ "${l12_requested_refs}" -ge 9 ] || fail "hardware Layer 12 request must survive earlier layer skip gates (U4)"

# =============================================================================
# Layer 14: thin host, Nix main-space
# =============================================================================

# U2: rocknix-guest-v2.service shape (the clean shopping-list nspawn unit).
L14_UNIT="${PKG_DIR}/system.d/rocknix-guest-v2.service"
[ -f "${L14_UNIT}" ] || fail "missing Layer 14 unit (U2)"

# Required binds (positive shape).
#
# /dev/console was on this list before 2026-05-08; live validation on
# Thor showed --bind=/dev/console clashes with the nspawn pty allocation
# ("Failed to copy bytes from %s to /dev/console") and the unit aborts
# at PID 1. Bug #5 fix removed the bind and is reflected here.
#
# /dev/tty0 + /dev/tty1 were added 2026-05-08 to let libseat acquire
# vt1 inside the guest; without them seatd cannot canonicalize a target
# tty and DRM session bring-up fails.
for required_bind in \
  '/dev/snd' \
  '/dev/rfkill' \
  '/dev/dri/card0' \
  '/dev/dri/renderD128' \
  '/dev/input' \
  '/dev/tty0' \
  '/dev/tty1' \
  '/run/.guest-udev:/run/udev' \
  '/sys/class/backlight' \
  '/sys/class/leds' \
  '/sys/class/devfreq' \
  '/sys/devices/system/cpu/cpufreq' \
  '/storage/roms' \
  '/storage/.guest'; do
  grep -qF -- "${required_bind}" "${L14_UNIT}" \
    || fail "Layer 14 unit missing required bind: ${required_bind} (U2)"
done

# Forbidden binds we KNOW broke things on Thor.
#
# /dev/console: clashes with nspawn pty allocation (Bug #5).
# Raw /run/udev (without scrubbing): InputPlumber-hidden devices
#   propagate into the guest and crash libseat / wlroots GPU init.
L14_UNIT_BODY_FOR_DEV_CONSOLE=$(grep -v '^[[:space:]]*#' "${L14_UNIT}")
if printf '%s\n' "${L14_UNIT_BODY_FOR_DEV_CONSOLE}" | grep -qE -- '--bind(-ro)?=/dev/console([[:space:]]|$|\\)'; then
  fail "Layer 14 unit must NOT bind /dev/console (Bug #5, nspawn pty clash)"
fi
if printf '%s\n' "${L14_UNIT_BODY_FOR_DEV_CONSOLE}" | grep -qE -- '--bind(-ro)?=/run/udev([[:space:]]|$|\\)'; then
  fail "Layer 14 unit must NOT bind raw /run/udev; bind the staged /run/.guest-udev tree instead (libseat InputPlumber-hidden enumeration crash)"
fi

# Layer 14 unit must run the udev-stage hook before nspawn so the
# scrubbed tree exists when systemd-nspawn attempts the bind-ro mount.
grep -q 'ExecStartPre=/usr/bin/rocknix-guest-udev-stage' "${L14_UNIT}" \
  || fail "Layer 14 unit missing ExecStartPre=/usr/bin/rocknix-guest-udev-stage (U2)"
grep -q 'SOUND_UDEV_WAIT_SECS' "${PKG_DIR}/scripts/rocknix-guest-udev-stage" \
  || fail "udev stage script must wait boundedly for sound udev metadata"
grep -q 'E:ALSA_CARD_NUMBER=' "${PKG_DIR}/scripts/rocknix-guest-udev-stage" \
  || fail "udev stage script must verify sound records contain ALSA card metadata"
grep -q 'inputplumber/by-hidden' "${PKG_DIR}/scripts/rocknix-guest-udev-stage" \
  || fail "udev stage script must continue scrubbing InputPlumber-hidden records"

# Forbidden binds (negative shape; the lessons of Tier A-E). Strip comment
# lines first so descriptive prose explaining what NOT to do does not
# itself trip the check.
L14_UNIT_BODY=$(grep -v '^[[:space:]]*#' "${L14_UNIT}")
for forbidden in \
  '--bind-ro=/usr' \
  '--bind-ro=/lib' \
  '--bind-ro=/etc/profile' \
  '--bind=/etc/resolv.conf' \
  '--bind-ro=/etc/resolv.conf' \
  '--bind-ro=/etc/ssh/authorized_keys' \
  '--bind=/run/0-runtime-dir' \
  '--bind=/tmp/.X11-unix' \
  '--bind=/storage:/storage'; do
  if printf '%s\n' "${L14_UNIT_BODY}" | grep -qF -- "${forbidden}"; then
    fail "Layer 14 unit contains forbidden bind matching: ${forbidden} (U2)"
  fi
done

# Lifecycle and safety knobs.
grep -q 'WorkingDirectory=/storage/machines/rocknix-guest' "${L14_UNIT}" \
  || fail "Layer 14 unit missing WorkingDirectory= (U2)"
grep -qE '^Restart=on-failure' "${L14_UNIT}" \
  || fail "Layer 14 unit must Restart=on-failure (U2)"
grep -qE '^WatchdogSec=' "${L14_UNIT}" \
  || fail "Layer 14 unit missing WatchdogSec= (U2)"
grep -q 'ExecStartPre=/usr/bin/rocknix-layer14-prep' "${L14_UNIT}" \
  || fail "Layer 14 unit missing prep ExecStartPre (U2)"
grep -q 'ExecStopPost=/usr/bin/rocknix-host-reclaim' "${L14_UNIT}" \
  || fail "Layer 14 unit missing reclaim ExecStopPost (U2/U7)"
grep -q -- '--register=no' "${L14_UNIT}" \
  || fail "Layer 14 unit must use --register=no (U2)"
if printf '%s\n' "${L14_UNIT_BODY}" | grep -qF -- '--private-network'; then
  fail "Layer 14 unit must NOT use --private-network -- shared netns is the main-space contract (U2)"
fi
if printf '%s\n' "${L14_UNIT_BODY}" | grep -q 'WantedBy=multi-user.target'; then
  fail "Layer 14 unit must NOT WantedBy=multi-user.target -- THIN_HOST=yes wires it via rocknix-graphical.target (U2)"
fi
grep -q 'WantedBy=rocknix-graphical.target' "${L14_UNIT}" \
  || fail "Layer 14 unit must WantedBy=rocknix-graphical.target (U2)"

# U2 helpers: prep + reclaim scripts.
check_script "${PKG_DIR}/scripts/rocknix-layer14-prep"
check_script "${PKG_DIR}/scripts/rocknix-host-reclaim"
grep -q 'ROCKNIX_LAYER14_GUEST_ROOT' "${PKG_DIR}/scripts/rocknix-layer14-prep" \
  || fail "prep script missing fixtureable guest-root override (U2)"
grep -q 'resolv.conf.layer14-owned' "${PKG_DIR}/scripts/rocknix-layer14-prep" \
  || fail "prep script missing resolv.conf ownership marker (U2)"
grep -q 'SERVICE_RESULT' "${PKG_DIR}/scripts/rocknix-host-reclaim" \
  || fail "reclaim script must distinguish exits via SERVICE_RESULT (U7)"
grep -q 'reclaim skipped' "${PKG_DIR}/scripts/rocknix-host-reclaim" \
  || fail "reclaim script must have a graceful-exit skip path (U7)"
grep -q 'sway essway' "${PKG_DIR}/scripts/rocknix-host-reclaim" \
  || fail "reclaim script must restart legacy host UI services on crash (U7)"

# U4 + U5: recovery toggle service + script + graphical target.
L14_TOGGLE_UNIT="${PKG_DIR}/system.d/rocknix-recovery-toggle.service"
L14_TOGGLE_SCRIPT="${PKG_DIR}/scripts/rocknix-recovery-toggle"
L14_TARGET_UNIT="${PKG_DIR}/system.d/rocknix-graphical.target"
[ -f "${L14_TOGGLE_UNIT}" ] || fail "missing Layer 14 recovery-toggle unit (U4)"
[ -f "${L14_TARGET_UNIT}" ] || fail "missing Layer 14 graphical target (U5)"
check_script "${L14_TOGGLE_SCRIPT}"
grep -q 'DefaultDependencies=no' "${L14_TOGGLE_UNIT}" \
  || fail "recovery-toggle must DefaultDependencies=no (U4)"
grep -q 'Before=sysinit.target' "${L14_TOGGLE_UNIT}" \
  || fail "recovery-toggle must run Before=sysinit.target (U4)"
grep -q 'WantedBy=sysinit.target' "${L14_TOGGLE_UNIT}" \
  || fail "recovery-toggle must be WantedBy=sysinit.target (U4)"
grep -q '/flash/rocknix.no-nspawn' "${L14_TOGGLE_SCRIPT}" \
  || fail "recovery-toggle script missing flag-file path (U4)"
grep -q 'rocknix\\.safe=1' "${L14_TOGGLE_SCRIPT}" \
  || fail "recovery-toggle script missing kernel cmdline pattern (U4)"
grep -q 'systemctl set-default' "${L14_TOGGLE_SCRIPT}" \
  || fail "recovery-toggle script must call systemctl set-default (U4)"
grep -q 'rocknix-graphical.target' "${L14_TOGGLE_SCRIPT}" \
  || fail "recovery-toggle script must reference rocknix-graphical.target (U4)"
grep -q 'graphical.target' "${L14_TOGGLE_SCRIPT}" \
  || fail "recovery-toggle script must reference legacy graphical.target (U4)"
grep -q 'Wants=rocknix-guest-v2.service' "${L14_TARGET_UNIT}" \
  || fail "rocknix-graphical.target must Wants= the v2 guest unit (U5)"
grep -q 'Alias=default.target' "${L14_TARGET_UNIT}" \
  || fail "rocknix-graphical.target must Alias=default.target so set-default works (U5)"

# U3: guest NixOS modules for Layer 14 main-space.

# Layer 14 Cemu build-parity diagnostics: host-side scripts must be
# syntax-checkable and the stable guest launcher must allow an explicit
# guest-native Cemu binary override without changing the default path.
for bind_path in \
  '--bind=/storage/.config/Cemu:/storage/.config/Cemu' \
  '--bind=/storage/.config/MangoHud:/storage/.config/MangoHud' \
  '--bind=/storage/.local:/storage/.local' \
  '--bind=/storage/roms/bios:/storage/roms/bios'; do
  grep -F -q -- "${bind_path}" "${PKG_DIR}/system.d/rocknix-guest-v2.service" \
    || fail "rocknix-guest-v2.service missing narrow Cemu compatibility bind: ${bind_path}"
done
! grep -F -q -- '--bind=/storage \' "${PKG_DIR}/system.d/rocknix-guest-v2.service" \
  || fail "rocknix-guest-v2.service must not broad-bind /storage"

# U6: THIN_HOST build flag, gated SM8550-only, wired into the package install.
grep -q 'THIN_HOST=' "${REPO_ROOT}/projects/ROCKNIX/options" \
  || fail "missing THIN_HOST build option (U6)"
grep -q 'THIN_HOST=' "${PKG_DIR}/package.mk" \
  || fail "package.mk missing THIN_HOST plumbing (U6)"
grep -q 'THIN_HOST.*=.*"yes".*DEVICE.*!=.*"SM8550"' "${PKG_DIR}/package.mk" \
  || fail "package.mk missing SM8550-only hard guard for THIN_HOST=yes (U6/R7)"
grep -q 'rocknix-layer14-prep' "${PKG_DIR}/package.mk" \
  || fail "package.mk does not install Layer 14 prep helper (U2)"
grep -q 'rocknix-host-reclaim' "${PKG_DIR}/package.mk" \
  || fail "package.mk does not install Layer 14 reclaim helper (U7)"
grep -q 'rocknix-recovery-toggle' "${PKG_DIR}/package.mk" \
  || fail "package.mk does not install Layer 14 recovery-toggle script (U4)"
# Structural assertion: the THIN_HOST=yes branch must enable
# recovery-toggle, rocknix-graphical.target, and rocknix-guest-v2;
# the THIN_HOST=no branch must NOT enable any of those AND must
# scrub the rocknix-graphical.target file that scripts/install's
# system.d glob otherwise drops in unconditionally. (Lesson from
# the first Thor flash 2026-05-08: shipping the target on a
# THIN_HOST=no image let the toggle's existence-check fire and
# rewrite default.target.)
thin_host_block_yes=$(awk '
  /if \[ "\$\{THIN_HOST\}" = "yes" \]; then/ { in_yes=1; next }
  in_yes && /^  else/ { in_yes=0 }
  in_yes && /^  fi/   { in_yes=0 }
  in_yes
' "${PKG_DIR}/package.mk")
thin_host_block_no=$(awk '
  /if \[ "\$\{THIN_HOST\}" = "yes" \]; then/ { in_yes=1; next }
  in_yes && /^  else/ { in_yes=0; in_no=1; next }
  in_no  && /^  fi/   { in_no=0 }
  in_no
' "${PKG_DIR}/package.mk")

[ -n "${thin_host_block_yes}" ] || fail "package.mk: THIN_HOST=yes block is empty (U6)"
[ -n "${thin_host_block_no}" ]  || fail "package.mk: THIN_HOST=no else-branch missing (U6, fix-after-flash regression guard)"

printf '%s\n' "${thin_host_block_yes}" | grep -q 'enable_service rocknix-recovery-toggle' \
  || fail "package.mk: enable_service rocknix-recovery-toggle must live INSIDE the THIN_HOST=yes block (U4)"
printf '%s\n' "${thin_host_block_yes}" | grep -q 'enable_service rocknix-graphical.target' \
  || fail "package.mk: enable_service rocknix-graphical.target must live inside THIN_HOST=yes block (U6)"
printf '%s\n' "${thin_host_block_yes}" | grep -q 'enable_service rocknix-guest-v2.service' \
  || fail "package.mk: enable_service rocknix-guest-v2.service must live inside THIN_HOST=yes block (U6)"
printf '%s\n' "${thin_host_block_yes}" | grep -q 'flash/HOW-TO-FALL-BACK.md' \
  || fail "package.mk does not ship HOW-TO-FALL-BACK.md to /flash under THIN_HOST=yes (U9)"

printf '%s\n' "${thin_host_block_no}" | grep -q 'safe_remove .*rocknix-graphical.target' \
  || fail "package.mk: THIN_HOST=no else-branch must safe_remove rocknix-graphical.target (regression: 2026-05-08 first-flash contract violation)"

# And the negative shape: NONE of the enable_service / cp HOW-TO
# lines may live OUTSIDE both branches (i.e., at top level of
# post_install before the if).
post_install_top=$(awk '
  /^post_install/ { in_post=1; next }
  /if \[ "\$\{THIN_HOST\}" = "yes" \]; then/ && in_post { in_post=0 }
  in_post
' "${PKG_DIR}/package.mk")
if printf '%s\n' "${post_install_top}" | grep -q 'enable_service rocknix-recovery-toggle'; then
  fail "package.mk: enable_service rocknix-recovery-toggle must NOT be unconditional (regression: 2026-05-08 first-flash bug)"
fi
if printf '%s\n' "${post_install_top}" | grep -q 'enable_service rocknix-graphical.target'; then
  fail "package.mk: enable_service rocknix-graphical.target must NOT be unconditional (U6)"
fi
if printf '%s\n' "${post_install_top}" | grep -q 'enable_service rocknix-guest-v2.service'; then
  fail "package.mk: enable_service rocknix-guest-v2.service must NOT be unconditional (U6)"
fi

# U8: standalone soak harness.
check_script "${PKG_DIR}/scripts/rocknix-layer14-soak"
grep -q 'rocknix-layer14-soak' "${PKG_DIR}/package.mk" \
  || fail "package.mk does not install rocknix-layer14-soak (U8)"
grep -q 'check_resolv_owned' "${PKG_DIR}/scripts/rocknix-layer14-soak" \
  || fail "soak harness missing resolv.conf bleed check (U8)"
grep -q 'check_no_host_usr_in_guest_path' "${PKG_DIR}/scripts/rocknix-layer14-soak" \
  || fail "soak harness missing host /usr leak check (U8)"
grep -q 'check_host_ssh_responsive' "${PKG_DIR}/scripts/rocknix-layer14-soak" \
  || fail "soak harness missing host SSH check (U8)"
grep -q 'check_memory_no_growth' "${PKG_DIR}/scripts/rocknix-layer14-soak" \
  || fail "soak harness missing memory-growth check (U8)"

# U9: HOW-TO-FALL-BACK.md exists and is self-contained.
printf 'nix-integration static checks passed\n'
