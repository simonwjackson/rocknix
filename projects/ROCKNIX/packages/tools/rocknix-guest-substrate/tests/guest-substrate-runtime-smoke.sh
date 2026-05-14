#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Runtime smoke for the thin-host substrate. This intentionally no longer
# exercises historical Layer 4-12 CLIs (nixctl, nix-doctor, nix-layer-activate):
# those were scaffolding for the path to the current design. The remaining
# runtime contract is small:
#   - guest rootfs has its own /nix store/profile tree
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
  PKG_DIR="/usr/lib/rocknix-guest-substrate"
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
check_executable "${SCRIPT_ROOT}/rocknix-guest-start"
check_executable "${SCRIPT_ROOT}/rocknix-guest-udev-stage"
check_executable "${SCRIPT_ROOT}/rocknix-guest-wifi-unblock"
check_executable "${SCRIPT_ROOT}/rocknix-recovery-toggle"
check_executable "${SCRIPT_ROOT}/rocknix-guest-soak"
check_executable "${SCRIPT_ROOT}/rocknix-guest-generation-import"
check_executable "${SCRIPT_ROOT}/rocknix-guest-generation-switch"
check_executable "${SCRIPT_ROOT}/rocknix-guest-activation-audit"

[ ! -e "${UNIT_ROOT}/nix-storage-setup.service" ] || fail "host nix-storage-setup.service must be retired"
[ ! -e "${UNIT_ROOT}/nix.mount" ] || fail "host nix.mount must be retired"
check_file "${UNIT_ROOT}/rocknix-main-space.target"
check_file "${UNIT_ROOT}/rocknix-guest.service"
check_file "${UNIT_ROOT}/rocknix-guest-promote.service"
check_file "${UNIT_ROOT}/rocknix-guest-wifi-ready.service"
check_file "${UNIT_ROOT}/rocknix-recovery-toggle.service"

for retired_unit in nix-daemon.service nix-daemon.socket; do
  [ ! -e "${UNIT_ROOT}/${retired_unit}" ] || fail "retired host Nix service still installed: ${retired_unit}"
  ! grep -R -q "${retired_unit}" "${UNIT_ROOT}" || fail "unit still references retired host Nix service: ${retired_unit}"
done

guest_unit="${UNIT_ROOT}/rocknix-guest.service"
check_grep 'RequiresMountsFor=/storage' "${guest_unit}" "guest unit must require storage"
if grep -q 'nix.mount' "${guest_unit}" "${UNIT_ROOT}/rocknix-main-space.target" 2>/dev/null; then
  fail "guest units must not require retired host nix.mount"
fi
if grep -q 'RequiresMountsFor=/storage /nix' "${guest_unit}" 2>/dev/null; then
  fail "guest unit must not require host /nix"
fi
check_grep 'StartLimitIntervalSec=5min' "${guest_unit}" "guest unit must bound bad-generation restart loops"
check_grep 'StartLimitBurst=3' "${guest_unit}" "guest unit must cap restart bursts"
check_grep 'StartLimitAction=none' "${guest_unit}" "guest unit must not auto-reboot or auto-recover"
check_grep 'ExecStart=/usr/bin/rocknix-guest-start' "${guest_unit}" "guest unit must use guest start helper"
check_grep '/usr/bin/systemd-nspawn' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must exec systemd-nspawn"
check_grep '--directory=/storage/machines/rocknix-guest' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must target /storage/machines/rocknix-guest"
check_grep '--register=no' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must avoid machined registration"
check_grep 'DeviceAllow=/dev/net/tun rwm' "${guest_unit}" "guest unit must allow tun device access for guest Tailscale"
for device_allow in \
  'DeviceAllow=/dev/uhid rwm' \
  'DeviceAllow=/dev/snd/controlC0 rwm' \
  'DeviceAllow=/dev/snd/pcmC0D0p rwm' \
  'DeviceAllow=/dev/snd/pcmC0D1p rwm' \
  'DeviceAllow=/dev/snd/pcmC0D2c rwm' \
  'DeviceAllow=/dev/snd/timer rwm' \
  'DeviceAllow=char-alsa rwm' \
  'DeviceAllow=/dev/dri/card0 rwm' \
  'DeviceAllow=/dev/dri/renderD128 rwm' \
  'DeviceAllow=/dev/input/event0 rwm' \
  'DeviceAllow=/dev/input/event11 rwm' \
  'DeviceAllow=char-input rwm' \
  'DeviceAllow=char-hidraw rwm' \
  'DeviceAllow=/dev/uinput rwm' \
  'DeviceAllow=/dev/tty0 rwm' \
  'DeviceAllow=/dev/tty1 rwm' \
  'DeviceAllow=/dev/rfkill rwm'; do
  check_grep "${device_allow}" "${guest_unit}" "guest unit must not let tun DeviceAllow block main-space devices: ${device_allow}"
