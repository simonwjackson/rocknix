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
PKG_NIX_GUEST_REV="d7d5d72821c509ba42b15f2663cd1bfa2e7c5229"
PKG_NIX_GUEST_SHA256="60f49d95006f6064fa3578b1947a91c6a0b3704718684f6f4e1d19819507165a"
PKG_NIX_GUEST_URL="https://github.com/simonwjackson/rocknix-nix-guest/archive/${PKG_NIX_GUEST_REV}.tar.gz"

# Bootable first-boot guest rootfs seed. This must be a prebuilt tarball
# produced from the rocknix-nix-guest rootfs/rootfs-thor flake output for the
# same guest revision. It is intentionally distinct from PKG_NIX_GUEST_URL:
# source can be promoted by a running guest, but fresh /storage needs a
# bootable rootfs seed before rocknix-guest.service can start. Leave these
# placeholders unset only while developing the substrate; post_install fails
# closed until a real URL and SHA256 are provided.
PKG_NIX_GUEST_ROOTFS_SEED_REV="${PKG_NIX_GUEST_REV}"
PKG_NIX_GUEST_ROOTFS_SEED_SHA256="REPLACE_WITH_BOOTABLE_ROOTFS_SEED_SHA256"
PKG_NIX_GUEST_ROOTFS_SEED_URL=""

