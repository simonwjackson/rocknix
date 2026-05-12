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

check_unit() {
  path=$1
  [ -f "${path}" ] || fail "missing unit: ${path}"
}

# Package shape: thin-host bootstrap only. No old Layer 4-13 host CLIs,
# module kit, profile.d hook, or host nix-daemon units should remain.
[ -f "${PKG_DIR}/package.mk" ] || fail "missing package.mk"
sh -n "${PKG_DIR}/package.mk" || fail "package.mk syntax failed"
grep -q 'PKG_NAME="nix-integration"' "${PKG_DIR}/package.mk" || fail "package.mk has wrong PKG_NAME"
grep -q 'PKG_TOOLCHAIN="manual"' "${PKG_DIR}/package.mk" || fail "package.mk should use manual toolchain"

for gone in \
  "${PKG_DIR}/scripts/nixctl" \
  "${PKG_DIR}/scripts/nix-doctor" \
  "${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/modules" \
  "${PKG_DIR}/profile.d" \
  "${PKG_DIR}/system.d/nix-daemon.service" \
  "${PKG_DIR}/system.d/nix-daemon.socket"; do
  [ ! -e "${gone}" ] || fail "removed backward-compat surface still exists: ${gone}"
done

for old_name in nixctl nix-doctor nix-layer-activate 'usr/lib/nix-integration/modules' 'nix-daemon'; do
  ! grep -q "${old_name}" "${PKG_DIR}/package.mk" || fail "package.mk still references removed surface: ${old_name}"
done

# Remaining host scripts are the thin-host guest launcher/recovery support.
check_script "${PKG_DIR}/scripts/rocknix-guest-prep"
check_script "${PKG_DIR}/scripts/rocknix-guest-promote"
check_script "${PKG_DIR}/scripts/rocknix-guest-udev-stage"
check_script "${PKG_DIR}/scripts/rocknix-recovery-toggle"
check_script "${PKG_DIR}/scripts/rocknix-guest-soak"

grep -q 'rocknix-guest-prep' "${PKG_DIR}/package.mk" || fail "package.mk does not install prep helper"
grep -q 'rocknix-guest-promote' "${PKG_DIR}/package.mk" || fail "package.mk does not install guest promotion helper"
grep -q 'rocknix-guest-udev-stage' "${PKG_DIR}/package.mk" || fail "package.mk does not install udev stage helper"
! grep -q 'rocknix-host-reclaim' "${PKG_DIR}/package.mk" || fail "package.mk must not install host reclaim helper"
grep -q 'rocknix-recovery-toggle' "${PKG_DIR}/package.mk" || fail "package.mk does not install recovery toggle"
grep -q 'rocknix-guest-soak' "${PKG_DIR}/package.mk" || fail "package.mk does not install soak helper"

grep -q '/usr/lib/nix-integration/tests' "${PKG_DIR}/package.mk" || fail "package.mk does not install runtime smoke tests"
grep -q 'nix-integration-runtime-smoke.sh' "${PKG_DIR}/package.mk" || fail "package.mk does not package runtime smoke helper"
[ -f "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" ] || fail "missing runtime smoke test"
sh -n "${SCRIPT_DIR}/nix-integration-runtime-smoke.sh" || fail "runtime smoke syntax failed"

