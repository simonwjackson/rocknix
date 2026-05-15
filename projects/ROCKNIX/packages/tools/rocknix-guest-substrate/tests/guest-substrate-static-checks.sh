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

assert_order() {
  path=$1
  first=$2
  second=$3
  message=$4
  awk -v first="${first}" -v second="${second}" '
    index($0, first) { seen = 1 }
    seen && index($0, second) { found = 1 }
    END { exit found ? 0 : 1 }
  ' "${path}" || fail "${message}"
}

assert_job_contains() {
  path=$1
  job=$2
  needle=$3
  message=$4
  awk -v job="  ${job}:" -v needle="${needle}" '
    $0 == job { in_job = 1; next }
    in_job && /^  [A-Za-z0-9_-]+:/ { exit found ? 0 : 1 }
    in_job && index($0, needle) { found = 1 }
    END { if (in_job) exit found ? 0 : 1; exit 1 }
  ' "${path}" || fail "${message}"
}

# Package shape: thin-host bootstrap only. No old Layer 4-13 host CLIs,
# module kit, profile.d hook, or host nix-daemon units should remain.
[ -f "${PKG_DIR}/package.mk" ] || fail "missing package.mk"
sh -n "${PKG_DIR}/package.mk" || fail "package.mk syntax failed"
grep -q 'PKG_NAME="rocknix-guest-substrate"' "${PKG_DIR}/package.mk" || fail "package.mk has wrong PKG_NAME"
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

for old_name in nixctl nix-doctor nix-layer-activate 'usr/lib/nix-integration' 'usr/lib/rocknix-guest-substrate/modules' 'nix-daemon'; do
  ! grep -q "${old_name}" "${PKG_DIR}/package.mk" || fail "package.mk still references removed surface: ${old_name}"
done

for old_service in nix-daemon.service nix-daemon.socket; do
  ! grep -R -q "${old_service}" "${PKG_DIR}/system.d" || fail "unit still references removed service: ${old_service}"
done

# Remaining host scripts are the thin-host guest launcher/recovery support.
check_script "${PKG_DIR}/scripts/rocknix-guest-root-ensure"
check_script "${PKG_DIR}/scripts/rocknix-guest-prep"
check_script "${PKG_DIR}/scripts/rocknix-guest-promote"
check_script "${PKG_DIR}/scripts/rocknix-guest-start"
check_script "${PKG_DIR}/scripts/rocknix-guest-udev-stage"
check_script "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock"
check_script "${PKG_DIR}/scripts/rocknix-recovery-toggle"
check_script "${PKG_DIR}/scripts/rocknix-guest-soak"
check_script "${PKG_DIR}/scripts/rocknix-guest-generation-import"
check_script "${PKG_DIR}/scripts/rocknix-guest-generation-switch"
check_script "${PKG_DIR}/scripts/rocknix-guest-activation-audit"

grep -q 'rocknix-guest-root-ensure' "${PKG_DIR}/package.mk" || fail "package.mk does not install guest root ensure helper"
grep -q 'rocknix-guest-prep' "${PKG_DIR}/package.mk" || fail "package.mk does not install prep helper"
grep -q 'rocknix-guest-promote' "${PKG_DIR}/package.mk" || fail "package.mk does not install guest promotion helper"
grep -q 'rocknix-guest-start' "${PKG_DIR}/package.mk" || fail "package.mk does not install guest start helper"
grep -q 'rocknix-guest-udev-stage' "${PKG_DIR}/package.mk" || fail "package.mk does not install udev stage helper"
grep -q 'rocknix-guest-wifi-unblock' "${PKG_DIR}/package.mk" || fail "package.mk does not install guest Wi-Fi unblock helper"
! grep -q 'rocknix-host-reclaim' "${PKG_DIR}/package.mk" || fail "package.mk must not install host reclaim helper"
grep -q 'rocknix-recovery-toggle' "${PKG_DIR}/package.mk" || fail "package.mk does not install recovery toggle"
grep -q 'rocknix-guest-soak' "${PKG_DIR}/package.mk" || fail "package.mk does not install soak helper"
grep -q 'rocknix-guest-generation-import' "${PKG_DIR}/package.mk" || fail "package.mk does not install generation import helper"
grep -q 'rocknix-guest-generation-switch' "${PKG_DIR}/package.mk" || fail "package.mk does not install generation switch helper"
grep -q 'rocknix-guest-activation-audit' "${PKG_DIR}/package.mk" || fail "package.mk does not install activation audit helper"

grep -q 'substrate_lib="${INSTALL}/usr/lib/rocknix-guest-substrate"' "${PKG_DIR}/package.mk" || fail "package.mk does not define substrate lib path"
grep -q 'mkdir -p "${substrate_lib}/tests"' "${PKG_DIR}/package.mk" || fail "package.mk does not install runtime smoke tests"
grep -q 'guest-substrate-runtime-smoke.sh' "${PKG_DIR}/package.mk" || fail "package.mk does not package runtime smoke helper"
[ -f "${SCRIPT_DIR}/guest-substrate-runtime-smoke.sh" ] || fail "missing runtime smoke test"
sh -n "${SCRIPT_DIR}/guest-substrate-runtime-smoke.sh" || fail "runtime smoke syntax failed"

# Guest source is fetched from rocknix-nix-guest and verified by SHA256.
grep -q 'PKG_NIX_GUEST_REV=' "${PKG_DIR}/package.mk" || fail "package.mk missing guest rev pin"
grep -q 'PKG_NIX_GUEST_SHA256=' "${PKG_DIR}/package.mk" || fail "package.mk missing guest tarball sha256 pin"
grep -q 'rocknix-nix-guest/archive' "${PKG_DIR}/package.mk" || fail "package.mk missing guest tarball URL"
grep -q 'sha256sum "${guest_tarball}.tmp"' "${PKG_DIR}/package.mk" || fail "package.mk must verify freshly downloaded guest tarball sha256"
grep -q 'sha256sum "${guest_tarball}"' "${PKG_DIR}/package.mk" || fail "package.mk must verify cached guest tarball sha256 before extraction"
grep -q 'cached rocknix-nix-guest tarball SHA256 mismatch' "${PKG_DIR}/package.mk" || fail "package.mk must fail clearly on cached tarball sha256 mismatch"
assert_order "${PKG_DIR}/package.mk" 'sha256sum "${guest_tarball}.tmp"' 'mv "${guest_tarball}.tmp" "${guest_tarball}"' "package.mk must verify fresh guest tarball before caching it"
assert_order "${PKG_DIR}/package.mk" 'sha256sum "${guest_tarball}"' 'tar -xzf "${guest_tarball}"' "package.mk must verify cached guest tarball before extraction"
grep -q 'tar -xzf "${guest_tarball}"' "${PKG_DIR}/package.mk" || fail "package.mk must extract fetched guest tarball"
grep -q 'cp -PR "${guest_extract}/."' "${PKG_DIR}/package.mk" || fail "package.mk must stage fetched guest tree"
grep -q 'guest-revision' "${PKG_DIR}/package.mk" || fail "package.mk must ship packaged guest revision marker"
grep -q 'docs/contracts/layer14-main-space-contract.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship main-space contract doc from guest"
grep -q 'docs/contracts/layer14-soak-checklist.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship soak checklist from guest"
grep -q 'docs/contracts/HOW-TO-FALL-BACK.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship fallback doc from guest"
grep -q 'SM8550_MINIMAL_HOST=yes' "${PKG_DIR}/package.mk" || fail "package.mk must document minimal-host fallback mode when enabled"
grep -q 'PKG_NIX_GUEST_ROOTFS_SEED_URL=' "${PKG_DIR}/package.mk" || fail "package.mk missing bootable rootfs seed URL contract"
grep -q 'PKG_NIX_GUEST_ROOTFS_SEED_SHA256=' "${PKG_DIR}/package.mk" || fail "package.mk missing bootable rootfs seed SHA256 contract"
grep -q 'PKG_NIX_GUEST_ROOTFS_SEED_COMPATIBLE=' "${PKG_DIR}/package.mk" || fail "package.mk missing bootable rootfs seed compatible contract"
grep -q 'PKG_NIX_GUEST_ROOTFS_SEED_ARCHIVE=' "${PKG_DIR}/package.mk" || fail "package.mk missing bootable rootfs seed archive filename contract"
grep -q 'bootable guest rootfs seed URL/SHA256 are not configured' "${PKG_DIR}/package.mk" || fail "package.mk must fail closed while rootfs seed URL/SHA are placeholders"
grep -q 'guest-rootfs-seed.manifest' "${PKG_DIR}/package.mk" || fail "package.mk must install a rootfs seed manifest"
grep -q 'seed_release_dir="${BUILD}/rocknix-guest-rootfs-seed"' "${PKG_DIR}/package.mk" || fail "package.mk must stage rootfs seed outside SYSTEM for image packaging"
grep -q -- '--output - "${seed_url}" >> "${seed_tarball}.tmp"' "${PKG_DIR}/package.mk" || fail "package.mk must reassemble split seed assets without storing duplicate part files"
! grep -q 'cp "${seed_tarball}" "${substrate_lib}' "${PKG_DIR}/package.mk" || fail "package.mk must not copy the rootfs seed archive into SYSTEM"
! grep -q 'cp -PR "${seed_extract}/."' "${PKG_DIR}/package.mk" || fail "package.mk must not duplicate the expanded rootfs seed during build"

# Storage + guest service wiring. Host root /nix was retired: the guest
# system store lives under /storage/machines/rocknix-guest/nix and is resolved
# through GUEST_ROOT by the substrate scripts.
[ ! -e "${PKG_DIR}/system.d/nix-storage-setup.service" ] || fail "host nix-storage-setup.service must be retired"
[ ! -e "${PKG_DIR}/system.d/nix.mount" ] || fail "host nix.mount must be retired"
check_unit "${PKG_DIR}/system.d/rocknix-main-space.target"
check_unit "${PKG_DIR}/system.d/rocknix-guest-root-ensure.service"
check_unit "${PKG_DIR}/system.d/rocknix-guest.service"
check_unit "${PKG_DIR}/system.d/rocknix-guest-promote.service"
check_unit "${PKG_DIR}/system.d/rocknix-guest-wifi-ready.service"
check_unit "${PKG_DIR}/system.d/rocknix-recovery-toggle.service"