done
check_grep '--capability=CAP_NET_ADMIN' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must retain CAP_NET_ADMIN for guest Tailscale"
check_grep '--capability=CAP_NET_RAW' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must retain CAP_NET_RAW for guest Tailscale"
check_grep '--bind=/dev/net/tun' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must pass through tun for guest Tailscale"
check_grep '--bind=/dev/uhid' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must pass through uhid for guest Bluetooth HID devices"
check_grep '--bind=/dev/uinput' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must pass through uinput for guest InputPlumber"
check_grep '--bind=/storage/.guest' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must keep the single host/guest storage seam"
check_grep 'has_candidate_media_member' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must classify media without probing blocked devices"
if grep -q 'blkid' "${SCRIPT_ROOT}/rocknix-guest-start"; then
  fail "guest start helper must not depend on blkid before runtime DeviceAllow is applied"
fi
check_grep 'is_host_mounted_root' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must guard host-mounted block roots"
check_grep 'systemctl set-property' "${SCRIPT_ROOT}/rocknix-guest-start" "guest start helper must apply exact runtime DeviceAllow entries"
if grep -q 'DeviceAllow=block-sd' "${guest_unit}"; then
  fail "guest unit must not use broad block DeviceAllow classes"
fi
check_grep 'ExecStartPre=/usr/bin/rocknix-guest-prep' "${guest_unit}" "guest unit missing prep helper"
check_grep 'ExecStartPre=/usr/bin/rocknix-guest-udev-stage' "${guest_unit}" "guest unit missing udev stage helper"
if grep -q 'ExecStopPost=' "${guest_unit}"; then
  fail "guest unit must not run host-side fallback/reclaim hooks"
fi
check_grep 'WantedBy=rocknix-main-space.target' "${guest_unit}" "guest unit must install under rocknix-main-space.target"

promote_unit="${UNIT_ROOT}/rocknix-guest-promote.service"
check_grep 'After=rocknix-guest.service' "${promote_unit}" "promotion unit must run after guest boot"
check_grep 'ExecStart=/usr/bin/rocknix-guest-promote' "${promote_unit}" "promotion unit has wrong ExecStart"
check_grep 'WantedBy=rocknix-main-space.target' "${promote_unit}" "promotion unit must install under main-space target"

for forbidden in '--bind-ro=/usr' '--bind-ro=/lib' '--bind-ro=/etc/profile' '--bind=/storage ' '--bind-ro=/storage/roms' '--bind=/storage/.config/Cemu' '--bind=/storage/.config/MangoHud' '--bind=/storage/.local'; do
  if grep -v '^#' "${guest_unit}" | grep -F -q -- "${forbidden}"; then
    fail "guest unit contains forbidden host leak: ${forbidden}"
  fi
done

