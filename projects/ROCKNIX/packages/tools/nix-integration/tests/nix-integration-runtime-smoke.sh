#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Runtime smoke for the thin-host substrate. This intentionally no longer
# exercises historical Layer 4-12 CLIs (nixctl, nix-doctor, nix-layer-activate):
# those were scaffolding for the path to the current design. The remaining
# runtime contract is small:
#   - host has a storage-backed /nix mountpoint for the guest rootfs/store
#   - host ships the nspawn guest unit and recovery toggle
#   - the guest unit points at the pinned main-space root and avoids host leaks
#   - optional live mode can verify systemd's current view on device

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Source-tree mode (developer/CI) versus installed mode on ROCKNIX.
if [ -d "${SCRIPT_DIR}/../scripts" ]; then
  PKG_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
  SCRIPT_ROOT="${PKG_DIR}/scripts"
  UNIT_ROOT="${PKG_DIR}/system.d"
else
  PKG_DIR="/usr/lib/nix-integration"
  SCRIPT_ROOT="/usr/bin"
  UNIT_ROOT="/usr/lib/systemd/system"
fi

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

check_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

check_executable() {
  check_file "$1"
  [ -x "$1" ] || fail "not executable: $1"
  sh -n "$1" || fail "shell syntax failed: $1"
}

check_grep() {
  pattern=$1
  file=$2
  message=$3
  grep -q -- "${pattern}" "${file}" || fail "${message}"
}

check_executable "${SCRIPT_ROOT}/rocknix-guest-prep"
check_executable "${SCRIPT_ROOT}/rocknix-guest-promote"
check_executable "${SCRIPT_ROOT}/rocknix-guest-udev-stage"
check_executable "${SCRIPT_ROOT}/rocknix-recovery-toggle"
check_executable "${SCRIPT_ROOT}/rocknix-guest-soak"

check_file "${UNIT_ROOT}/nix-storage-setup.service"
check_file "${UNIT_ROOT}/nix.mount"
check_file "${UNIT_ROOT}/rocknix-graphical.target"
check_file "${UNIT_ROOT}/rocknix-guest-v2.service"
check_file "${UNIT_ROOT}/rocknix-guest-promote.service"
check_file "${UNIT_ROOT}/rocknix-recovery-toggle.service"

guest_unit="${UNIT_ROOT}/rocknix-guest-v2.service"
check_grep 'ExecStart=/usr/bin/systemd-nspawn' "${guest_unit}" "guest unit must use systemd-nspawn"
check_grep '--directory=/storage/machines/rocknix-guest' "${guest_unit}" "guest unit must target /storage/machines/rocknix-guest"
check_grep '--register=no' "${guest_unit}" "guest unit must avoid machined registration"
check_grep 'DeviceAllow=/dev/net/tun rwm' "${guest_unit}" "guest unit must allow tun device access for guest Tailscale"
for device_allow in \
  'DeviceAllow=/dev/snd/\* rwm' \
  'DeviceAllow=/dev/dri/\* rwm' \
  'DeviceAllow=/dev/input/\* rwm' \
  'DeviceAllow=/dev/tty0 rw' \
  'DeviceAllow=/dev/tty1 rw' \
  'DeviceAllow=/dev/rfkill rw'; do
  check_grep "${device_allow}" "${guest_unit}" "guest unit must not let tun DeviceAllow block main-space devices: ${device_allow}"
done
check_grep '--capability=CAP_NET_ADMIN' "${guest_unit}" "guest unit must retain CAP_NET_ADMIN for guest Tailscale"
check_grep '--capability=CAP_NET_RAW' "${guest_unit}" "guest unit must retain CAP_NET_RAW for guest Tailscale"
check_grep '--bind=/dev/net/tun' "${guest_unit}" "guest unit must pass through tun for guest Tailscale"
check_grep 'ExecStartPre=/usr/bin/rocknix-guest-prep' "${guest_unit}" "guest unit missing prep helper"
check_grep 'ExecStartPre=/usr/bin/rocknix-guest-udev-stage' "${guest_unit}" "guest unit missing udev stage helper"
if grep -q 'ExecStopPost=' "${guest_unit}"; then
  fail "guest unit must not run host-side fallback/reclaim hooks"
fi
check_grep 'WantedBy=rocknix-graphical.target' "${guest_unit}" "guest unit must install under rocknix-graphical.target"

promote_unit="${UNIT_ROOT}/rocknix-guest-promote.service"
check_grep 'After=rocknix-guest-v2.service' "${promote_unit}" "promotion unit must run after guest boot"
check_grep 'ExecStart=/usr/bin/rocknix-guest-promote' "${promote_unit}" "promotion unit has wrong ExecStart"
check_grep 'WantedBy=rocknix-graphical.target' "${promote_unit}" "promotion unit must install under graphical target"

for forbidden in '--bind-ro=/usr' '--bind-ro=/lib' '--bind-ro=/etc/profile' '--bind=/storage '; do
  if grep -v '^#' "${guest_unit}" | grep -F -q -- "${forbidden}"; then
    fail "guest unit contains forbidden host leak: ${forbidden}"
  fi
done

# Live device checks are opt-in because this script is also run from build/CI
# contexts where systemd and /storage guest roots are absent.
if [ "${ROCKNIX_GUEST_LIVE_SMOKE:-0}" = "1" ]; then
  command -v systemctl >/dev/null 2>&1 || fail "systemctl unavailable for live smoke"

  [ -d /storage/machines/rocknix-guest ] || fail "guest root missing: /storage/machines/rocknix-guest"
  [ -d /storage/.nix-root ] || fail "storage-backed Nix root missing: /storage/.nix-root"
  [ -d /nix ] || fail "/nix mountpoint missing"

  mountpoint -q /nix || fail "/nix is not mounted"
  systemctl list-unit-files rocknix-graphical.target >/dev/null 2>&1 || fail "rocknix-graphical.target not installed"
  systemctl list-unit-files rocknix-guest-v2.service >/dev/null 2>&1 || fail "rocknix-guest-v2.service not installed"
  systemctl list-unit-files rocknix-guest-promote.service >/dev/null 2>&1 || fail "guest promotion service not installed"
  systemctl list-unit-files rocknix-recovery-toggle.service >/dev/null 2>&1 || fail "recovery toggle service not installed"
  systemctl list-unit-files sshd.service >/dev/null 2>&1 || fail "sshd.service not installed"
  systemctl is-active --quiet sshd.service || fail "sshd.service must be active for SSH-first recovery"

  default_target=$(systemctl get-default 2>/dev/null || true)
  case "${default_target}" in
    rocknix-graphical.target|multi-user.target) : ;;
    *) fail "default.target points at unexpected target: ${default_target}" ;;
  esac
fi

printf 'nix-integration thin-host runtime smoke passed\n'