# Guest source is fetched from rocknix-nix-guest and verified by SHA256.
grep -q 'PKG_NIX_GUEST_REV=' "${PKG_DIR}/package.mk" || fail "package.mk missing guest rev pin"
grep -q 'PKG_NIX_GUEST_SHA256=' "${PKG_DIR}/package.mk" || fail "package.mk missing guest tarball sha256 pin"
grep -q 'rocknix-nix-guest/archive' "${PKG_DIR}/package.mk" || fail "package.mk missing guest tarball URL"
grep -q 'sha256sum "${guest_tarball}.tmp"' "${PKG_DIR}/package.mk" || fail "package.mk must verify guest tarball sha256"
grep -q 'tar -xzf "${guest_tarball}"' "${PKG_DIR}/package.mk" || fail "package.mk must extract fetched guest tarball"
grep -q 'cp -PR "${guest_extract}/."' "${PKG_DIR}/package.mk" || fail "package.mk must stage fetched guest tree"
grep -q '/usr/lib/nix-integration/guest-revision' "${PKG_DIR}/package.mk" || fail "package.mk must ship packaged guest revision marker"
grep -q 'docs/contracts/layer14-main-space-contract.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship main-space contract doc from guest"
grep -q 'docs/contracts/layer14-soak-checklist.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship soak checklist from guest"
grep -q 'docs/contracts/HOW-TO-FALL-BACK.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship fallback doc from guest"
grep -q 'SM8550_MINIMAL_HOST=yes' "${PKG_DIR}/package.mk" || fail "package.mk must document minimal-host fallback mode when enabled"

# Storage + guest service wiring.
check_unit "${PKG_DIR}/system.d/nix-storage-setup.service"
check_unit "${PKG_DIR}/system.d/nix.mount"
check_unit "${PKG_DIR}/system.d/rocknix-graphical.target"
check_unit "${PKG_DIR}/system.d/rocknix-guest-v2.service"
check_unit "${PKG_DIR}/system.d/rocknix-guest-promote.service"
check_unit "${PKG_DIR}/system.d/rocknix-recovery-toggle.service"

grep -q 'mkdir -p ${INSTALL}/nix' "${PKG_DIR}/package.mk" || fail "package.mk does not create /nix mountpoint"
grep -q 'enable_service nix-storage-setup.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix-storage-setup.service"
grep -q 'enable_service nix.mount' "${PKG_DIR}/package.mk" || fail "package.mk does not enable nix.mount"
grep -q 'enable_service rocknix-graphical.target' "${PKG_DIR}/package.mk" || fail "package.mk does not enable rocknix-graphical.target"
grep -q 'enable_service rocknix-guest-v2.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable rocknix-guest-v2.service"
grep -q 'enable_service rocknix-guest-promote.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable guest promotion service"
grep -q 'enable_service rocknix-recovery-toggle.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable recovery toggle"

grep -q 'RequiresMountsFor=/storage' "${PKG_DIR}/system.d/nix-storage-setup.service" || fail "setup service does not require /storage"
grep -q '/storage/.nix-root' "${PKG_DIR}/system.d/nix-storage-setup.service" || fail "setup service does not prepare storage-backed Nix root"
grep -q 'DefaultDependencies=no' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount should avoid early local-fs ordering"
grep -q 'What=/storage/.nix-root' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount has wrong source"
grep -q 'Where=/nix' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount has wrong target"
grep -q 'Options=bind' "${PKG_DIR}/system.d/nix.mount" || fail "nix.mount is not a bind mount"

grep -q 'Alias=default.target' "${PKG_DIR}/system.d/rocknix-graphical.target" || fail "rocknix-graphical.target must alias default.target"
grep -q 'Wants=rocknix-guest-v2.service' "${PKG_DIR}/system.d/rocknix-graphical.target" || fail "rocknix-graphical.target must start guest unit"
grep -q 'Before=sysinit.target' "${PKG_DIR}/system.d/rocknix-recovery-toggle.service" || fail "recovery toggle must run before sysinit"
grep -q 'ExecStart=/usr/bin/rocknix-recovery-toggle' "${PKG_DIR}/system.d/rocknix-recovery-toggle.service" || fail "recovery toggle unit has wrong ExecStart"

