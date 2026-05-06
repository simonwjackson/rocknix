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

post_install() {
  mkdir -p ${INSTALL}/nix
  chmod 0755 ${INSTALL}/nix

  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/nix-doctor ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/nix-layer-activate ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/nixctl ${INSTALL}/usr/bin
  chmod 0755 \
    ${INSTALL}/usr/bin/nix-doctor \
    ${INSTALL}/usr/bin/nix-layer-activate \
    ${INSTALL}/usr/bin/nixctl

  enable_service nix-storage-setup.service
  enable_service nix.mount

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