! grep -q 'mkdir -p ${INSTALL}/nix' "${PKG_DIR}/package.mk" || fail "package.mk must not create host /nix mountpoint"
! grep -q 'enable_service nix-storage-setup.service' "${PKG_DIR}/package.mk" || fail "package.mk must not enable nix-storage-setup.service"
! grep -q 'enable_service nix.mount' "${PKG_DIR}/package.mk" || fail "package.mk must not enable nix.mount"
! grep -R -q 'nix.mount' "${PKG_DIR}/system.d" "${PKG_DIR}/package.mk" || fail "host units/package must not require host nix.mount"
grep -q 'enable_service rocknix-main-space.target' "${PKG_DIR}/package.mk" || fail "package.mk does not enable rocknix-main-space.target"
grep -q 'enable_service rocknix-guest-root-ensure.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable guest root ensure service"
grep -q 'enable_service rocknix-guest.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable rocknix-guest.service"
grep -q 'enable_service rocknix-guest-wifi-ready.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable guest Wi-Fi unblock service"
grep -q 'enable_service rocknix-guest-promote.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable guest promotion service"
grep -q 'enable_service rocknix-recovery-toggle.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable recovery toggle"

grep -q 'Alias=default.target' "${PKG_DIR}/system.d/rocknix-main-space.target" || fail "rocknix-main-space.target must alias default.target"
! grep -q 'rocknix-graphical.target' "${PKG_DIR}/system.d/rocknix-main-space.target" || fail "rocknix-main-space.target must not keep old graphical-target alias"
grep -q 'Wants=rocknix-guest-root-ensure.service rocknix-guest.service' "${PKG_DIR}/system.d/rocknix-main-space.target" || fail "rocknix-main-space.target must start root ensure before guest unit"
! grep -q 'rocknix-automount.service' "${PKG_DIR}/system.d/rocknix-main-space.target" || fail "main-space target must not require host game-media automount"
grep -q 'Before=sysinit.target' "${PKG_DIR}/system.d/rocknix-recovery-toggle.service" || fail "recovery toggle audit must run before sysinit"
grep -q 'ExecStart=/usr/bin/rocknix-recovery-toggle' "${PKG_DIR}/system.d/rocknix-recovery-toggle.service" || fail "recovery toggle unit has wrong ExecStart"

ensure_unit="${PKG_DIR}/system.d/rocknix-guest-root-ensure.service"
grep -q 'ExecStart=/usr/bin/rocknix-guest-root-ensure' "${ensure_unit}" || fail "root ensure unit has wrong ExecStart"
grep -q 'Before=rocknix-guest.service rocknix-guest-promote.service rocknix-guest-wifi-ready.service' "${ensure_unit}" || fail "root ensure unit must order before all guest-path services"
grep -q 'RequiresMountsFor=/storage /flash' "${ensure_unit}" || fail "root ensure unit must require storage and flash"
grep -q 'ConditionKernelCommandLine=!rocknix.safe=1' "${ensure_unit}" || fail "root ensure unit must be guarded by rocknix.safe=1"
grep -q 'ConditionPathExists=!/flash/rocknix.no-nspawn' "${ensure_unit}" || fail "root ensure unit must be guarded by sticky recovery flag"
grep -q '/run/lock/rocknix-guest-root.lock' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must use root-owned mutation lock"
grep -q 'guest-rootfs-seed.manifest' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must read packaged rootfs seed manifest"
grep -q 'ROCKNIX_GUEST_ROOTFS_SEED_DIR' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must support local /storage seed staging directory"
grep -q 'ROCKNIX_GUEST_ROOTFS_SEED_ARCHIVE' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must support compressed rootfs seed archive overrides"
grep -q 'verify_seed_archive_sha' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must verify staged seed archive sha256"
grep -q 'first_device_compatible' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must select staged seed by compatible string"
grep -q 'extract_seed_archive' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must extract compressed rootfs seed archives on first boot"
grep -q 'rocknix-guest-root-seed-complete' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must write seed completion marker"
grep -q 'rocknix.reseed-guest' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must expose explicit reseed flag"
grep -q 'guest root mutation lock is held' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must fail closed on concurrent mutation"
grep -q 'is a symlink' "${PKG_DIR}/scripts/rocknix-guest-root-ensure" || fail "root ensure helper must reject symlinked storage paths"

guest_unit="${PKG_DIR}/system.d/rocknix-guest.service"
grep -q 'RequiresMountsFor=/storage /flash' "${guest_unit}" || fail "guest unit must require storage and flash"
! grep -q 'RequiresMountsFor=/storage /nix' "${guest_unit}" || fail "guest unit must not require host /nix"
grep -q 'Requires=rocknix-guest-root-ensure.service' "${guest_unit}" || fail "guest unit must require root ensure service"
grep -q 'After=.*rocknix-guest-root-ensure.service' "${guest_unit}" || fail "guest unit must start after root ensure service"
! grep -q 'ConditionPathExists=/storage/machines/rocknix-guest' "${guest_unit}" || fail "guest unit must not skip fresh installs before root ensure can run"
grep -q 'ConditionKernelCommandLine=!rocknix.safe=1' "${guest_unit}" || fail "guest unit must be guarded by rocknix.safe=1"
grep -q 'ConditionPathExists=!/flash/rocknix.no-nspawn' "${guest_unit}" || fail "guest unit must be guarded by sticky recovery flag"
! grep -q 'Requires=nix.mount' "${guest_unit}" || fail "guest unit must not require host nix.mount"
grep -q 'StartLimitIntervalSec=5min' "${guest_unit}" || fail "guest unit must bound bad-generation restart loops"
grep -q 'StartLimitBurst=3' "${guest_unit}" || fail "guest unit must cap restart bursts"
grep -q 'StartLimitAction=none' "${guest_unit}" || fail "guest unit must not auto-reboot or auto-recover"
grep -q 'ExecStartPre=/usr/bin/rocknix-guest-wifi-unblock --host-only' "${guest_unit}" || fail "guest unit must unblock host Wi-Fi before starting guest"
grep -q 'ExecStartPre=/usr/bin/rocknix-guest-prep' "${guest_unit}" || fail "guest unit missing prep helper"
grep -q 'ExecStartPre=/usr/bin/rocknix-guest-udev-stage' "${guest_unit}" || fail "guest unit missing udev stage helper"
grep -q 'ExecStart=/usr/bin/rocknix-guest-start' "${guest_unit}" || fail "guest unit must launch through guest start helper"
grep -q '/usr/bin/systemd-nspawn' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must exec systemd-nspawn"
grep -q -- '--directory=/storage/machines/rocknix-guest' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper has wrong guest root"
grep -q -- '--register=no' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must avoid machined registration"
grep -q 'DeviceAllow=/dev/net/tun rwm' "${guest_unit}" || fail "guest unit must allow tun device access for guest Tailscale"
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
  grep -q "${device_allow}" "${guest_unit}" || fail "guest unit must not let tun DeviceAllow block main-space devices: ${device_allow}"
done
grep -q -- '--capability=CAP_NET_ADMIN' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must retain CAP_NET_ADMIN for guest Tailscale"
grep -q -- '--capability=CAP_NET_RAW' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must retain CAP_NET_RAW for guest Tailscale"
grep -q -- '--bind=/dev/net/tun' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must pass through tun device for guest Tailscale"
grep -q -- '--bind=/dev/uhid' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must pass through uhid for guest Bluetooth HID devices"
grep -q -- '--bind=/dev/input' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must pass through input devices"
grep -q -- '--bind=/dev/uinput' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must pass through uinput for guest InputPlumber"
grep -q -- '--bind=/dev/snd' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must pass through sound devices"
grep -q -- '--bind-ro=/run/.guest-udev:/run/udev' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must bind scrubbed udev db"
grep -q -- '--bind=/storage/.guest' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must keep the single host/guest storage seam"
! grep -q -- '--bind-ro=/storage/roms' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must not bind host ROM library"
! grep -q -- '--bind=/storage/.config/Cemu' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must not bind host Cemu config"
! grep -q -- '--bind=/storage/.config/MangoHud' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must not bind host MangoHud config"
! grep -q -- '--bind=/storage/.local' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must not bind host .local"
grep -q 'has_candidate_media_member' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must classify media without probing blocked devices"
! grep -q 'blkid' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must not depend on blkid before runtime DeviceAllow is applied"
grep -q 'is_host_mounted_root' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must guard against host-mounted block roots"
grep -q 'systemctl set-property' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must apply exact runtime DeviceAllow entries"
grep -q 'emit_device_allow "DeviceAllow=/dev/${member} rw"' "${PKG_DIR}/scripts/rocknix-guest-start" || fail "guest start helper must allow discovered block nodes exactly"
! grep -q 'DeviceAllow=block-sd' "${guest_unit}" || fail "guest unit must not use broad sd block allow"
! grep -q 'DeviceAllow=block-mmc' "${guest_unit}" || fail "guest unit must not use broad mmc block allow"
! grep -q 'DeviceAllow=block-nvme' "${guest_unit}" || fail "guest unit must not use broad nvme block allow"
! grep -q 'DeviceAllow=block-blkext' "${guest_unit}" || fail "guest unit must not use broad blkext block allow"
! grep -q 'ExecStopPost=' "${guest_unit}" || fail "guest unit must not run host-side fallback/reclaim hooks"
grep -q 'Restart=on-failure' "${guest_unit}" || fail "guest unit must restart on failure"
grep -q 'WantedBy=rocknix-main-space.target' "${guest_unit}" || fail "guest unit must be wanted by rocknix-main-space.target"
! grep -q 'Alias=rocknix-guest-v2.service' "${guest_unit}" || fail "guest unit must not keep old v2 alias"