guest_unit="${PKG_DIR}/system.d/rocknix-guest-v2.service"
grep -q 'ExecStartPre=/usr/bin/rocknix-guest-prep' "${guest_unit}" || fail "guest unit missing prep helper"
grep -q 'ExecStartPre=/usr/bin/rocknix-guest-udev-stage' "${guest_unit}" || fail "guest unit missing udev stage helper"
grep -q 'ExecStart=/usr/bin/systemd-nspawn' "${guest_unit}" || fail "guest unit must launch systemd-nspawn"
grep -q -- '--directory=/storage/machines/rocknix-guest' "${guest_unit}" || fail "guest unit has wrong guest root"
grep -q -- '--register=no' "${guest_unit}" || fail "guest unit must avoid machined registration"
grep -q -- '--bind=/dev/input' "${guest_unit}" || fail "guest unit must pass through input devices"
grep -q -- '--bind=/dev/snd' "${guest_unit}" || fail "guest unit must pass through sound devices"
grep -q -- '--bind-ro=/run/.guest-udev:/run/udev' "${guest_unit}" || fail "guest unit must bind scrubbed udev db"
! grep -q 'ExecStopPost=' "${guest_unit}" || fail "guest unit must not run host-side fallback/reclaim hooks"
grep -q 'Restart=on-failure' "${guest_unit}" || fail "guest unit must restart on failure"
grep -q 'WantedBy=rocknix-graphical.target' "${guest_unit}" || fail "guest unit must be wanted by rocknix-graphical.target"

promote_unit="${PKG_DIR}/system.d/rocknix-guest-promote.service"
grep -q 'After=rocknix-guest-v2.service' "${promote_unit}" || fail "guest promotion must run after guest boot"
grep -q 'ExecStart=/usr/bin/rocknix-guest-promote' "${promote_unit}" || fail "guest promotion unit has wrong ExecStart"
grep -q 'WantedBy=rocknix-graphical.target' "${promote_unit}" || fail "guest promotion must be wanted by graphical target"
grep -q 'TimeoutStartSec=60min' "${promote_unit}" || fail "guest promotion needs a long timeout for Nix builds"
grep -q 'nix build' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must build packaged guest configuration"
grep -q 'nix-env -p /nix/var/nix/profiles/system --set' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must update guest system profile"
grep -q 'systemctl restart --no-block rocknix-guest-v2.service' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must restart guest after profile update"
grep -q 'rocknix-guest-revision' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must track applied guest revision"
grep -q 'rocknix-guest-system-path' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must track applied guest system path"
grep -q 'resolve_guest_system_profile' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must inspect persistent guest system profile"
grep -q 'guest_store_path_exists' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must verify applied system path still exists"
grep -q 'system profile drifted' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must repair profile drift when revision marker matches"
grep -q 'applied system path is missing; rebuilding' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must rebuild if revision marker matches but system path is gone"
grep -q 'nsenter .* sh -c' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must avoid login shell nsenter invocations"
! grep -q 'nsenter .* sh -lc' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must not invoke guest login shell"
grep -q '/storage/.guest/rocknix-guest-promote-system-path' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must return system path through shared guest storage"
grep -q '/run/current-system/sw/bin/systemctl is-active NetworkManager.service' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must use absolute guest systemctl for readiness"
! grep -q 'seq 1 60' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must not depend on seq during early guest boot"
grep -q '/run/current-system/sw/bin/sleep 2' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must use absolute guest sleep when available"
for forbidden in '--bind-ro=/usr' '--bind-ro=/lib' '--bind-ro=/etc/profile' '--bind=/storage '; do
  ! grep -v '^#' "${guest_unit}" | grep -F -q -- "${forbidden}" || fail "guest unit still contains forbidden broad bind: ${forbidden}"
done

# Recovery and safety net.
grep -q '/flash/rocknix.no-nspawn' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle missing flag-file escape"
grep -q 'rocknix.safe=1' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle missing cmdline escape"
grep -q 'rocknix-graphical.target' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle missing normal target"
grep -q 'RECOVERY_TARGET="multi-user.target"' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle must route minimal-host recovery to multi-user.target"
grep -q 'systemctl set-default' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle must switch default target"

