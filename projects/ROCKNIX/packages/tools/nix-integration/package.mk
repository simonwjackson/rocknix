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

# Pinned source of the Nix main-space guest. The host repo carries
# only the bootstrap plumbing for the guest; the guest itself lives in
# https://github.com/simonwjackson/rocknix-nix-guest and is fetched
# from a pinned commit at build time. Bump PKG_NIX_GUEST_REV (and the
# accompanying SHA256 of the GitHub-rendered tarball) to roll the host
# to a newer guest release. The closure layout dropped into
# /usr/lib/nix-integration/guest/ remains byte-identical to the old
# in-tree guest/ subtree -- only the source of truth moved.
PKG_NIX_GUEST_REV="9c8b65354bb9558c8a891163f4ddf182642b0367"
PKG_NIX_GUEST_SHA256="0b5be6020609e31a63bed073a87b7b14cc7e66f7456e7a9002becee5a5f38bb2"
PKG_NIX_GUEST_URL="https://github.com/simonwjackson/rocknix-nix-guest/archive/${PKG_NIX_GUEST_REV}.tar.gz"

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
  cp ${PKG_DIR}/scripts/rocknix-guest-udev-stage ${INSTALL}/usr/bin
  chmod 0755 \
    ${INSTALL}/usr/bin/nix-doctor \
    ${INSTALL}/usr/bin/nix-layer-activate \
    ${INSTALL}/usr/bin/nixctl \
    ${INSTALL}/usr/bin/rocknix-layer14-prep \
    ${INSTALL}/usr/bin/rocknix-host-reclaim \
    ${INSTALL}/usr/bin/rocknix-recovery-toggle \
    ${INSTALL}/usr/bin/rocknix-layer14-soak \
    ${INSTALL}/usr/bin/rocknix-guest-udev-stage

  mkdir -p ${INSTALL}/usr/lib/nix-integration/tests
  cp ${PKG_DIR}/tests/nix-integration-runtime-smoke.sh ${INSTALL}/usr/lib/nix-integration/tests
  chmod 0755 ${INSTALL}/usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh

  mkdir -p ${INSTALL}/usr/lib/nix-integration/modules
  cp -PR ${PKG_DIR}/modules/. ${INSTALL}/usr/lib/nix-integration/modules/

  # Fetch the pinned rocknix-nix-guest source and stage it under
  # /usr/lib/nix-integration/guest/. Cached under ${SOURCES}/ so
  # repeat builds (and the fast-iter image-only workflow) hit the
  # cache instead of GitHub. SHA256 verification is mandatory.
  guest_tarball="${SOURCES}/rocknix-nix-guest/rocknix-nix-guest-${PKG_NIX_GUEST_REV}.tar.gz"
  if [ ! -f "${guest_tarball}" ]; then
    mkdir -p "$(dirname "${guest_tarball}")"
    echo "nix-integration: fetching rocknix-nix-guest ${PKG_NIX_GUEST_REV}"
    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
         --output "${guest_tarball}.tmp" "${PKG_NIX_GUEST_URL}"
    actual_sha="$(sha256sum "${guest_tarball}.tmp" | awk '{print $1}')"
    if [ "${actual_sha}" != "${PKG_NIX_GUEST_SHA256}" ]; then
      echo "nix-integration: rocknix-nix-guest tarball SHA256 mismatch" >&2
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

  mkdir -p ${INSTALL}/usr/lib/nix-integration/guest
  cp -PR "${guest_extract}/." ${INSTALL}/usr/lib/nix-integration/guest/

  # Contract docs are owned by rocknix-nix-guest under docs/contracts/.
  # Copy the two that the host ships on-image from the fetched tarball.
  mkdir -p ${INSTALL}/usr/lib/nix-integration/docs
  cp "${guest_extract}/docs/contracts/layer14-main-space-contract.md" ${INSTALL}/usr/lib/nix-integration/docs/
  cp "${guest_extract}/docs/contracts/layer14-soak-checklist.md" ${INSTALL}/usr/lib/nix-integration/docs/

  enable_service nix-storage-setup.service
  enable_service nix.mount

  # Layer 14 main-space wiring. The whole boot-routing / runtime block
  # (recovery-toggle service, rocknix-graphical.target, guest unit
  # WantedBy that target) is gated strictly behind THIN_HOST=yes so a
  # legacy (THIN_HOST=no) image is byte-equivalent to today's modulo
  # inert files in /usr/bin/ and /usr/lib/systemd/system/.
  #
  # Lesson from the first flash on Thor (2026-05-08): scripts/install
  # globs system.d/*.* unconditionally, so rocknix-graphical.target
  # ends up on disk even when this conditional `cp` is skipped. The
  # target's mere presence let the toggle's existence-check fire and
  # rewrite default.target, breaking the THIN_HOST=no contract. Fix
  # below: under THIN_HOST=no, safe_remove the target after the glob
  # has copied it; under THIN_HOST=yes, leave it in place.
  if [ "${THIN_HOST}" = "yes" ]; then
    enable_service rocknix-graphical.target
    enable_service rocknix-guest-v2.service

    # rocknix-recovery-toggle.service runs Before=sysinit.target and
    # is what selects between rocknix-graphical.target (main-space)
    # and graphical.target (legacy recovery) on every THIN_HOST=yes
    # boot. It must NOT be enabled under THIN_HOST=no -- there is no
    # rocknix-graphical.target to escape FROM, and silently rewriting
    # default.target would violate the legacy-equivalent contract.
    enable_service rocknix-recovery-toggle.service

    # Ship the recovery readme to /flash/. Pulled from the fetched
    # rocknix-nix-guest tarball (docs/contracts/HOW-TO-FALL-BACK.md) so
    # a teardown / SD-card reader on another machine can read it without
    # booting Thor.
    mkdir -p ${INSTALL}/flash
    cp "${guest_extract}/docs/contracts/HOW-TO-FALL-BACK.md" ${INSTALL}/flash/HOW-TO-FALL-BACK.md
  else
    # THIN_HOST=no: scrub the target file that scripts/install's glob
    # copied. The file's mere presence on disk would let any future
    # boot-time logic (or a stray manual `systemctl set-default`) flip
    # the device into main-space mode without the build flag's consent.
    safe_remove ${INSTALL}/usr/lib/systemd/system/rocknix-graphical.target
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
