# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="quirks"
PKG_VERSION=""
PKG_LICENSE="GPLv2"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain autostart"
PKG_LONGDESC="Quirks is a simple package that provides device quirks."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/autostart/quirks/{platforms,devices}
  cp -r ${PKG_DIR}/devices/* ${INSTALL}/usr/lib/autostart/quirks/devices
  if [ -d "${PKG_DIR}/platforms/${DEVICE}" ]
  then
    cp -r ${PKG_DIR}/platforms/* ${INSTALL}/usr/lib/autostart/quirks/platforms
  fi
  if [ "${SM8550_MINIMAL_HOST:-no}" = "yes" ]; then
    # These SM8550 quirks only configure the legacy host UI/MangoHud plane.
    # The minimal host has no host compositor or emulator UX; the Nix guest
    # owns those concerns.
    rm -f \
      ${INSTALL}/usr/lib/autostart/quirks/platforms/SM8550/075-mangohud-supported \
      ${INSTALL}/usr/lib/autostart/quirks/platforms/SM8550/090-ui_service \
      ${INSTALL}/usr/lib/autostart/quirks/platforms/SM8550/091-ui_shader
  fi
  chmod -R 0755 ${INSTALL}/usr/lib/autostart/quirks
}

post_install() {
  enable_service led-poweroff.service
  if [ "${DEVICE}" = "RK3566" ]
  then
    enable_service volume-fixup.service
  fi
}