# Live device checks are opt-in because this script is also run from build/CI
# contexts where systemd and /storage guest roots are absent.
if [ "${ROCKNIX_GUEST_LIVE_SMOKE:-0}" = "1" ]; then
  command -v systemctl >/dev/null 2>&1 || fail "systemctl unavailable for live smoke"

  GUEST_ROOT="${ROCKNIX_GUEST_ROOT:-/storage/machines/rocknix-guest}"
  SELECTED_PROFILE_GUEST="${ROCKNIX_GUEST_SYSTEM_PROFILE:-/nix/var/nix/profiles/per-user/root/rocknix-guest-system}"
  MANUAL_HOLD_FILE="${ROCKNIX_GUEST_MANUAL_HOLD_FILE:-/storage/.guest/rocknix-guest-manual-generation-hold}"

  [ -d "${GUEST_ROOT}" ] || fail "guest root missing: ${GUEST_ROOT}"
  [ -d "${GUEST_ROOT}/nix" ] || fail "guest rootfs /nix missing: ${GUEST_ROOT}/nix"
  if systemctl list-unit-files nix.mount >/dev/null 2>&1; then
    fail "retired host nix.mount is still installed"
  fi
  if mountpoint -q /nix 2>/dev/null; then
    fail "retired host /nix mount is still active"
  fi

  resolve_profile() {
    profile_guest_path="$1"
    profile_path="${GUEST_ROOT}${profile_guest_path}"
    [ -L "${profile_path}" ] || return 1
    target="$(readlink "${profile_path}" 2>/dev/null || true)"
    case "${target}" in
      /nix/*) resolved="${target}" ;;
      '') return 1 ;;
      *) resolved="$(readlink "$(dirname "${profile_path}")/${target}" 2>/dev/null || true)" ;;
    esac
    case "${resolved}" in /nix/*) : ;; *) return 1 ;; esac
    [ -x "${GUEST_ROOT}${resolved}/init" ] || return 1
    printf '%s\n' "${resolved}"
  }

  selected_system="$(resolve_profile "${SELECTED_PROFILE_GUEST}" || true)"
  [ -n "${selected_system}" ] || fail "no valid selected guest system profile"

  systemctl list-unit-files rocknix-main-space.target >/dev/null 2>&1 || fail "rocknix-main-space.target not installed"
  systemctl list-unit-files rocknix-guest.service >/dev/null 2>&1 || fail "rocknix-guest.service not installed"
  systemctl list-unit-files rocknix-guest-promote.service >/dev/null 2>&1 || fail "guest promotion service not installed"
  systemctl list-unit-files rocknix-recovery-toggle.service >/dev/null 2>&1 || fail "recovery toggle service not installed"

  if [ -e "${MANUAL_HOLD_FILE}" ]; then
    echo "WARNING: manual generation hold is active: ${MANUAL_HOLD_FILE}" >&2
  fi

  "${SCRIPT_ROOT}/rocknix-guest-activation-audit" --quiet || fail "guest activation audit failed"

  outer_pid="$(systemctl show -p MainPID --value rocknix-guest.service 2>/dev/null || true)"
  if [ -n "${outer_pid}" ] && [ "${outer_pid}" != "0" ]; then
    inner_pid="$(pgrep -P "${outer_pid}" | head -1 || true)"
    if [ -n "${inner_pid}" ]; then
      running_system="$(readlink "/proc/${inner_pid}/root/run/current-system" 2>/dev/null || true)"
      expected_system="${selected_system:-}"
      if [ -n "${expected_system}" ] && [ -z "${running_system}" ]; then
        fail "running guest /run/current-system missing while expected generation is ${expected_system}"
      fi
      if [ -n "${expected_system}" ] && [ -n "${running_system}" ] && [ "${running_system}" != "${expected_system}" ]; then
        fail "running guest generation drifted: running=${running_system} expected=${expected_system}"
      fi
    fi
  fi
  systemctl list-unit-files sshd.service >/dev/null 2>&1 || fail "sshd.service not installed"
  systemctl is-active --quiet sshd.service || fail "sshd.service must be active for SSH-first recovery"

  default_target=$(systemctl get-default 2>/dev/null || true)
  case "${default_target}" in
    rocknix-main-space.target|multi-user.target) : ;;
    *) fail "default.target points at unexpected target: ${default_target}" ;;
  esac
fi

printf 'rocknix-guest-substrate thin-host runtime smoke passed\n'
