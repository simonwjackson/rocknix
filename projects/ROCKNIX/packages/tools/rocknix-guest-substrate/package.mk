# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rocknix-guest-substrate"
PKG_VERSION="0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/ROCKNIX/distribution"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="rocknix-guest-substrate: SM8550 main-space guest substrate for ROCKNIX"
PKG_TOOLCHAIN="manual"

# Pinned source of the NixOS main-space guest. The host repo carries
# only the substrate plumbing for the guest; the guest itself lives in
# https://github.com/simonwjackson/rocknix-nix-guest and is fetched
# from a pinned commit at build time. Bump PKG_NIX_GUEST_REV (and the
# accompanying SHA256 of the GitHub-rendered tarball) to roll the host
# to a newer guest release. The closure layout dropped into
# /usr/lib/rocknix-guest-substrate/guest/ remains byte-identical to the
# old in-tree guest/ subtree -- only the source of truth moved.
PKG_NIX_GUEST_REV="64bfb9993198554c47974248dd581c76c435fc1e"
PKG_NIX_GUEST_SHA256="da9d9e34f0c16fb4b9e68161e9150208b9a3d66d1cfb7a39471580074ef546b7"
PKG_NIX_GUEST_URL="https://github.com/simonwjackson/rocknix-nix-guest/archive/${PKG_NIX_GUEST_REV}.tar.gz"

post_install() {
  # rocknix-guest-substrate is an SM8550-only package. Other devices do
  # not have the validated guest closure (Tier A-E spike series ran on
  # Thor/SM8550) and should not include this package.
  if [ "${DEVICE}" != "SM8550" ]; then
    echo "rocknix-guest-substrate: SM8550-only (got DEVICE=${DEVICE})" >&2
    exit 1
  fi

  substrate_lib="${INSTALL}/usr/lib/rocknix-guest-substrate"
  compat_lib="${INSTALL}/usr/lib/nix-integration"

  mkdir -p ${INSTALL}/nix
  chmod 0755 ${INSTALL}/nix

  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-prep ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-promote ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-recovery-toggle ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-soak ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-udev-stage ${INSTALL}/usr/bin
  chmod 0755 \
    ${INSTALL}/usr/bin/rocknix-guest-prep \
    ${INSTALL}/usr/bin/rocknix-guest-promote \
    ${INSTALL}/usr/bin/rocknix-recovery-toggle \
    ${INSTALL}/usr/bin/rocknix-guest-soak \
    ${INSTALL}/usr/bin/rocknix-guest-udev-stage

  mkdir -p "${substrate_lib}/tests"
  cp ${PKG_DIR}/tests/guest-substrate-runtime-smoke.sh "${substrate_lib}/tests"
  chmod 0755 "${substrate_lib}/tests/guest-substrate-runtime-smoke.sh"

  # Fetch the pinned rocknix-nix-guest source and stage it under
  # /usr/lib/rocknix-guest-substrate/guest/. Cached under ${SOURCES}/ so
  # repeat builds (and the fast-iter image-only workflow) hit the
  # cache instead of GitHub. SHA256 verification is mandatory.
  guest_tarball="${SOURCES}/rocknix-nix-guest/rocknix-nix-guest-${PKG_NIX_GUEST_REV}.tar.gz"
  if [ ! -f "${guest_tarball}" ]; then
    mkdir -p "$(dirname "${guest_tarball}")"
    echo "rocknix-guest-substrate: fetching rocknix-nix-guest ${PKG_NIX_GUEST_REV}"
    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
         --output "${guest_tarball}.tmp" "${PKG_NIX_GUEST_URL}"
    actual_sha="$(sha256sum "${guest_tarball}.tmp" | awk '{print $1}')"
    if [ "${actual_sha}" != "${PKG_NIX_GUEST_SHA256}" ]; then
      echo "rocknix-guest-substrate: rocknix-nix-guest tarball SHA256 mismatch" >&2
      echo "  expected: ${PKG_NIX_GUEST_SHA256}" >&2
      echo "  actual:   ${actual_sha}" >&2
      rm -f "${guest_tarball}.tmp"
      exit 1
    fi
    mv "${guest_tarball}.tmp" "${guest_tarball}"
  fi

  guest_extract="${PKG_BUILD}/.rocknix-nix-guest"
  rm -rf "${guest_extract}"
  mkdir -p "${guest_extract}"
  tar -xzf "${guest_tarball}" -C "${guest_extract}" --strip-components=1

  mkdir -p "${substrate_lib}/guest"
  cp -PR "${guest_extract}/." "${substrate_lib}/guest/"
  printf '%s\n' "${PKG_NIX_GUEST_REV}" > "${substrate_lib}/guest-revision"
  printf '%s\n' "${PKG_NIX_GUEST_REV}" > "${substrate_lib}/guest/.rocknix-guest-revision"

  # Contract docs are owned by rocknix-nix-guest under docs/contracts/.
  # Copy the two that the host ships on-image from the fetched tarball.
  mkdir -p "${substrate_lib}/docs"
  cp "${guest_extract}/docs/contracts/layer14-main-space-contract.md" "${substrate_lib}/docs/"
  cp "${guest_extract}/docs/contracts/layer14-soak-checklist.md" "${substrate_lib}/docs/"

  # Transitional compatibility for live runbooks and old drop-ins that still
  # point at /usr/lib/nix-integration. The active package identity is
  # rocknix-guest-substrate; this alias can be removed after devices have
  # validated the new substrate naming.
  mkdir -p "${INSTALL}/usr/lib"
  rm -rf "${compat_lib}"
  ln -s rocknix-guest-substrate "${compat_lib}"

  enable_service nix-storage-setup.service
  enable_service nix.mount

  # Main-space wiring. SM8550 always boots the NixOS guest by default;
  # ROCKNIX remains the recovery plane via rocknix-recovery-toggle.
  enable_service rocknix-main-space.target
  enable_service rocknix-guest.service
  enable_service rocknix-guest-promote.service
  enable_service rocknix-recovery-toggle.service

  # Ship the recovery readme to /flash/. Pulled from the fetched
  # rocknix-nix-guest tarball (docs/contracts/HOW-TO-FALL-BACK.md) so
  # a teardown / SD-card reader on another machine can read it without
  # booting Thor.
  mkdir -p ${INSTALL}/flash
  cp "${guest_extract}/docs/contracts/HOW-TO-FALL-BACK.md" ${INSTALL}/flash/HOW-TO-FALL-BACK.md
  if [ "${SM8550_MINIMAL_HOST:-no}" = "yes" ]; then
    cat >> ${INSTALL}/flash/HOW-TO-FALL-BACK.md <<'EOF'

## SM8550 minimal-host recovery note

This image is built with `SM8550_MINIMAL_HOST=yes`. Recovery mode is
SSH-first: `/flash/rocknix.no-nspawn` or `rocknix.safe=1` routes the next
boot to `multi-user.target` so host SSH, storage, and `/storage/.update/`
remain available without starting the legacy ROCKNIX UI stack. Remove the
flag file and reboot to return to the NixOS guest main-space target.
EOF
  fi

}