wifi_unit="${PKG_DIR}/system.d/rocknix-guest-wifi-ready.service"
grep -q 'Requires=rocknix-guest-root-ensure.service' "${wifi_unit}" || fail "guest Wi-Fi unblock service must require root ensure"
grep -q 'After=.*rocknix-guest-root-ensure.service' "${wifi_unit}" || fail "guest Wi-Fi unblock service must run after root ensure"
grep -q 'After=.*rocknix-guest.service' "${wifi_unit}" || fail "guest Wi-Fi unblock service must run after guest starts"
grep -q 'ConditionKernelCommandLine=!rocknix.safe=1' "${wifi_unit}" || fail "guest Wi-Fi unblock service must be guarded by rocknix.safe=1"
grep -q 'ConditionPathExists=!/flash/rocknix.no-nspawn' "${wifi_unit}" || fail "guest Wi-Fi unblock service must be guarded by sticky recovery flag"
grep -q 'Before=rocknix-guest-promote.service' "${wifi_unit}" || fail "guest Wi-Fi unblock service must run before promotion"
grep -q 'ExecStart=/usr/bin/rocknix-guest-wifi-unblock --guest-radio' "${wifi_unit}" || fail "guest Wi-Fi unblock service has wrong ExecStart"
grep -q 'TimeoutStartSec=3min' "${wifi_unit}" || fail "guest Wi-Fi unblock service must have a bounded startup timeout"
grep -q 'WantedBy=rocknix-main-space.target' "${wifi_unit}" || fail "guest Wi-Fi unblock service must be wanted by main-space target"
grep -q 'rfkill unblock wifi' "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock" || fail "Wi-Fi unblock helper must clear live rfkill state"
grep -q 'timeout 10 nsenter' "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock" || fail "Wi-Fi unblock helper must bound guest namespace probes so iwctl cannot hang boot"
grep -q 'run_timeout 4 iwctl device wlan0 set-property Powered on' "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock" || fail "Wi-Fi unblock helper must bound iwctl power-on calls"
grep -q 'nmcli radio wifi on' "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock" || fail "Wi-Fi unblock helper must enable guest NetworkManager Wi-Fi radio"
grep -q 'nm_wifi_enabled' "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock" || fail "Wi-Fi unblock helper must confirm NetworkManager accepted radio enablement"
grep -q 'iwd_wifi_powered' "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock" || fail "Wi-Fi unblock helper must confirm iwd accepted device power-on"
grep -q 'guest Wi-Fi radio enabled' "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock" || fail "Wi-Fi unblock helper must log confirmed guest radio readiness"
grep -q 'ROCKNIX_GUEST_RFKILL_CACHE' "${PKG_DIR}/scripts/rocknix-guest-wifi-unblock" || fail "Wi-Fi unblock helper must allow rfkill cache override for tests"

promote_unit="${PKG_DIR}/system.d/rocknix-guest-promote.service"
grep -q 'Requires=rocknix-guest-root-ensure.service' "${promote_unit}" || fail "guest promotion must require root ensure"
grep -q 'After=.*rocknix-guest-root-ensure.service' "${promote_unit}" || fail "guest promotion must run after root ensure"
grep -q 'After=.*rocknix-guest.service' "${promote_unit}" || fail "guest promotion must run after guest boot"
grep -q 'ConditionKernelCommandLine=!rocknix.safe=1' "${promote_unit}" || fail "guest promotion must be guarded by rocknix.safe=1"
grep -q 'ConditionPathExists=!/flash/rocknix.no-nspawn' "${promote_unit}" || fail "guest promotion must be guarded by sticky recovery flag"
grep -q 'ExecStart=/usr/bin/rocknix-guest-promote' "${promote_unit}" || fail "guest promotion unit has wrong ExecStart"
grep -q 'WantedBy=rocknix-main-space.target' "${promote_unit}" || fail "guest promotion must be wanted by main-space target"
grep -q 'TimeoutStartSec=60min' "${promote_unit}" || fail "guest promotion needs a long timeout for Nix builds"
grep -q 'nix build' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must build packaged guest configuration"
grep -q 'rocknix-guest-main-space-by-compatible' "${PKG_DIR}/scripts/rocknix-guest-promote" \
  || fail "guest promotion must build the by-compatible dispatch entry point so per-device profiles are picked from /proc/device-tree/compatible (rocknix-nix-guest)"
! grep -qE '\.#nixosConfigurations\.rocknix-guest-main-space\.' "${PKG_DIR}/scripts/rocknix-guest-promote" \
  || fail "guest promotion must not target the legacy Thor-aliased rocknix-guest-main-space attribute; use rocknix-guest-main-space-by-compatible"
grep -q 'nix build --impure' "${PKG_DIR}/scripts/rocknix-guest-promote" \
  || fail "guest promotion must pass --impure (by-compatible dispatch reads /proc/device-tree/compatible at eval time)"
grep -q 'ROCKNIX_GUEST_SYSTEM_PROFILE' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must honor selected profile override"
grep -q "nix-env -p '\${SELECTED_PROFILE_GUEST}' --set" "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must update selected guest system profile"
! grep -q "LEGACY_PROFILE_GUEST" "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must not maintain the retired legacy system mirror"
! grep -q "nix-env -p '/nix/var/nix/profiles/system'" "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must not write retired legacy system profile"
grep -q 'systemctl restart --no-block "${GUEST_SERVICE}"' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must restart guest after profile update"
grep -q 'rocknix-guest-revision' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must track applied guest revision"
grep -q 'rocknix-guest-system-path' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must track applied guest system path"
grep -q 'resolve_guest_system_profile' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must inspect persistent guest system profile"
grep -q 'guest_system_path_valid' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must verify applied system path has an executable init"
! grep -q 'system profile drifted' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must not repair selected-profile drift from marker state"
! grep -q 'wait_for_guest_current_system' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must not carry drift-repair readiness code"
grep -q 'refusing to use applied markers as source of truth' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must treat applied markers as audit data, not source of truth"
grep -q 'nsenter .* sh -c' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must avoid login shell nsenter invocations"
! grep -q 'nsenter .* sh -lc' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must not invoke guest login shell"
grep -q 'ROCKNIX_GUEST_PROMOTE_SYSTEM_PATH' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must allow promote result file override for tests"
grep -q '/storage/.guest/rocknix-guest-promote-system-path' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must return system path through shared guest storage"
grep -q '/run/current-system/sw/bin/systemctl is-active NetworkManager.service' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must use absolute guest systemctl for readiness"
! grep -q 'seq 1 60' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must not depend on seq during early guest boot"
grep -q '/run/current-system/sw/bin/sleep 2' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must use absolute guest sleep when available"
grep -q 'ROCKNIX_GUEST_HOST_PATH' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must allow host command stubs for fixture tests"
grep -q 'ROCKNIX_GUEST_MANUAL_HOLD_FILE' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must honor manual generation hold override"
grep -q 'exit_if_manual_generation_hold_active' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must check manual generation hold"
grep -q 'manual generation selection hold is active' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must log manual generation hold"
grep -q 'rocknix-guest-stage10-proof-thor' "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must document explicit Thor proof output"
grep -q 'rocknix-guest-stage10-proof-odin2portal' "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must document explicit Odin 2 Portal proof output"
grep -q 'thor|odin2portal' "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must allow both Thor and Odin 2 Portal explicit targets"
grep -q 'live generation A is required for import' "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must require live generation A"
grep -q 'rocknix-stage10-proof-marker' "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must require B proof marker"
grep -q "\[ -f '\${SYSTEM_PATH}/\${PROOF_MARKER_REL}' \]" "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must verify B proof marker from live guest namespace"
grep -q 'rocknix-guest-manual-generation-hold' "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must require manual generation hold"
grep -q 'systemctl stop "${PROMOTE_SERVICE}"' "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must stop in-flight promotion"
grep -q 'systemctl reset-failed "${GUEST_SERVICE}"' "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must reset failed/start-limit state before restart"
grep -q 'selected/running differ before recording generation A' "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must require clean selected generation A before recording rollback state"
! grep -q "LEGACY_PROFILE_GUEST" "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must not write retired legacy system profile"
grep -q 'rocknix-stage10-proof-marker' "${PKG_DIR}/scripts/rocknix-guest-activation-audit" || fail "activation audit must report B proof marker"
grep -q 'running_guest_has_file' "${PKG_DIR}/scripts/rocknix-guest-activation-audit" || fail "activation audit must verify proof marker from live guest namespace"
grep -q 'seed_expected_revision' "${PKG_DIR}/scripts/rocknix-guest-activation-audit" || fail "activation audit must report seed manifest revision"
grep -q 'seed_staged=' "${PKG_DIR}/scripts/rocknix-guest-activation-audit" || fail "activation audit must report staged seed state"
grep -q 'reseed_flag=' "${PKG_DIR}/scripts/rocknix-guest-activation-audit" || fail "activation audit must report reseed flag state"
grep -q 'never repair' "${PKG_DIR}/scripts/rocknix-guest-activation-audit" || fail "activation audit must document read-only behavior"
grep -q 'rocknix-guest-activation-audit' "${PKG_DIR}/scripts/rocknix-guest-soak" || fail "soak helper must reuse activation audit when installed"

