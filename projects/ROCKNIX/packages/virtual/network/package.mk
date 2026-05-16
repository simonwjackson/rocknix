# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team CoreELEC (https://coreelec.org)

PKG_NAME="network"
PKG_VERSION=""
PKG_LICENSE="various"
PKG_SITE="https://libreelec.tv"
PKG_URL=""
if [ "${SM8550_MINIMAL_HOST:-no}" = "yes" ]; then
  # Minimal SM8550 host keeps the recovery/update substrate reachable even
  # when the guest cannot boot: host Wi-Fi, SSH, transfer tooling, and basic
  # name resolution stay on the host. Product-facing network services
  # (tailscale, avahi, miniupnpc, speedtest-cli, samba, simple-http-server,
  # zerotier, wireguard) move to the guest or disappear from the host image.
  PKG_DEPENDS_TARGET="toolchain iwd networkmanager netbase ethtool openssh iw wireless-regdb rsync nss-mdns"
else
  PKG_DEPENDS_TARGET="toolchain iwd networkmanager netbase ethtool openssh iw wireless-regdb rsync tailscale avahi miniupnpc nss-mdns speedtest-cli"
fi
PKG_SECTION="virtual"
PKG_LONGDESC="Metapackage for various packages to install network support"

if [ "${BLUETOOTH_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} bluez dbussy"
fi

if [ "${SAMBA_SERVER}" = "yes" ] || [ "$SAMBA_SUPPORT" = "yes" ]; then
  PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} samba"
fi

if [ "${SIMPLE_HTTP_SERVER}" = "yes" ]; then
  PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} simple-http-server"
fi

if [ "${OPENVPN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} openvpn"
fi

if [ "${WIREGUARD_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} wireguard-tools"
fi

if [ "${ZEROTIER_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} zerotier-one"
fi

# nss needed by inputstream.adaptive, chromium etc.
if [ "${TARGET_ARCH}" = "x86_64" ] || [ "${TARGET_ARCH}" = "arm" ]; then
  PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} nss"
fi