post_install() {
  # rocknix-guest-substrate is an SM8550-only package. Other devices do
  # not have the validated guest closure (Tier A-E spike series ran on
  # Thor/SM8550) and should not include this package.
  if [ "${DEVICE}" != "SM8550" ]; then
    echo "rocknix-guest-substrate: SM8550-only (got DEVICE=${DEVICE})" >&2
    exit 1
  fi

  substrate_lib="${INSTALL}/usr/lib/rocknix-guest-substrate"

  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-root-ensure ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-prep ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-promote ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-start ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-recovery-toggle ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-soak ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-udev-stage ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-wifi-unblock ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-generation-import ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-generation-switch ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/rocknix-guest-activation-audit ${INSTALL}/usr/bin
  chmod 0755 \
    ${INSTALL}/usr/bin/rocknix-guest-root-ensure \
    ${INSTALL}/usr/bin/rocknix-guest-prep \
    ${INSTALL}/usr/bin/rocknix-guest-promote \
    ${INSTALL}/usr/bin/rocknix-guest-start \
    ${INSTALL}/usr/bin/rocknix-recovery-toggle \
    ${INSTALL}/usr/bin/rocknix-guest-soak \
    ${INSTALL}/usr/bin/rocknix-guest-udev-stage \
    ${INSTALL}/usr/bin/rocknix-guest-wifi-unblock \
    ${INSTALL}/usr/bin/rocknix-guest-generation-import \
    ${INSTALL}/usr/bin/rocknix-guest-generation-switch \
    ${INSTALL}/usr/bin/rocknix-guest-activation-audit

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

  actual_sha="$(sha256sum "${guest_tarball}" | awk '{print $1}')"
  if [ "${actual_sha}" != "${PKG_NIX_GUEST_SHA256}" ]; then
    echo "rocknix-guest-substrate: cached rocknix-nix-guest tarball SHA256 mismatch" >&2
    echo "  expected: ${PKG_NIX_GUEST_SHA256}" >&2
    echo "  actual:   ${actual_sha}" >&2
    exit 1
  fi

  guest_extract="${PKG_BUILD}/.rocknix-nix-guest"
  rm -rf "${guest_extract}"
  mkdir -p "${guest_extract}"
  tar -xzf "${guest_tarball}" -C "${guest_extract}" --strip-components=1

  mkdir -p "${substrate_lib}/guest"
  cp -PR "${guest_extract}/." "${substrate_lib}/guest/"
  printf '%s\n' "${PKG_NIX_GUEST_REV}" > "${substrate_lib}/guest-revision"
  printf '%s\n' "${PKG_NIX_GUEST_REV}" > "${substrate_lib}/guest/.rocknix-guest-revision"

  if [ -z "${PKG_NIX_GUEST_ROOTFS_SEED_URL}" ] || [ "${PKG_NIX_GUEST_ROOTFS_SEED_SHA256}" = "REPLACE_WITH_BOOTABLE_ROOTFS_SEED_SHA256" ]; then
    echo "rocknix-guest-substrate: bootable guest rootfs seed URL/SHA256 are not configured" >&2
    echo "  Build and publish rocknix-nix-guest .#rootfs-thor for ${PKG_NIX_GUEST_ROOTFS_SEED_REV}, then set:" >&2
    echo "  PKG_NIX_GUEST_ROOTFS_SEED_URL and PKG_NIX_GUEST_ROOTFS_SEED_SHA256" >&2
    exit 1
  fi

  seed_ext="${PKG_NIX_GUEST_ROOTFS_SEED_URL##*.}"
  seed_tarball="${SOURCES}/rocknix-nix-guest/rocknix-guest-rootfs-seed-${PKG_NIX_GUEST_ROOTFS_SEED_REV}.tar.${seed_ext}"
  if [ ! -f "${seed_tarball}" ]; then
    mkdir -p "$(dirname "${seed_tarball}")"
    echo "rocknix-guest-substrate: fetching bootable guest rootfs seed ${PKG_NIX_GUEST_ROOTFS_SEED_REV}"
    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
         --output "${seed_tarball}.tmp" "${PKG_NIX_GUEST_ROOTFS_SEED_URL}"
    actual_seed_sha="$(sha256sum "${seed_tarball}.tmp" | awk '{print $1}')"
    if [ "${actual_seed_sha}" != "${PKG_NIX_GUEST_ROOTFS_SEED_SHA256}" ]; then
      echo "rocknix-guest-substrate: bootable guest rootfs seed SHA256 mismatch" >&2
      echo "  expected: ${PKG_NIX_GUEST_ROOTFS_SEED_SHA256}" >&2
      echo "  actual:   ${actual_seed_sha}" >&2
      rm -f "${seed_tarball}.tmp"
      exit 1
    fi
    mv "${seed_tarball}.tmp" "${seed_tarball}"
  fi

  actual_seed_sha="$(sha256sum "${seed_tarball}" | awk '{print $1}')"
  if [ "${actual_seed_sha}" != "${PKG_NIX_GUEST_ROOTFS_SEED_SHA256}" ]; then
    echo "rocknix-guest-substrate: cached bootable guest rootfs seed SHA256 mismatch" >&2
    echo "  expected: ${PKG_NIX_GUEST_ROOTFS_SEED_SHA256}" >&2
    echo "  actual:   ${actual_seed_sha}" >&2
    exit 1
  fi

  seed_extract="${PKG_BUILD}/.rocknix-guest-rootfs-seed"
  rm -rf "${seed_extract}"
  mkdir -p "${seed_extract}"
  case "${seed_tarball}" in
    *.tar.zst) tar --zstd -xf "${seed_tarball}" -C "${seed_extract}" ;;
    *.tar.gz|*.tgz) tar -xzf "${seed_tarball}" -C "${seed_extract}" ;;
    *.tar) tar -xf "${seed_tarball}" -C "${seed_extract}" ;;
    *) echo "rocknix-guest-substrate: unsupported rootfs seed archive format: ${seed_tarball}" >&2; exit 1 ;;
  esac

  [ -d "${seed_extract}/nix" ] || { echo "rocknix-guest-substrate: rootfs seed missing /nix" >&2; exit 1; }
  [ -d "${seed_extract}/etc" ] || { echo "rocknix-guest-substrate: rootfs seed missing /etc" >&2; exit 1; }
  [ -d "${seed_extract}/sbin" ] || { echo "rocknix-guest-substrate: rootfs seed missing /sbin" >&2; exit 1; }
  seed_profile="${seed_extract}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  [ -L "${seed_profile}" ] || { echo "rocknix-guest-substrate: rootfs seed missing selected rocknix-guest-system profile" >&2; exit 1; }
  seed_profile_target="$(readlink "${seed_profile}" 2>/dev/null || true)"
  case "${seed_profile_target}" in
    /nix/*) seed_system="${seed_profile_target}" ;;
    '') echo "rocknix-guest-substrate: rootfs seed selected profile is empty" >&2; exit 1 ;;
    *) seed_system="$(readlink "$(dirname "${seed_profile}")/${seed_profile_target}" 2>/dev/null || true)" ;;
  esac
  case "${seed_system}" in
    /nix/*) : ;;
    *) echo "rocknix-guest-substrate: rootfs seed selected profile does not resolve under /nix" >&2; exit 1 ;;
  esac
  [ -x "${seed_extract}${seed_system}/init" ] || { echo "rocknix-guest-substrate: rootfs seed selected profile init is not executable: ${seed_system}/init" >&2; exit 1; }
  [ -L "${seed_extract}/init" ] || { echo "rocknix-guest-substrate: rootfs seed missing /init symlink" >&2; exit 1; }
  [ -L "${seed_extract}/sbin/init" ] || { echo "rocknix-guest-substrate: rootfs seed missing /sbin/init symlink" >&2; exit 1; }

  mkdir -p "${substrate_lib}/guest-rootfs-seed"
  cp -PR "${seed_extract}/." "${substrate_lib}/guest-rootfs-seed/"
  {
    printf 'revision=%s\n' "${PKG_NIX_GUEST_ROOTFS_SEED_REV}"
    printf 'sha256=%s\n' "${PKG_NIX_GUEST_ROOTFS_SEED_SHA256}"
    printf 'source=%s\n' "${PKG_NIX_GUEST_ROOTFS_SEED_URL}"
  } > "${substrate_lib}/guest-rootfs-seed/.rocknix-guest-rootfs-seed"

  # Contract docs are owned by rocknix-nix-guest under docs/contracts/.
  # Copy the two that the host ships on-image from the fetched tarball.
  mkdir -p "${substrate_lib}/docs"
  cp "${guest_extract}/docs/contracts/layer14-main-space-contract.md" "${substrate_lib}/docs/"
  cp "${guest_extract}/docs/contracts/layer14-soak-checklist.md" "${substrate_lib}/docs/"

  # Main-space wiring. SM8550 always boots the NixOS guest by default;
  # ROCKNIX remains the recovery plane via rocknix-recovery-toggle.
  enable_service rocknix-main-space.target
  enable_service rocknix-guest-root-ensure.service
  enable_service rocknix-guest.service
  enable_service rocknix-guest-wifi-ready.service
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