run_promote_profile_fixture() {
  tmp_dir=$(mktemp -d)
  guest_root="${tmp_dir}/guest-root"
  guest_source="${tmp_dir}/guest-source"
  guest_rev="${tmp_dir}/guest-revision"
  staged_source="${tmp_dir}/staged-source"
  bin_dir="${tmp_dir}/bin"
  nsenter_log="${tmp_dir}/nsenter.log"
  systemctl_log="${tmp_dir}/systemctl.log"
  compatible_file="${tmp_dir}/compatible"
  mkdir -p \
    "${guest_root}/nix/var/nix/profiles/per-user/root" \
    "${guest_root}/nix/var/nix/profiles" \
    "${guest_root}/nix/store/applied-system" \
    "${guest_root}/nix/store/old-system" \
    "${guest_root}/etc" \
    "${guest_source}" \
    "${bin_dir}"
  : > "${guest_root}/nix/store/applied-system/init"
  : > "${guest_root}/nix/store/old-system/init"
  chmod 0755 "${guest_root}/nix/store/applied-system/init" "${guest_root}/nix/store/old-system/init"
  printf 'rev-a\n' > "${guest_rev}"
  printf 'ayn,thor\n' > "${compatible_file}"
  printf 'rev-a\n' > "${guest_root}/etc/rocknix-guest-revision"
  printf '/nix/store/applied-system\n' > "${guest_root}/etc/rocknix-guest-system-path"

  cat > "${bin_dir}/systemctl" <<'EOF'
#!/bin/sh
case "$1" in
  show) printf '100\n' ;;
  restart) printf '%s\n' "$*" >> "${ROCKNIX_TEST_SYSTEMCTL_LOG}" ;;
  *) exit 0 ;;
esac
EOF
  cat > "${bin_dir}/pgrep" <<'EOF'
#!/bin/sh
printf '200\n'
EOF
  cat > "${bin_dir}/nsenter" <<'EOF'
#!/bin/sh
last=
for arg in "$@"; do last="$arg"; done
printf '%s\n' "${last}" >> "${ROCKNIX_TEST_NSENTER_LOG}"
case "${last}" in
  *'nix build'*) printf '/nix/store/rebuilt-system\n' > "${ROCKNIX_GUEST_PROMOTE_SYSTEM_PATH}" ;;
esac
exit 0
EOF
  chmod 0755 "${bin_dir}/systemctl" "${bin_dir}/pgrep" "${bin_dir}/nsenter"

  set_profile() {
    profile_path="$1"
    link_name="$2"
    target="$3"
    profile_dir=$(dirname "${profile_path}")
    rm -f "${profile_path}" "${profile_dir}/${link_name}"
    ln -s "${target}" "${profile_dir}/${link_name}"
    ln -s "${link_name}" "${profile_path}"
  }

  selected_profile="${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  set_profile "${selected_profile}" "rocknix-guest-system-1-link" "/nix/store/applied-system"

  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_TEST_NSENTER_LOG="${nsenter_log}" \
    ROCKNIX_TEST_SYSTEMCTL_LOG="${systemctl_log}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_SOURCE="${guest_source}" \
    ROCKNIX_GUEST_REV_FILE="${guest_rev}" \
    ROCKNIX_GUEST_STAGED_SOURCE="${staged_source}" \
    "${PKG_DIR}/scripts/rocknix-guest-promote" >/dev/null
  [ ! -s "${nsenter_log}" ] || fail "promote fixture: already-applied path should not enter guest"
  [ ! -s "${systemctl_log}" ] || fail "promote fixture: already-applied path should not restart guest"

  set_profile "${selected_profile}" "rocknix-guest-system-1-link" "/nix/store/old-system"
  : > "${nsenter_log}"
  : > "${systemctl_log}"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_TEST_NSENTER_LOG="${nsenter_log}" \
    ROCKNIX_TEST_SYSTEMCTL_LOG="${systemctl_log}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_SOURCE="${guest_source}" \
    ROCKNIX_GUEST_REV_FILE="${guest_rev}" \
    ROCKNIX_GUEST_STAGED_SOURCE="${staged_source}" \
    "${PKG_DIR}/scripts/rocknix-guest-promote" >/dev/null
  [ ! -s "${nsenter_log}" ] || fail "promote fixture: marker-matching selected profile must remain authoritative"
  [ ! -s "${systemctl_log}" ] || fail "promote fixture: marker-matching selected profile should not restart guest"

  mkdir -p "${guest_root}/nix/store/rebuilt-system"
  : > "${guest_root}/nix/store/rebuilt-system/init"
  chmod 0755 "${guest_root}/nix/store/rebuilt-system/init"
  printf 'rev-b\n' > "${guest_rev}"
  : > "${nsenter_log}"
  : > "${systemctl_log}"
  promote_result="${tmp_dir}/promote-result"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_TEST_NSENTER_LOG="${nsenter_log}" \
    ROCKNIX_TEST_SYSTEMCTL_LOG="${systemctl_log}" \
    ROCKNIX_GUEST_PROMOTE_SYSTEM_PATH="${promote_result}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_SOURCE="${guest_source}" \
    ROCKNIX_GUEST_REV_FILE="${guest_rev}" \
    ROCKNIX_GUEST_STAGED_SOURCE="${staged_source}" \
    "${PKG_DIR}/scripts/rocknix-guest-promote" >/dev/null
  grep -q "nix-env -p '/nix/var/nix/profiles/per-user/root/rocknix-guest-system' --set '/nix/store/rebuilt-system'" "${nsenter_log}" \
    || fail "promote fixture: rebuild path did not write selected profile"
  ! grep -q "nix-env -p '/nix/var/nix/profiles/system'" "${nsenter_log}" \
    || fail "promote fixture: rebuild path wrote retired legacy profile"
  [ "$(sed -n '1p' "${guest_root}/etc/rocknix-guest-revision")" = "rev-b" ] \
    || fail "promote fixture: rebuild path did not update revision marker"
  [ "$(sed -n '1p' "${guest_root}/etc/rocknix-guest-system-path")" = "/nix/store/rebuilt-system" ] \
    || fail "promote fixture: rebuild path did not update system marker"
  grep -q 'restart --no-block rocknix-guest.service' "${systemctl_log}" \
    || fail "promote fixture: rebuild path did not restart guest"

  : > "${nsenter_log}"
  : > "${systemctl_log}"
  : > "${tmp_dir}/manual-hold"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_TEST_NSENTER_LOG="${nsenter_log}" \
    ROCKNIX_TEST_SYSTEMCTL_LOG="${systemctl_log}" \
    ROCKNIX_GUEST_MANUAL_HOLD_FILE="${tmp_dir}/manual-hold" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_SOURCE="${guest_source}" \
    ROCKNIX_GUEST_REV_FILE="${guest_rev}" \
    ROCKNIX_GUEST_STAGED_SOURCE="${staged_source}" \
    "${PKG_DIR}/scripts/rocknix-guest-promote" >/dev/null
  [ ! -s "${nsenter_log}" ] || fail "promote fixture: manual hold should not enter guest"
  [ ! -s "${systemctl_log}" ] || fail "promote fixture: manual hold should not restart guest"

  rm -rf "${tmp_dir}"
}
run_promote_profile_fixture

for forbidden in '--bind-ro=/usr' '--bind-ro=/lib' '--bind-ro=/etc/profile' '--bind=/storage ' '--bind-ro=/storage/roms' '--bind=/storage/.config/Cemu' '--bind=/storage/.config/MangoHud' '--bind=/storage/.local'; do
  ! grep -v '^#' "${guest_unit}" | grep -F -q -- "${forbidden}" || fail "guest unit still contains forbidden broad bind: ${forbidden}"
done

# Recovery and safety net.
grep -q '/flash/rocknix.no-nspawn' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle missing flag-file escape"
grep -q 'rocknix.safe=1' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle missing cmdline escape"
grep -q 'rocknix-main-space.target' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle missing normal target"
grep -q 'RECOVERY_TARGET="multi-user.target"' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle must route minimal-host recovery to multi-user.target"
grep -q 'early generator should select' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle must be audit-only for early generator selection"
! grep -q 'systemctl set-default' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle must not mutate persistent default.target during boot"
grep -q 'systemctl set-default during boot' "${PKG_DIR}/system.d/rocknix-recovery-toggle.service" || fail "recovery toggle unit must document that late set-default is not authoritative"

grep -q 'resolv.conf.guest-owned' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing resolv.conf ownership marker"
grep -q '/storage/.guest' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing guest writable area"
grep -q 'GUEST_STORAGE_ROOT=' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper must create guest-owned storage namespace"
grep -q '/nix/var/nix/profiles/per-user/root/rocknix-guest-system' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing selected guest system profile check"
! grep -q '/nix/var/nix/profiles/system' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper must not fall back to retired legacy system profile"
grep -q 'no valid selected guest system profile' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper must fail clearly when selected profile is invalid"
grep -q 'expected .*init to be executable' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper must validate selected init"

run_prep_profile_fixture() {
  tmp_dir=$(mktemp -d)
  guest_root="${tmp_dir}/guest-root"
  guest_area="${tmp_dir}/guest-area"
  mkdir -p \
    "${guest_root}/nix/var/nix/profiles/per-user/root" \
    "${guest_root}/nix/var/nix/profiles" \
    "${guest_root}/nix/store/selected-system" \
    "${guest_root}/etc" \
    "${guest_root}/sbin" \
    "${guest_area}"
  : > "${guest_root}/nix/store/selected-system/init"
  chmod 0755 "${guest_root}/nix/store/selected-system/init"
  ln -s /nix/store/selected-system "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system-1-link"
  ln -s rocknix-guest-system-1-link "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"

  ROCKNIX_GUEST_ROOT="${guest_root}" ROCKNIX_GUEST_AREA="${guest_area}" "${PKG_DIR}/scripts/rocknix-guest-prep" >/dev/null 2>&1
  [ "$(readlink "${guest_root}/init")" = "/nix/store/selected-system/init" ] || fail "prep fixture: selected profile did not win"
  [ "$(readlink "${guest_root}/sbin/init")" = "/nix/store/selected-system/init" ] || fail "prep fixture: selected profile did not relink sbin/init"

  rm -f "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  if ROCKNIX_GUEST_ROOT="${guest_root}" ROCKNIX_GUEST_AREA="${guest_area}" "${PKG_DIR}/scripts/rocknix-guest-prep" >/dev/null 2>&1; then
    fail "prep fixture: missing selected profile should fail"
  fi

  ln -s rocknix-guest-system-1-link "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  rm -f "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system-1-link"
  ln -s /nix/store/missing-system "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system-1-link"
  if ROCKNIX_GUEST_ROOT="${guest_root}" ROCKNIX_GUEST_AREA="${guest_area}" "${PKG_DIR}/scripts/rocknix-guest-prep" >/dev/null 2>&1; then
    fail "prep fixture: invalid selected profile should fail"
  fi

  rm -rf "${tmp_dir}"
}
run_prep_profile_fixture