grep -q 'resolv.conf.guest-owned' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing resolv.conf ownership marker"
grep -q '/storage/.guest' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing guest writable area"
grep -q '/nix/var/nix/profiles/system' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing system profile check"
grep -q 'inputplumber/by-hidden' "${PKG_DIR}/scripts/rocknix-guest-udev-stage" || fail "udev stage must scrub InputPlumber-hidden devices"
grep -q 'check_host_ssh_responsive' "${PKG_DIR}/scripts/rocknix-guest-soak" || fail "soak helper missing host SSH check"
grep -q 'ROCKNIX_REQUIRE_HOST_ESSWAY' "${PKG_DIR}/scripts/rocknix-guest-soak" || fail "soak helper must allow SSH-first recovery without host essway"
grep -q 'check_resolv_owned' "${PKG_DIR}/scripts/rocknix-guest-soak" || fail "soak helper missing resolv ownership check"

# Device gates: only SM8550 ships the guest substrate.
SYSTEMD_PKG="${REPO_ROOT}/projects/ROCKNIX/packages/sysutils/systemd/package.mk"
[ -f "${SYSTEMD_PKG}" ] || fail "missing ROCKNIX systemd package.mk"
grep -q '\[ "\${DEVICE}" = "SM8550" \] && PKG_DEPENDS_TARGET+=" nix-integration"' "${REPO_ROOT}/projects/ROCKNIX/packages/virtual/image/package.mk" \
  || fail "image package must gate nix-integration on DEVICE=SM8550"
grep -q 'SM8550_MINIMAL_HOST' "${REPO_ROOT}/projects/ROCKNIX/devices/SM8550/options" \
  || fail "SM8550 options must expose the minimal-host switch"
grep -q '\[ "\${BASE_ONLY}" = "true" \] || \[ "\${SM8550_MINIMAL_HOST:-no}" = "yes" \]' "${REPO_ROOT}/projects/ROCKNIX/packages/virtual/image/package.mk" \
  || fail "image package must use minimal-host path to skip product UX metas"
grep -q 'SM8550 minimal host pulled a host UX/emulation payload' "${REPO_ROOT}/projects/ROCKNIX/packages/virtual/image/package.mk" \
  || fail "image package must fail closed if minimal host reintroduces UX/emulation payloads"
grep -q 'Minimal SM8550 host keeps only what the recovery/update substrate needs' "${REPO_ROOT}/projects/ROCKNIX/packages/virtual/network/package.mk" \
  || fail "ROCKNIX network meta must document the minimal-host dependency set"
grep -q 'PKG_DEPENDS_TARGET="toolchain iwd networkmanager netbase ethtool openssh iw wireless-regdb rsync nss-mdns"' "${REPO_ROOT}/projects/ROCKNIX/packages/virtual/network/package.mk" \
  || fail "ROCKNIX network meta must have a minimal-host dependency set"
grep -q 'if \[ "${DEVICE}" != "SM8550" \]' "${SYSTEMD_PKG}" \
  || fail "systemd package must strip nspawn on non-SM8550 devices"
grep -q 'safe_remove ${INSTALL}/usr/bin/systemd-nspawn' "${SYSTEMD_PKG}" || fail "systemd package missing nspawn binary removal fallback"
grep -q 'safe_remove ${INSTALL}/usr/lib/systemd/system/systemd-nspawn@.service' "${SYSTEMD_PKG}" || fail "systemd package missing nspawn unit removal fallback"
! grep -qE 'enable_service .*nspawn' "${SYSTEMD_PKG}" || fail "systemd package must not enable nspawn services by default"

# Old support flags should not be resurrected.
! grep -R --exclude='nix-integration-static-checks.sh' -q 'NIX_INTEGRATION_SUPPORT\|NIX_NSPAWN_SUPPORT\|NIX_DAEMON_SUPPORT\|THIN_HOST' \
  "${REPO_ROOT}/projects/ROCKNIX" "${REPO_ROOT}/.github" "${REPO_ROOT}/scripts" || fail "removed support gate still referenced"

printf 'nix-integration static checks passed\n'
