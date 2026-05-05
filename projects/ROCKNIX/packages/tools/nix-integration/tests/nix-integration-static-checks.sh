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

check_script "${PKG_DIR}/scripts/nix-portable-install"
check_script "${PKG_DIR}/scripts/nix-portable-run"
check_script "${PKG_DIR}/scripts/nix-doctor"
check_script "${PKG_DIR}/scripts/nix-layer-activate"
check_script "${PKG_DIR}/scripts/nixctl"

[ -f "${PKG_DIR}/package.mk" ] || fail "missing package.mk"
sh -n "${PKG_DIR}/package.mk" || fail "package.mk syntax failed"
grep -q 'PKG_NAME="nix-integration"' "${PKG_DIR}/package.mk" || fail "package.mk has wrong PKG_NAME"
grep -q 'PKG_TOOLCHAIN="manual"' "${PKG_DIR}/package.mk" || fail "package.mk should use manual toolchain"
grep -q 'nix-portable-install' "${PKG_DIR}/package.mk" || fail "package.mk does not install nix-portable-install"
grep -q 'nix-doctor' "${PKG_DIR}/package.mk" || fail "package.mk does not install nix-doctor"
grep -q 'nix-layer-activate' "${PKG_DIR}/package.mk" || fail "package.mk does not install nix-layer-activate (Layer 6 activation engine)"
grep -q 'nixctl' "${PKG_DIR}/package.mk" || fail "package.mk does not install nixctl (Layer 4 front door)"
grep -q 'mkdir -p ${INSTALL}/nix' "${PKG_DIR}/package.mk" || fail "package.mk does not create /nix mountpoint"
grep -q 'enable_service nix-storage-setup.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix-storage-setup.service"
grep -q 'enable_service nix.mount' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix.mount"

PROFILE_SNIPPET="998-nix-integration.conf"
[ -f "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" ] || fail "missing profile integration"
sh -n "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile integration syntax failed"
grep -q 'NP_RUNTIME="proot"' "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile does not default NP_RUNTIME to proot"
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
grep -q 'surface|name|source|mode' "${PKG_DIR}/scripts/nix-layer-activate" || fail "nix-layer-activate missing manifest contract"
grep -q 'target exists and is not owned by Layer 6' "${PKG_DIR}/scripts/nix-layer-activate" || fail "nix-layer-activate missing conflict refusal"
[ -f "${PKG_DIR}/docs/layer6-activation-contract.md" ] || fail "missing Layer 6 activation contract doc"
grep -q '/storage/bin' "${PKG_DIR}/docs/layer6-activation-contract.md" || fail "Layer 6 contract missing storage bin surface"
grep -q '/storage/.config/profile.d' "${PKG_DIR}/docs/layer6-activation-contract.md" || fail "Layer 6 contract missing profile.d surface"
for sub in status install upgrade uninstall doctor user-env; do
  # Subcommand can appear as 'sub)' (alone), 'sub|other)' (left of alt),
  # or '...|sub)' (right of alt). Match by requiring sub to be preceded by
  # start-of-line, whitespace, or '|' and followed by ')' or '|'.
  grep -qE "(^|[[:space:]]|\|)${sub}[|)]" "${PKG_DIR}/scripts/nixctl" || fail "nixctl missing dispatch for subcommand: ${sub}"
done

[ -f "${PKG_DIR}/system.d/nix-storage-setup.service" ] || fail "missing nix-storage-setup.service"
[ -f "${PKG_DIR}/system.d/nix.mount" ] || fail "missing nix.mount"
grep -q 'RequiresMountsFor=/storage' "${PKG_DIR}/system.d/nix-storage-setup.service" || fail "setup service does not require /storage"
grep -q '/storage/.nix-root' "${PKG_DIR}/system.d/nix-storage-setup.service" || fail "setup service does not prepare storage-backed Nix root"
grep -q 'DefaultDependencies=no' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount should avoid early local-fs ordering"
grep -q 'What=/storage/.nix-root' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount has wrong source"
grep -q 'Where=/nix' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount has wrong target"
grep -q 'Options=bind' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount is not a bind mount"

grep -q 'NIX_INTEGRATION_SUPPORT=' "${REPO_ROOT}/projects/ROCKNIX/options" || fail "missing NIX_INTEGRATION_SUPPORT build option"
grep -q 'nix-integration' "${REPO_ROOT}/projects/ROCKNIX/packages/virtual/image/package.mk" || fail "image package does not include nix-integration gate"

[ -f "${REPO_ROOT}/nix-on-rocknix-bootstrap.sh" ] || fail "missing standalone bootstrap script"
[ -x "${REPO_ROOT}/nix-on-rocknix-bootstrap.sh" ] || fail "standalone bootstrap script is not executable"
sh -n "${REPO_ROOT}/nix-on-rocknix-bootstrap.sh" || fail "standalone bootstrap script syntax failed"
grep -q 'NP_RUNTIME=.*proot' "${REPO_ROOT}/nix-on-rocknix-bootstrap.sh" || fail "standalone bootstrap does not default to proot"
grep -q 'nix-dev-shell' "${REPO_ROOT}/nix-on-rocknix-bootstrap.sh" || fail "standalone bootstrap does not install nix-dev-shell"

[ -f "${PKG_DIR}/tests/fixtures/layer6-user-env/manifest" ] || fail "missing Layer 6 smoke fixture manifest"
grep -q 'bin|rocknix-layer6-smoke' "${PKG_DIR}/tests/fixtures/layer6-user-env/manifest" || fail "Layer 6 smoke fixture missing bin target"
grep -q 'profile.d|999-rocknix-layer6-smoke' "${PKG_DIR}/tests/fixtures/layer6-user-env/manifest" || fail "Layer 6 smoke fixture missing profile.d target"

[ -f "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" ] || fail "missing runtime smoke test"
sh -n "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke syntax failed"

printf 'nix-integration static checks passed\n'