create_bootable_seed_fixture() {
  root="$1"
  mkdir -p \
    "${root}/nix/var/nix/profiles/per-user/root" \
    "${root}/nix/store/selected-system" \
    "${root}/etc" \
    "${root}/sbin"
  : > "${root}/nix/store/selected-system/init"
  chmod 0755 "${root}/nix/store/selected-system/init"
  ln -s /nix/store/selected-system "${root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system-1-link"
  ln -s rocknix-guest-system-1-link "${root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  ln -s /nix/store/selected-system/init "${root}/init"
  ln -s /nix/store/selected-system/init "${root}/sbin/init"
  printf 'revision=test\nsha256=test\n' > "${root}/.rocknix-guest-rootfs-seed"
}

run_root_ensure_fixture() {
  tmp_dir=$(mktemp -d)
  seed_root="${tmp_dir}/seed"
  machines_root="${tmp_dir}/storage/machines"
  guest_root="${machines_root}/rocknix-guest"
  lock_file="${tmp_dir}/run/lock/rocknix-guest-root.lock"
  bin_dir="${tmp_dir}/bin"
  mkdir -p "${seed_root}" "${machines_root}" "${bin_dir}"
  create_bootable_seed_fixture "${seed_root}"

  cat > "${bin_dir}/systemctl" <<'EOF'
#!/bin/sh
exit 3
EOF
  chmod 0755 "${bin_dir}/systemctl"

  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED="${seed_root}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null
  [ -d "${guest_root}/nix" ] || fail "root ensure fixture: missing root was not seeded"
  [ -f "${guest_root}/etc/rocknix-guest-root-seed-complete" ] || fail "root ensure fixture: completion marker missing"
  [ "$(readlink "${guest_root}/init")" = "/nix/store/selected-system/init" ] || fail "root ensure fixture: /init link was not preserved"

  before=$(find "${guest_root}" -type f | wc -l)
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED="${seed_root}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null
  after=$(find "${guest_root}" -type f | wc -l)
  [ "${before}" = "${after}" ] || fail "root ensure fixture: valid root should not be recopied"

  rm -rf "${guest_root}"
  stale_tmp="${guest_root}.tmp.stale"
  mkdir -p "${stale_tmp}"
  : > "${stale_tmp}/.rocknix-guest-rootfs-seed-in-progress"
  mkdir -p "${guest_root}"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED="${seed_root}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null
  [ -f "${guest_root}/etc/rocknix-guest-root-seed-complete" ] || fail "root ensure fixture: empty root was not seeded"
  [ ! -e "${stale_tmp}" ] || fail "root ensure fixture: helper-owned stale temp was not cleaned"

  rm -rf "${guest_root}"
  archive_seed_root="${tmp_dir}/archive-seed"
  seed_stage_dir="${tmp_dir}/storage/.guest/seed"
  seed_manifest="${tmp_dir}/guest-rootfs-seed.manifest"
  compatible_file="${tmp_dir}/compatible"
  mkdir -p "${seed_stage_dir}"
  create_bootable_seed_fixture "${archive_seed_root}"
  seed_archive="${seed_stage_dir}/fixture-rootfs.tar.zst"
  tar --zstd -cf "${seed_archive}" -C "${archive_seed_root}" .
  seed_sha="$(sha256sum "${seed_archive}" | awk '{print $1}')"
  seed_size="$(stat -c %s "${seed_archive}")"
  {
    printf 'seed_manifest_version=1\n'
    printf 'seed_device=odin2portal\n'
    printf 'seed_compatible=ayn,odin2portal\n'
    printf 'seed_revision=test-archive\n'
    printf 'seed_archive=fixture-rootfs.tar.zst\n'
    printf 'seed_sha256=%s\n' "${seed_sha}"
    printf 'seed_size=%s\n' "${seed_size}"
    printf 'seed_source_urls=fixture\n'
  } > "${seed_manifest}"
  printf 'ayn,odin2portal\000qcom,sm8550\000' > "${compatible_file}"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED_DIR="${seed_stage_dir}" \
    ROCKNIX_GUEST_ROOTFS_SEED_MANIFEST="${seed_manifest}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null
  [ -f "${guest_root}/.rocknix-guest-rootfs-seed" ] || fail "root ensure fixture: archive seed contract marker missing"
  grep -q 'compatible=ayn,odin2portal' "${guest_root}/.rocknix-guest-rootfs-seed" || fail "root ensure fixture: archive seed compatible marker missing"

  rm -rf "${guest_root}"
  sed 's/seed_compatible=ayn,odin2portal/seed_compatible=ayn,thor/' "${seed_manifest}" > "${seed_manifest}.bad-compatible"
  if ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED_DIR="${seed_stage_dir}" \
    ROCKNIX_GUEST_ROOTFS_SEED_MANIFEST="${seed_manifest}.bad-compatible" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null 2>&1; then
    fail "root ensure fixture: incompatible staged seed should fail closed"
  fi
  [ ! -e "${guest_root}" ] || fail "root ensure fixture: incompatible staged seed created authoritative root"

  sed "s/seed_sha256=${seed_sha}/seed_sha256=0000000000000000000000000000000000000000000000000000000000000000/" "${seed_manifest}" > "${seed_manifest}.bad-sha"
  if ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED_DIR="${seed_stage_dir}" \
    ROCKNIX_GUEST_ROOTFS_SEED_MANIFEST="${seed_manifest}.bad-sha" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null 2>&1; then
    fail "root ensure fixture: sha-mismatched staged seed should fail closed"
  fi
  [ ! -e "${guest_root}" ] || fail "root ensure fixture: sha-mismatched staged seed created authoritative root"

  rm -rf "${guest_root}" "${guest_root}.previous"
  create_bootable_seed_fixture "${guest_root}"
  printf 'old-root\n' > "${guest_root}/etc/old-root"
  reseed_flag="${tmp_dir}/flash/rocknix.reseed-guest"
  mkdir -p "$(dirname "${reseed_flag}")"
  : > "${reseed_flag}"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED_DIR="${seed_stage_dir}" \
    ROCKNIX_GUEST_ROOTFS_SEED_MANIFEST="${seed_manifest}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_RESEED_FLAG="${reseed_flag}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null
  [ ! -f "${guest_root}/etc/old-root" ] || fail "root ensure fixture: reseed did not replace active root"
  [ -f "${guest_root}.previous/etc/old-root" ] || fail "root ensure fixture: reseed did not preserve previous root"
  [ ! -e "${reseed_flag}" ] || fail "root ensure fixture: reseed flag was not cleared"

  : > "${reseed_flag}"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED_DIR="${seed_stage_dir}" \
    ROCKNIX_GUEST_ROOTFS_SEED_MANIFEST="${seed_manifest}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_RESEED_FLAG="${reseed_flag}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null
  [ ! -e "${reseed_flag}" ] || fail "root ensure fixture: second reseed after legacy previous did not clear flag"

  rm -rf "${guest_root}" "${guest_root}.previous"
  mkdir -p "${guest_root}/etc"
  printf 'damaged-root\n' > "${guest_root}/etc/not-a-guest-root"
  : > "${reseed_flag}"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED_DIR="${seed_stage_dir}" \
    ROCKNIX_GUEST_ROOTFS_SEED_MANIFEST="${seed_manifest}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_RESEED_FLAG="${reseed_flag}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null
  [ -d "${guest_root}/nix" ] || fail "root ensure fixture: reseed flag did not recover damaged root"
  [ -f "${guest_root}.previous/etc/not-a-guest-root" ] || fail "root ensure fixture: damaged root was not preserved as previous"

  rm -rf "${guest_root}" "${guest_root}.previous"
  mkdir -p "${guest_root}/etc"
  printf 'user-data\n' > "${guest_root}/etc/not-a-guest-root"
  if ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED="${seed_root}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null 2>&1; then
    fail "root ensure fixture: non-empty invalid root should fail closed"
  fi
  [ -f "${guest_root}/etc/not-a-guest-root" ] || fail "root ensure fixture: invalid root data was overwritten"

  rm -rf "${guest_root}"
  rm -f "${seed_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  if ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_GUEST_ROOTFS_SEED="${seed_root}" \
    ROCKNIX_GUEST_MACHINES_ROOT="${machines_root}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_ROOT_LOCK="${lock_file}" \
    "${PKG_DIR}/scripts/rocknix-guest-root-ensure" >/dev/null 2>&1; then
    fail "root ensure fixture: invalid seed should fail before creating root"
  fi
  [ ! -e "${guest_root}" ] || fail "root ensure fixture: invalid seed created authoritative root"

  rm -rf "${tmp_dir}"
}
run_root_ensure_fixture

grep -q 'inputplumber/by-hidden' "${PKG_DIR}/scripts/rocknix-guest-udev-stage" || fail "udev stage must scrub InputPlumber-hidden devices"
grep -q 'SYS_SOUND_DIR' "${PKG_DIR}/scripts/rocknix-guest-udev-stage" || fail "udev stage must allow fixture-controlled sound sysfs"
grep -q 'DEVNAME=/dev/snd/controlC' "${PKG_DIR}/scripts/rocknix-guest-udev-stage" || fail "udev stage must treat the control device udev record as sound-ready"
! grep -q 'ALSA_CARD_NUMBER' "${PKG_DIR}/scripts/rocknix-guest-udev-stage" || fail "udev stage must not wait for ALSA_CARD_NUMBER; ROCKNIX udev records may not provide it"

