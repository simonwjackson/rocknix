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

[ -f "${PKG_DIR}/package.mk" ] || fail "missing package.mk"
sh -n "${PKG_DIR}/package.mk" || fail "package.mk syntax failed"
grep -q 'PKG_NAME="nix-integration"' "${PKG_DIR}/package.mk" || fail "package.mk has wrong PKG_NAME"
grep -q 'PKG_TOOLCHAIN="manual"' "${PKG_DIR}/package.mk" || fail "package.mk should use manual toolchain"
grep -q 'nix-portable-install' "${PKG_DIR}/package.mk" || fail "package.mk does not install nix-portable-install"
grep -q 'nix-doctor' "${PKG_DIR}/package.mk" || fail "package.mk does not install nix-doctor"
grep -q 'mkdir -p ${INSTALL}/nix' "${PKG_DIR}/package.mk" || fail "package.mk does not create /nix mountpoint"
grep -q 'enable_service nix-storage-setup.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix-storage-setup.service"
grep -q 'enable_service nix.mount' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix.mount"

[ -f "${PKG_DIR}/profile.d/085-nix-integration.conf" ] || fail "missing profile integration"
sh -n "${PKG_DIR}/profile.d/085-nix-integration.conf" || fail "profile integration syntax failed"
grep -q 'NP_RUNTIME="proot"' "${PKG_DIR}/profile.d/085-nix-integration.conf" || fail "profile does not default NP_RUNTIME to proot"

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

[ -f "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" ] || fail "missing runtime smoke test"
sh -n "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke syntax failed"

printf 'nix-integration static checks passed\n'
