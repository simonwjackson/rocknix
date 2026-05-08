# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="nix-integration"
PKG_VERSION="0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/ROCKNIX/distribution"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="nix-integration: custom-image Nix tooling for ROCKNIX"
PKG_TOOLCHAIN="manual"

NIX_DAEMON_SUPPORT="${NIX_DAEMON_SUPPORT:-no}"
NIX_DAEMON_BUILD_GROUP="${NIX_DAEMON_BUILD_GROUP:-nixbld}"
NIX_DAEMON_BUILD_GROUP_ID="${NIX_DAEMON_BUILD_GROUP_ID:-30000}"
NIX_DAEMON_BUILD_USER_ID_FIRST="${NIX_DAEMON_BUILD_USER_ID_FIRST:-30001}"
NIX_DAEMON_BUILD_USER_COUNT="${NIX_DAEMON_BUILD_USER_COUNT:-10}"

# Layer 14 thin-host main-space build flag. SM8550-only.
THIN_HOST="${THIN_HOST:-no}"

post_install() {
  # Layer 14 hard guard: THIN_HOST=yes is SM8550-only. Other devices
  # do not have the validated guest closure (Tier A-E spike series
  # ran on Thor/SM8550) and we refuse to ship the build flag for them.
  if [ "${THIN_HOST}" = "yes" ] && [ "${DEVICE}" != "SM8550" ]; then
    echo "Layer 14 nix-integration: THIN_HOST=yes is SM8550-only (got DEVICE=${DEVICE})" >&2
    exit 1
  fi

  mkdir -p ${INSTALL}/nix
  chmod 0755 ${INSTALL}/nix

  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/nix-doctor ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/nix-layer-activate ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/nixctl ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-layer14-prep ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-host-reclaim ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-recovery-toggle ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-layer14-soak ${INSTALL}/usr/bin
  chmod 0755 \
    ${INSTALL}/usr/bin/nix-doctor \
    ${INSTALL}/usr/bin/nix-layer-activate \
    ${INSTALL}/usr/bin/nixctl \
    ${INSTALL}/usr/bin/rocknix-layer14-prep \
    ${INSTALL}/usr/bin/rocknix-host-reclaim \
    ${INSTALL}/usr/bin/rocknix-recovery-toggle \
    ${INSTALL}/usr/bin/rocknix-layer14-soak

  mkdir -p ${INSTALL}/usr/lib/nix-integration/tests
  cp ${PKG_DIR}/tests/nix-integration-runtime-smoke.sh ${INSTALL}/usr/lib/nix-integration/tests
  chmod 0755 ${INSTALL}/usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh

  mkdir -p ${INSTALL}/usr/lib/nix-integration/modules
  cp -PR ${PKG_DIR}/modules/. ${INSTALL}/usr/lib/nix-integration/modules/

  mkdir -p ${INSTALL}/usr/lib/nix-integration/guest
  cp -PR ${PKG_DIR}/guest/. ${INSTALL}/usr/lib/nix-integration/guest/

  mkdir -p ${INSTALL}/usr/lib/nix-integration/docs
  cp ${PKG_DIR}/docs/layer14-main-space-contract.md ${INSTALL}/usr/lib/nix-integration/docs/
  cp ${PKG_DIR}/docs/layer14-soak-checklist.md ${INSTALL}/usr/lib/nix-integration/docs/

  enable_service nix-storage-setup.service
  enable_service nix.mount

  # rocknix-recovery-toggle.service runs before sysinit on every boot.
  # Under THIN_HOST=no it falls back cleanly to graphical.target (the
  # rocknix-graphical.target unit is absent), so it is safe to enable
  # unconditionally and provides the per-boot recovery hook even on
  # legacy builds where someone wants to opt-in via cmdline later.
  enable_service rocknix-recovery-toggle.service

  # Layer 14 main-space wiring. Only enabled under THIN_HOST=yes; the
  # unit and target are SHIPPED on disk regardless so a soak run
  # (running rocknix-guest-v2 alongside the legacy host UI) is
  # possible without rebuilding the image.
  if [ "${THIN_HOST}" = "yes" ]; then
    cp ${PKG_DIR}/system.d/rocknix-graphical.target ${INSTALL}/usr/lib/systemd/system/
    enable_service rocknix-graphical.target
    enable_service rocknix-guest-v2.service

    # Ship the recovery readme to /flash/. Built from the in-package
    # docs/HOW-TO-FALL-BACK.md so a teardown / SD-card reader on
    # another machine can read it without booting Thor.
    mkdir -p ${INSTALL}/flash
    cp ${PKG_DIR}/docs/HOW-TO-FALL-BACK.md ${INSTALL}/flash/HOW-TO-FALL-BACK.md
  fi

  if [ "${NIX_DAEMON_SUPPORT}" = "yes" ]; then
    add_group "${NIX_DAEMON_BUILD_GROUP}" "${NIX_DAEMON_BUILD_GROUP_ID}"
    i=1
    while [ "${i}" -le "${NIX_DAEMON_BUILD_USER_COUNT}" ]; do
      uid=$((NIX_DAEMON_BUILD_USER_ID_FIRST + i - 1))
      add_user "nixbld${i}" x "${uid}" "${NIX_DAEMON_BUILD_GROUP_ID}" "Nix build user ${i}" "/var/empty" "/bin/false"
      i=$((i + 1))
    done
  fi
}