run_udev_stage_sound_wait_fixture() {
  tmp_dir=$(mktemp -d)
  source_dir="${tmp_dir}/udev"
  stage_dir="${tmp_dir}/stage"
  sys_sound_dir="${tmp_dir}/sys-sound"
  mkdir -p "${source_dir}/data" "${source_dir}/tags" "${sys_sound_dir}"

  (
    sleep 1
    mkdir -p "${sys_sound_dir}/controlC0"
    printf '%s\n' '116:5' > "${sys_sound_dir}/controlC0/dev"
    cat > "${source_dir}/data/c116:5" <<'EOF'
E:DEVPATH=/devices/platform/sound/sound/card0/controlC0
E:DEVNAME=/dev/snd/controlC0
E:SUBSYSTEM=sound
E:ID_PATH=platform-sound
EOF
  ) &
  producer_pid=$!

  SOURCE_DIR="${source_dir}" \
    STAGE_DIR="${stage_dir}" \
    SYS_SOUND_DIR="${sys_sound_dir}" \
    SOUND_UDEV_WAIT_SECS=3 \
    "${PKG_DIR}/scripts/rocknix-guest-udev-stage" >/dev/null 2>&1 || {
      wait "${producer_pid}" 2>/dev/null || true
      rm -rf "${tmp_dir}"
      fail "udev stage fixture: stage helper failed"
    }
  wait "${producer_pid}"

  [ -f "${stage_dir}/data/c116:5" ] || fail "udev stage fixture: did not wait for late sound control record"
  grep -q 'E:DEVNAME=/dev/snd/controlC0' "${stage_dir}/data/c116:5" \
    || fail "udev stage fixture: staged sound control record is incomplete"

  rm -rf "${tmp_dir}"
}
run_udev_stage_sound_wait_fixture

grep -q 'check_host_ssh_responsive' "${PKG_DIR}/scripts/rocknix-guest-soak" || fail "soak helper missing host SSH check"
grep -q 'ROCKNIX_REQUIRE_HOST_ESSWAY' "${PKG_DIR}/scripts/rocknix-guest-soak" || fail "soak helper must allow SSH-first recovery without host essway"
grep -q 'check_resolv_owned' "${PKG_DIR}/scripts/rocknix-guest-soak" || fail "soak helper missing resolv ownership check"
grep -q 'check_selected_system_profile' "${PKG_DIR}/scripts/rocknix-guest-soak" || fail "soak helper missing selected system profile check"

run_target_generator_fixture() {
  generator="${REPO_ROOT}/packages/sysutils/busybox/scripts/libreelec-target-generator"
  [ -f "${generator}" ] || fail "missing target generator"
  sh -n "${generator}" || fail "target generator syntax failed"
  grep -q 'rocknix-main-space.target' "${generator}" || fail "target generator missing SM8550 main-space selection"
  grep -q 'rocknix.safe=1' "${generator}" || fail "target generator missing rocknix.safe=1 selection"
  grep -q 'rocknix.no-nspawn' "${generator}" || fail "target generator missing sticky recovery flag selection"

  tmp_dir=$(mktemp -d)
  early_dir="${tmp_dir}/early"
  storage_dir="${tmp_dir}/storage"
  flash_dir="${tmp_dir}/flash"
  systemd_dir="${tmp_dir}/systemd"
  cmdline="${tmp_dir}/cmdline"
  mkdir -p "${early_dir}" "${storage_dir}/.cache" "${storage_dir}/.restore" "${flash_dir}" "${systemd_dir}"
  for target in rocknix-main-space.target multi-user.target fs-resize.target factory-reset.target backup-restore.target textmode.target installer.target; do
    : > "${systemd_dir}/${target}"
  done

  run_generator() {
    rm -f "${early_dir}/default.target"
    LIBREELEC_TARGET_GENERATOR_CMDLINE="${cmdline}" \
      LIBREELEC_TARGET_GENERATOR_STORAGE="${storage_dir}" \
      LIBREELEC_TARGET_GENERATOR_FLASH="${flash_dir}" \
      LIBREELEC_TARGET_GENERATOR_SYSTEMD_DIR="${systemd_dir}" \
      LIBREELEC_TARGET_GENERATOR_KMSG="${tmp_dir}/kmsg" \
      "${generator}" ignored "${early_dir}"
    readlink "${early_dir}/default.target" 2>/dev/null | sed 's|.*/||'
  }

  printf '\n' > "${cmdline}"
  [ "$(run_generator)" = "rocknix-main-space.target" ] || fail "target generator fixture: normal boot should select main-space"

  printf 'quiet rocknix.safe=1\n' > "${cmdline}"
  [ "$(run_generator)" = "multi-user.target" ] || fail "target generator fixture: rocknix.safe=1 should select recovery"

  printf '\n' > "${cmdline}"
  : > "${flash_dir}/rocknix.no-nspawn"
  [ "$(run_generator)" = "multi-user.target" ] || fail "target generator fixture: sticky flag should select recovery"
  rm -f "${flash_dir}/rocknix.no-nspawn"

  : > "${storage_dir}/.please_resize_me"
  printf 'rocknix.safe=1\n' > "${cmdline}"
  [ "$(run_generator)" = "fs-resize.target" ] || fail "target generator fixture: resize must beat SM8550 recovery"
  rm -f "${storage_dir}/.please_resize_me"

  : > "${storage_dir}/.cache/reset_hard"
  printf '\n' > "${cmdline}"
  [ "$(run_generator)" = "factory-reset.target" ] || fail "target generator fixture: factory reset must beat main-space"
  rm -f "${storage_dir}/.cache/reset_hard"

  : > "${storage_dir}/.restore/backup.tar"
  [ "$(run_generator)" = "backup-restore.target" ] || fail "target generator fixture: backup restore must beat main-space"
  rm -f "${storage_dir}/.restore/backup.tar"

  printf 'textmode\n' > "${cmdline}"
  [ "$(run_generator)" = "textmode.target" ] || fail "target generator fixture: textmode must beat main-space"

  rm -f "${systemd_dir}/rocknix-main-space.target"
  rm -f "${early_dir}/default.target"
  printf '\n' > "${cmdline}"
  result=$(run_generator || true)
  [ -z "${result}" ] || fail "target generator fixture: non-SM8550 target availability must preserve existing behavior"

  rm -rf "${tmp_dir}"
}
run_target_generator_fixture

# Device gates: only SM8550 ships the guest substrate.
SYSTEMD_PKG="${REPO_ROOT}/projects/ROCKNIX/packages/sysutils/systemd/package.mk"
SM8550_OPTIONS="${REPO_ROOT}/projects/ROCKNIX/devices/SM8550/options"
IMAGE_PKG="${REPO_ROOT}/projects/ROCKNIX/packages/virtual/image/package.mk"
NETWORK_PKG="${REPO_ROOT}/projects/ROCKNIX/packages/virtual/network/package.mk"
IWD_PKG="${REPO_ROOT}/packages/network/iwd/package.mk"
OPENSSH_PKG="${REPO_ROOT}/projects/ROCKNIX/packages/network/openssh/package.mk"
CONNMAN_PKG="${REPO_ROOT}/projects/ROCKNIX/packages/network/connman/package.mk"
QUIRKS_PKG="${REPO_ROOT}/projects/ROCKNIX/packages/hardware/quirks/package.mk"
WORKFLOW_DIR="${REPO_ROOT}/.github/workflows"
BUILD_NIGHTLY_WORKFLOW="${WORKFLOW_DIR}/build-nightly.yml"
IMAGE_ONLY_WORKFLOW="${WORKFLOW_DIR}/build-image-only.yml"
LOCAL_IMAGE_BUILD="${REPO_ROOT}/scripts/local-image-build"
IMAGE_SCRIPT="${REPO_ROOT}/scripts/image"
INIT_SCRIPT="${REPO_ROOT}/projects/ROCKNIX/packages/sysutils/busybox/scripts/init"
[ -f "${SYSTEMD_PKG}" ] || fail "missing ROCKNIX systemd package.mk"
[ -f "${OPENSSH_PKG}" ] || fail "missing ROCKNIX openssh package.mk"
[ -f "${BUILD_NIGHTLY_WORKFLOW}" ] || fail "missing Build workflow"
[ -f "${IMAGE_ONLY_WORKFLOW}" ] || fail "missing image-only workflow"
[ -f "${LOCAL_IMAGE_BUILD}" ] || fail "missing local image build wrapper"
[ -f "${IMAGE_SCRIPT}" ] || fail "missing image script"
[ -f "${INIT_SCRIPT}" ] || fail "missing init script"
bash -n "${IMAGE_SCRIPT}" || fail "image script syntax failed"
sh -n "${INIT_SCRIPT}" || fail "init script syntax failed"

# SM8550 seed payload must stay outside SYSTEM and be hoisted before SYSTEM writes.
grep -q 'rocknix-guest-rootfs-seed' "${IMAGE_SCRIPT}" || fail "image script must include staged guest rootfs seed payloads"
grep -q 'target/seed' "${IMAGE_SCRIPT}" || fail "image script must place guest rootfs seed payload under target/seed"
grep -q 'stage_guest_rootfs_seed_update' "${INIT_SCRIPT}" || fail "init update path must stage guest rootfs seed payloads"
grep -q 'guest-rootfs-seed.manifest' "${INIT_SCRIPT}" || fail "init update path must read guest rootfs seed manifest from mounted SYSTEM"
grep -q 'ROCKNIX_UPDATE_STORAGE_ROOT:-/storage' "${INIT_SCRIPT}" || fail "init update path must hoist guest rootfs seed to persistent storage seam"
grep -q 'seed_sha256' "${INIT_SCRIPT}" || fail "init update path must verify guest rootfs seed sha256"
grep -q 'seed_compatible' "${INIT_SCRIPT}" || fail "init update path must reject wrong-device guest rootfs seeds"
assert_order "${INIT_SCRIPT}" 'stage_guest_rootfs_seed_update' 'update_file "System"' "init must stage guest seed before writing SYSTEM"

run_init_seed_staging_fixture() {
  tmp_dir=$(mktemp -d)
  helper="${tmp_dir}/seed-helper.sh"
  update_dir="${tmp_dir}/update-target"
  system_root="${tmp_dir}/mounted-system"
  storage_root="${tmp_dir}/storage"
  compatible_file="${tmp_dir}/compatible"
  seed_payload="${update_dir}/seed/fixture.tar.zst"
  mkdir -p "${update_dir}/seed" "${system_root}/usr/lib/rocknix-guest-substrate" "${storage_root}" \
    "$(dirname "${compatible_file}")"
  printf 'ayn,odin2portal\000qcom,sm8550\000' > "${compatible_file}"
  printf 'seed\n' > "${seed_payload}"
  seed_sha="$(sha256sum "${seed_payload}" | awk '{print $1}')"
  seed_size="$(stat -c %s "${seed_payload}")"
  cat > "${system_root}/usr/lib/rocknix-guest-substrate/guest-rootfs-seed.manifest" <<EOF
seed_archive=fixture.tar.zst
seed_sha256=${seed_sha}
seed_size=${seed_size}
seed_compatible=ayn,odin2portal
EOF

  {
    printf '%s\n' '#!/bin/sh' 'set -eu' \
      'StartProgress() { :; }' \
      'StopProgress() { :; }' \
      'UPDATE_DIR="${ROCKNIX_TEST_UPDATE_DIR}"' \
      'UPDATE_FILENAME="${ROCKNIX_TEST_UPDATE_FILENAME}"'
    awk '/^read_seed_manifest_value\(\)/ { copy=1 } /^display_versions\(\)/ { copy=0 } copy { print }' "${INIT_SCRIPT}"
    cat <<'EOF'
run_case() {
  stage_guest_rootfs_seed_update
}
run_case "$@"
EOF
  } > "${helper}"
  chmod 0755 "${helper}"

  ROCKNIX_TEST_UPDATE_DIR="${update_dir}" \
    ROCKNIX_TEST_UPDATE_FILENAME="update.tar" \
    ROCKNIX_UPDATE_SYSTEM_ROOT="${system_root}" \
    ROCKNIX_UPDATE_STORAGE_ROOT="${storage_root}" \
    ROCKNIX_UPDATE_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    "${helper}"
  cmp "${seed_payload}" "${storage_root}/.guest/seed/fixture.tar.zst" \
    || fail "init seed staging fixture: staged payload does not match source"

  rm -f "${storage_root}/.guest/seed/fixture.tar.zst"
  printf 'bad\n' >> "${seed_payload}"
  if ROCKNIX_TEST_UPDATE_DIR="${update_dir}" \
    ROCKNIX_TEST_UPDATE_FILENAME="update.tar" \
    ROCKNIX_UPDATE_SYSTEM_ROOT="${system_root}" \
    ROCKNIX_UPDATE_STORAGE_ROOT="${storage_root}" \
    ROCKNIX_UPDATE_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    "${helper}" >/dev/null 2>&1; then
    fail "init seed staging fixture: sha mismatch should fail"
  fi
  [ ! -e "${storage_root}/.guest/seed/fixture.tar.zst.tmp" ] \
    || fail "init seed staging fixture: sha mismatch left tmp seed"

  printf 'seed\n' > "${seed_payload}"
  printf 'ayn,thor\000' > "${compatible_file}"
  if ROCKNIX_TEST_UPDATE_DIR="${update_dir}" \
    ROCKNIX_TEST_UPDATE_FILENAME="update.tar" \
    ROCKNIX_UPDATE_SYSTEM_ROOT="${system_root}" \
    ROCKNIX_UPDATE_STORAGE_ROOT="${storage_root}" \
    ROCKNIX_UPDATE_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    "${helper}" >/dev/null 2>&1; then
    fail "init seed staging fixture: compatible mismatch should fail"
  fi

  printf 'ayn,odin2portal\000' > "${compatible_file}"
  rm -f "${seed_payload}"
  if ROCKNIX_TEST_UPDATE_DIR="${update_dir}" \
    ROCKNIX_TEST_UPDATE_FILENAME="update.tar" \
    ROCKNIX_UPDATE_SYSTEM_ROOT="${system_root}" \
    ROCKNIX_UPDATE_STORAGE_ROOT="${storage_root}" \
    ROCKNIX_UPDATE_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    "${helper}" >/dev/null 2>&1; then
    fail "init seed staging fixture: missing tar seed should fail"
  fi
  ROCKNIX_TEST_UPDATE_DIR="${update_dir}" \
    ROCKNIX_TEST_UPDATE_FILENAME="update.img.gz" \
    ROCKNIX_UPDATE_SYSTEM_ROOT="${system_root}" \
    ROCKNIX_UPDATE_STORAGE_ROOT="${storage_root}" \
    ROCKNIX_UPDATE_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    "${helper}" >/dev/null

  rm -rf "${tmp_dir}"
}
run_init_seed_staging_fixture

# Build-integrity gates must run before expensive/artifact-producing paths.
grep -q '^  validate-build-integrity:' "${BUILD_NIGHTLY_WORKFLOW}" || fail "Build workflow missing build-integrity validation job"
grep -q 'guest-substrate-static-checks.sh' "${BUILD_NIGHTLY_WORKFLOW}" || fail "Build workflow must run guest-substrate static checks"
grep -q 'git diff --check upstream/next\.\.\.HEAD' "${BUILD_NIGHTLY_WORKFLOW}" || fail "Build workflow must run upstream diff-check"
assert_job_contains "${BUILD_NIGHTLY_WORKFLOW}" build-docker 'validate-build-integrity' "Docker build must depend on build-integrity validation"
assert_job_contains "${BUILD_NIGHTLY_WORKFLOW}" build-devices 'validate-build-integrity' "device builds must depend on build-integrity validation"
assert_job_contains "${BUILD_NIGHTLY_WORKFLOW}" release-nightly 'validate-build-integrity' "nightly release must depend on build-integrity validation"
assert_job_contains "${BUILD_NIGHTLY_WORKFLOW}" release-official 'validate-build-integrity' "official release must depend on build-integrity validation"
assert_job_contains "${BUILD_NIGHTLY_WORKFLOW}" release-nightly "!contains(needs.*.result, 'skipped')" "nightly release must not proceed when validation-dependent jobs are skipped"
assert_job_contains "${BUILD_NIGHTLY_WORKFLOW}" release-official "!contains(needs.*.result, 'skipped')" "official release must not proceed when validation-dependent jobs are skipped"

grep -q 'permissions:' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow must declare least-privilege permissions"
grep -q 'actions: read' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow needs read-only Actions metadata/artifact permission"
grep -q 'guest-substrate-static-checks.sh' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow must run guest-substrate static checks"
grep -q 'git diff --check upstream/next\.\.\.HEAD' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow must run upstream diff-check"
assert_order "${IMAGE_ONLY_WORKFLOW}" 'Run build integrity checks' 'Verify base run is on the same branch and successful' "image-only workflow must validate static/diff checks before base-run preflight"
assert_order "${IMAGE_ONLY_WORKFLOW}" 'Verify base run is on the same branch and successful' 'Download aarch64 artifact from base run' "image-only workflow must verify artifact compatibility before download"
grep -q 'GITHUB_REF_NAME' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow must compare base branch to dispatch branch"
grep -q 'base_sha=' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow must inspect base run head SHA"
grep -q 'git merge-base --is-ancestor "${base_sha}" HEAD' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow must require base SHA ancestry"
grep -q 'unsafe_changes=' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow must reject non-image-step-safe diffs"
grep -q 'CLEAN_GUEST_SUBSTRATE' "${IMAGE_ONLY_WORKFLOW}" || fail "image-only workflow must enforce guest-substrate clean policy"
grep -q 'guest-substrate package/script/unit/test changes require CLEAN_GUEST_SUBSTRATE=true' "${IMAGE_ONLY_WORKFLOW}" \
  || fail "image-only workflow must reject guest-substrate changes when package clean is disabled"
! grep -q 'clean rocknix-guest-substrate || true' "${IMAGE_ONLY_WORKFLOW}" \
  || fail "image-only workflow must not mask guest-substrate clean failures"
grep -q 'Verify SM8550 host and seed artifacts' "${WORKFLOW_DIR}/build-aarch64-image.yml" \
  || fail "build-aarch64-image workflow must verify SM8550 host and seed artifacts before upload"
grep -q 'Verify SM8550 host and seed artifacts' "${IMAGE_ONLY_WORKFLOW}" \
  || fail "image-only workflow must verify SM8550 host and seed artifacts before upload"
grep -q 'Verify SM8550 SYSTEM budget' "${WORKFLOW_DIR}/build-aarch64.yml" \
  || fail "build-aarch64 workflow must verify SM8550 SYSTEM budget before upload"
grep -q '/target/seed/.*\\.tar\\.zst' "${WORKFLOW_DIR}/build-aarch64-image.yml" \
  || fail "build-aarch64-image workflow must require SM8550 update tar seed payload"
grep -q '/target/seed/.*\\.tar\\.zst' "${IMAGE_ONLY_WORKFLOW}" \
  || fail "image-only workflow must require SM8550 update tar seed payload"
grep -q 'scripts/(local-image-build|image|mkimage)' "${IMAGE_ONLY_WORKFLOW}" \
  || fail "image-only workflow allowlist must account for image layout script changes"

# Foreground local builds pipe through tee; the build command status must win.
grep -q '\${PIPESTATUS\[0\]}' "${LOCAL_IMAGE_BUILD}" || fail "local-image-build foreground path must capture the left side of the tee pipeline"
assert_order "${LOCAL_IMAGE_BUILD}" '| tee "${LOG_FILE}"' 'build_status=${PIPESTATUS[0]}' "local-image-build must capture foreground build status immediately after tee"
assert_order "${LOCAL_IMAGE_BUILD}" 'build_status=${PIPESTATUS[0]}' 'exit "${build_status}"' "local-image-build must return foreground build status"

grep -q '\[ "\${DEVICE}" = "SM8550" \] && PKG_DEPENDS_TARGET+=" rocknix-guest-substrate"' "${IMAGE_PKG}" \
  || fail "image package must gate rocknix-guest-substrate on DEVICE=SM8550"
grep -q 'SM8550_MINIMAL_HOST' "${SM8550_OPTIONS}" \
  || fail "SM8550 options must expose the minimal-host switch"
grep -q 'SM8550_FLASH_PARTITION_BUDGET_MIB' "${SM8550_OPTIONS}" \
  || fail "SM8550 options must declare a SYSTEM image size budget"
grep -q '\[ "\${BASE_ONLY}" = "true" \] || \[ "\${SM8550_MINIMAL_HOST:-no}" = "yes" \]' "${IMAGE_PKG}" \
  || fail "image package must use minimal-host path to skip product UX metas"
grep -q 'SM8550 minimal host pulled forbidden payload' "${IMAGE_PKG}" \
  || fail "image package must fail closed if minimal host reintroduces UX/emulation/network payloads"
grep -q '\[ "\${SM8550_MINIMAL_HOST:-no}" != "yes" \] && PKG_DEPENDS_TARGET+=" mako-osd"' "${IMAGE_PKG}" \
  || fail "mako-osd must be gated out of the SM8550 minimal host"
for forbidden in \
  mako-osd sway swaywm-env wlroots xwayland screen-switch gamepadcalibration \
  mesa-demos glmark2 vkmark emulators gamesupport retroarch lib32 tailscale \
  wireguard-tools corefonts poppler p7zip umtprd usb-modeswitch \
  ntfs-3g_ntfsprogs exfatprogs entware evtest patchelf; do
  grep -q " ${forbidden}" "${IMAGE_PKG}" || fail "image fail-closed guard must mention forbidden payload: ${forbidden}"
done
grep -q 'DISPLAYSERVER="no"' "${SM8550_OPTIONS}" || fail "SM8550 minimal host must disable host display server"
grep -q 'WINDOWMANAGER="none"' "${SM8550_OPTIONS}" || fail "SM8550 minimal host must disable host window manager"
grep -q 'EMULATION_DEVICE="no"' "${SM8550_OPTIONS}" || fail "SM8550 minimal host must disable host emulation device roots"
grep -q 'ENABLE_32BIT=no' "${IMAGE_PKG}" || fail "minimal-host image path must disable 32-bit roots"
grep -q 'PKG_DEPENDS_TARGET+=" i2c-tools ${ADDITIONAL_PACKAGES}"' "${IMAGE_PKG}" \
  || fail "SM8550 minimal host must keep i2c-tools while dropping patchelf/evtest/corefonts"
grep -q '\[ "\${SM8550_MINIMAL_HOST:-no}" != "yes" \] && PKG_DEPENDS_TARGET+=" umtprd usb-modeswitch poppler p7zip"' "${IMAGE_PKG}" \
  || fail "SM8550 minimal host must gate host USB/MTP/PDF/archive payloads out"
grep -q 'if \[ "\${SM8550_MINIMAL_HOST:-no}" != "yes" \]; then' "${IMAGE_PKG}" \
  || fail "SM8550 minimal host must gate entware out"
grep -q 'NTFS3G="no"' "${SM8550_OPTIONS}" || fail "SM8550 minimal host must disable NTFS3G"
grep -q 'EXFAT="no"' "${SM8550_OPTIONS}" || fail "SM8550 minimal host must disable exFAT"
grep -q 'ADDITIONAL_PACKAGES="rocknix-abl"' "${SM8550_OPTIONS}" \
  || fail "SM8550 minimal host must keep only ABL additional package; guest owns InputPlumber"
grep -q '075-mangohud-supported' "${QUIRKS_PKG}" \
  || fail "SM8550 minimal host must remove host MangoHud quirk"
grep -q '090-ui_service' "${QUIRKS_PKG}" \
  || fail "SM8550 minimal host must remove host UI service quirk"
grep -q '091-ui_shader' "${QUIRKS_PKG}" \
  || fail "SM8550 minimal host must remove host UI shader quirk"
grep -q 'Minimal SM8550 host keeps only what the recovery/update substrate needs' "${NETWORK_PKG}" \
  || fail "ROCKNIX network meta must document the minimal-host dependency set"
grep -q 'PKG_DEPENDS_TARGET="toolchain connman iwd netbase ethtool openssh iw wireless-regdb rsync nss-mdns"' "${NETWORK_PKG}" \
  || fail "ROCKNIX network meta must have a minimal-host dependency set"
grep -q 'Wi-Fi authentication/control moves to the NixOS guest' "${NETWORK_PKG}" \
  || fail "ROCKNIX network meta must document guest-owned Wi-Fi"
grep -q '\[ "${DEVICE:-}" = "SM8550" \] && \[ "${SM8550_MINIMAL_HOST:-no}" = "yes" \]' "${IWD_PKG}" \
  || fail "host iwd service must be disabled in SM8550 minimal-host mode"
grep -q 'wlan,wlan0,wl' "${CONNMAN_PKG}" \
  || fail "host ConnMan must blacklist Wi-Fi interfaces so the guest owns wlan0"
! sed -n '/if \[ "${SM8550_MINIMAL_HOST:-no}" = "yes" \]/,/else/p' "${NETWORK_PKG}" \
  | grep '^  PKG_DEPENDS_TARGET=' \
  | grep -Eq 'tailscale|wireguard-tools|zerotier-one|miniupnpc|speedtest-cli' \
  || fail "minimal-host network set must not include host VPN/network product extras"
grep -q 'SM8550 minimal host is SSH-first recovery' "${OPENSSH_PKG}" \
  || fail "openssh package must document deterministic SM8550 SSH-first recovery"
grep -q 'sed -e "\\|^Condition.*|d"' "${OPENSSH_PKG}" \
  || fail "openssh package must remove opt-in sshd conditions for SM8550 minimal host"
grep -q "inputs.DEVICE != 'SM8650' && inputs.DEVICE != 'SM8550'" "${WORKFLOW_DIR}/build-arm.yml" \
  || fail "SM8550 minimal host must skip 32-bit arm workflow"
for workflow in build-aarch64-image.yml build-image-only.yml; do
  grep -q "inputs.DEVICE != 'SM8650' && inputs.DEVICE != 'SM8550'" "${WORKFLOW_DIR}/${workflow}" \
    || fail "${workflow} must not download arm artifacts for SM8550"
  grep -q "inputs.DEVICE != 'SM8550'" "${WORKFLOW_DIR}/${workflow}" \
    || fail "${workflow} must skip emulator artifacts for SM8550"
done
grep -q "build-aarch64-mame-lr:" "${WORKFLOW_DIR}/build-device.yml" || fail "build-device workflow missing mame job"
grep -q "build-aarch64-qt6:" "${WORKFLOW_DIR}/build-device.yml" || fail "build-device workflow missing qt6 job"
grep -q "build-aarch64-emu-libretro:" "${WORKFLOW_DIR}/build-device.yml" || fail "build-device workflow missing emu-libretro job"
grep -q "build-aarch64-emu-standalone:" "${WORKFLOW_DIR}/build-device.yml" || fail "build-device workflow missing emu-standalone job"
[ "$(grep -c "if: \${{ inputs.DEVICE != 'SM8550'" "${WORKFLOW_DIR}/build-device.yml")" -ge 4 ] \
  || fail "build-device workflow must skip SM8550 host emulator/qt artifact jobs"
! grep -q 'gallium-nine' "${REPO_ROOT}/projects/ROCKNIX/packages/graphics/mesa/package.mk" \
  || fail "Mesa 26 no longer supports the gallium-nine Meson option"
! grep -q 'PKG_CONFIGURE_OPTS_TARGET="--disable-glx"' "${REPO_ROOT}/projects/ROCKNIX/packages/graphics/libepoxy/package.mk" \
  || fail "libepoxy must use Meson glx/x11 options, not the removed autotools --disable-glx flag"
grep -q 'PKG_MESON_OPTS_TARGET+=" -Dglx=no -Dx11=false"' "${REPO_ROOT}/projects/ROCKNIX/packages/graphics/libepoxy/package.mk" \
  || fail "libepoxy must disable glx/x11 through Meson options when no display server needs them"
grep -q 'if \[ "${DEVICE}" != "SM8550" \]' "${SYSTEMD_PKG}" \
  || fail "systemd package must strip nspawn on non-SM8550 devices"
grep -q 'safe_remove ${INSTALL}/usr/bin/systemd-nspawn' "${SYSTEMD_PKG}" || fail "systemd package missing nspawn binary removal fallback"
grep -q 'safe_remove ${INSTALL}/usr/lib/systemd/system/systemd-nspawn@.service' "${SYSTEMD_PKG}" || fail "systemd package missing nspawn unit removal fallback"
! grep -qE 'enable_service .*nspawn' "${SYSTEMD_PKG}" || fail "systemd package must not enable nspawn services by default"

# Old support flags should not be resurrected.
! grep -R --exclude='guest-substrate-static-checks.sh' -q 'NIX_INTEGRATION_SUPPORT\|NIX_NSPAWN_SUPPORT\|NIX_DAEMON_SUPPORT\|THIN_HOST' \
  "${REPO_ROOT}/projects/ROCKNIX" "${REPO_ROOT}/.github" "${REPO_ROOT}/scripts" || fail "removed support gate still referenced"

printf 'rocknix-guest-substrate static checks passed\n'
