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
check_script "${PKG_DIR}/scripts/rocknix-guest-prep"
check_script "${PKG_DIR}/scripts/rocknix-guest-promote"
check_script "${PKG_DIR}/scripts/rocknix-guest-start"
check_script "${PKG_DIR}/scripts/rocknix-guest-udev-stage"
check_script "${PKG_DIR}/scripts/rocknix-recovery-toggle"
check_script "${PKG_DIR}/scripts/rocknix-guest-soak"
check_script "${PKG_DIR}/scripts/rocknix-guest-generation-import"
check_script "${PKG_DIR}/scripts/rocknix-guest-generation-switch"
check_script "${PKG_DIR}/scripts/rocknix-guest-activation-audit"

grep -q 'rocknix-guest-prep' "${PKG_DIR}/package.mk" || fail "package.mk does not install prep helper"
grep -q 'rocknix-guest-promote' "${PKG_DIR}/package.mk" || fail "package.mk does not install guest promotion helper"
grep -q 'rocknix-guest-start' "${PKG_DIR}/package.mk" || fail "package.mk does not install guest start helper"
grep -q 'rocknix-guest-udev-stage' "${PKG_DIR}/package.mk" || fail "package.mk does not install udev stage helper"
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
grep -q 'sha256sum "${guest_tarball}.tmp"' "${PKG_DIR}/package.mk" || fail "package.mk must verify guest tarball sha256"
grep -q 'tar -xzf "${guest_tarball}"' "${PKG_DIR}/package.mk" || fail "package.mk must extract fetched guest tarball"
grep -q 'cp -PR "${guest_extract}/."' "${PKG_DIR}/package.mk" || fail "package.mk must stage fetched guest tree"
grep -q 'guest-revision' "${PKG_DIR}/package.mk" || fail "package.mk must ship packaged guest revision marker"
grep -q 'docs/contracts/layer14-main-space-contract.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship main-space contract doc from guest"
grep -q 'docs/contracts/layer14-soak-checklist.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship soak checklist from guest"
grep -q 'docs/contracts/HOW-TO-FALL-BACK.md' "${PKG_DIR}/package.mk" || fail "package.mk must ship fallback doc from guest"
grep -q 'SM8550_MINIMAL_HOST=yes' "${PKG_DIR}/package.mk" || fail "package.mk must document minimal-host fallback mode when enabled"

# Storage + guest service wiring. Host root /nix was retired: the guest
# system store lives under /storage/machines/rocknix-guest/nix and is resolved
# through GUEST_ROOT by the substrate scripts.
[ ! -e "${PKG_DIR}/system.d/nix-storage-setup.service" ] || fail "host nix-storage-setup.service must be retired"
[ ! -e "${PKG_DIR}/system.d/nix.mount" ] || fail "host nix.mount must be retired"
check_unit "${PKG_DIR}/system.d/rocknix-main-space.target"
check_unit "${PKG_DIR}/system.d/rocknix-guest.service"
check_unit "${PKG_DIR}/system.d/rocknix-guest-promote.service"
check_unit "${PKG_DIR}/system.d/rocknix-recovery-toggle.service"

! grep -q 'mkdir -p ${INSTALL}/nix' "${PKG_DIR}/package.mk" || fail "package.mk must not create host /nix mountpoint"
! grep -q 'enable_service nix-storage-setup.service' "${PKG_DIR}/package.mk" || fail "package.mk must not enable nix-storage-setup.service"
! grep -q 'enable_service nix.mount' "${PKG_DIR}/package.mk" || fail "package.mk must not enable nix.mount"
! grep -R -q 'nix.mount' "${PKG_DIR}/system.d" "${PKG_DIR}/package.mk" || fail "host units/package must not require host nix.mount"
grep -q 'enable_service rocknix-main-space.target' "${PKG_DIR}/package.mk" || fail "package.mk does not enable rocknix-main-space.target"
grep -q 'enable_service rocknix-guest.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable rocknix-guest.service"
grep -q 'enable_service rocknix-guest-promote.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable guest promotion service"
grep -q 'enable_service rocknix-recovery-toggle.service' "${PKG_DIR}/package.mk" || fail "package.mk does not enable recovery toggle"

grep -q 'Alias=default.target' "${PKG_DIR}/system.d/rocknix-main-space.target" || fail "rocknix-main-space.target must alias default.target"
! grep -q 'rocknix-graphical.target' "${PKG_DIR}/system.d/rocknix-main-space.target" || fail "rocknix-main-space.target must not keep old graphical-target alias"
grep -q 'Wants=rocknix-guest.service' "${PKG_DIR}/system.d/rocknix-main-space.target" || fail "rocknix-main-space.target must start guest unit"
! grep -q 'rocknix-automount.service' "${PKG_DIR}/system.d/rocknix-main-space.target" || fail "main-space target must not require host game-media automount"
grep -q 'Before=sysinit.target' "${PKG_DIR}/system.d/rocknix-recovery-toggle.service" || fail "recovery toggle must run before sysinit"
grep -q 'ExecStart=/usr/bin/rocknix-recovery-toggle' "${PKG_DIR}/system.d/rocknix-recovery-toggle.service" || fail "recovery toggle unit has wrong ExecStart"

guest_unit="${PKG_DIR}/system.d/rocknix-guest.service"
grep -q 'RequiresMountsFor=/storage' "${guest_unit}" || fail "guest unit must require storage only"
! grep -q 'RequiresMountsFor=/storage /nix' "${guest_unit}" || fail "guest unit must not require host /nix"
! grep -q 'Requires=nix.mount' "${guest_unit}" || fail "guest unit must not require host nix.mount"
grep -q 'StartLimitIntervalSec=5min' "${guest_unit}" || fail "guest unit must bound bad-generation restart loops"
grep -q 'StartLimitBurst=3' "${guest_unit}" || fail "guest unit must cap restart bursts"
grep -q 'StartLimitAction=none' "${guest_unit}" || fail "guest unit must not auto-reboot or auto-recover"
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

promote_unit="${PKG_DIR}/system.d/rocknix-guest-promote.service"
grep -q 'After=rocknix-guest.service' "${promote_unit}" || fail "guest promotion must run after guest boot"
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
grep -q "nix-env -p '\${LEGACY_PROFILE_GUEST}' --set" "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must mirror legacy guest system profile"
grep -q 'systemctl restart --no-block "${GUEST_SERVICE}"' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must restart guest after profile update"
grep -q 'rocknix-guest-revision' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must track applied guest revision"
grep -q 'rocknix-guest-system-path' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must track applied guest system path"
grep -q 'resolve_guest_system_profile' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must inspect persistent guest system profile"
grep -q 'guest_system_path_valid' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must verify applied system path has an executable init"
grep -q 'system profile drifted' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must repair profile drift when revision marker matches"
grep -q 'wait_for_guest_current_system' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must wait for guest current-system before repairing drift"
grep -q 'guest current system did not become available' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must fail clearly when guest current-system is unavailable"
grep -q 'applied system path is missing; rebuilding' "${PKG_DIR}/scripts/rocknix-guest-promote" || fail "guest promotion must rebuild if revision marker matches but system path is gone"
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
grep -q 'rocknix-guest-main-space-thor' "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must document explicit Thor off-device output"
grep -q 'live generation A is required for import' "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must require live generation A"
grep -q 'rocknix-stage10-proof-marker' "${PKG_DIR}/scripts/rocknix-guest-generation-import" || fail "generation import helper must require B proof marker"
grep -q 'rocknix-guest-manual-generation-hold' "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must require manual generation hold"
grep -q 'systemctl stop "${PROMOTE_SERVICE}"' "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must stop in-flight promotion"
grep -q 'systemctl reset-failed "${GUEST_SERVICE}"' "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must reset failed/start-limit state before restart"
grep -q 'selected/legacy differ before recording generation A' "${PKG_DIR}/scripts/rocknix-guest-generation-switch" || fail "generation switch helper must require clean A before recording rollback state"
grep -q 'rocknix-stage10-proof-marker' "${PKG_DIR}/scripts/rocknix-guest-activation-audit" || fail "activation audit must report B proof marker"
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
  legacy_profile="${guest_root}/nix/var/nix/profiles/system"
  set_profile "${selected_profile}" "rocknix-guest-system-1-link" "/nix/store/applied-system"
  set_profile "${legacy_profile}" "system-1-link" "/nix/store/applied-system"

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
  set_profile "${legacy_profile}" "system-1-link" "/nix/store/old-system"
  ROCKNIX_GUEST_HOST_PATH="${bin_dir}:${PATH}" \
    ROCKNIX_TEST_NSENTER_LOG="${nsenter_log}" \
    ROCKNIX_TEST_SYSTEMCTL_LOG="${systemctl_log}" \
    ROCKNIX_GUEST_ROOT="${guest_root}" \
    ROCKNIX_GUEST_DEVICE_COMPATIBLE_FILE="${compatible_file}" \
    ROCKNIX_GUEST_SOURCE="${guest_source}" \
    ROCKNIX_GUEST_REV_FILE="${guest_rev}" \
    ROCKNIX_GUEST_STAGED_SOURCE="${staged_source}" \
    "${PKG_DIR}/scripts/rocknix-guest-promote" >/dev/null
  grep -q "nix-env -p '/nix/var/nix/profiles/per-user/root/rocknix-guest-system' --set '/nix/store/applied-system'" "${nsenter_log}" \
    || fail "promote fixture: drift repair did not write selected profile"
  grep -q "nix-env -p '/nix/var/nix/profiles/system' --set '/nix/store/applied-system'" "${nsenter_log}" \
    || fail "promote fixture: drift repair did not mirror legacy profile"
  grep -q 'restart --no-block rocknix-guest.service' "${systemctl_log}" \
    || fail "promote fixture: drift repair did not restart guest"

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
  grep -q "nix-env -p '/nix/var/nix/profiles/system' --set '/nix/store/rebuilt-system'" "${nsenter_log}" \
    || fail "promote fixture: rebuild path did not mirror legacy profile"
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
grep -q 'systemctl set-default' "${PKG_DIR}/scripts/rocknix-recovery-toggle" || fail "recovery toggle must switch default target"

grep -q 'resolv.conf.guest-owned' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing resolv.conf ownership marker"
grep -q '/storage/.guest' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing guest writable area"
grep -q 'GUEST_STORAGE_ROOT=' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper must create guest-owned storage namespace"
grep -q '/nix/var/nix/profiles/per-user/root/rocknix-guest-system' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing selected guest system profile check"
grep -q '/nix/var/nix/profiles/system' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper missing legacy system profile fallback"
grep -q 'selected guest system profile missing or invalid; falling back to legacy profile' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper must log selected-profile fallback"
grep -q 'expected .*init to be executable' "${PKG_DIR}/scripts/rocknix-guest-prep" || fail "prep helper must validate selected/legacy init"

run_prep_profile_fixture() {
  tmp_dir=$(mktemp -d)
  guest_root="${tmp_dir}/guest-root"
  guest_area="${tmp_dir}/guest-area"
  mkdir -p \
    "${guest_root}/nix/var/nix/profiles/per-user/root" \
    "${guest_root}/nix/var/nix/profiles" \
    "${guest_root}/nix/store/selected-system" \
    "${guest_root}/nix/store/legacy-system" \
    "${guest_root}/etc" \
    "${guest_root}/sbin" \
    "${guest_area}"
  : > "${guest_root}/nix/store/selected-system/init"
  : > "${guest_root}/nix/store/legacy-system/init"
  chmod 0755 "${guest_root}/nix/store/selected-system/init" "${guest_root}/nix/store/legacy-system/init"
  ln -s /nix/store/selected-system "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system-1-link"
  ln -s rocknix-guest-system-1-link "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  ln -s /nix/store/legacy-system "${guest_root}/nix/var/nix/profiles/system-1-link"
  ln -s system-1-link "${guest_root}/nix/var/nix/profiles/system"

  ROCKNIX_GUEST_ROOT="${guest_root}" ROCKNIX_GUEST_AREA="${guest_area}" "${PKG_DIR}/scripts/rocknix-guest-prep" >/dev/null 2>&1
  [ "$(readlink "${guest_root}/init")" = "/nix/store/selected-system/init" ] || fail "prep fixture: selected profile did not win"
  [ "$(readlink "${guest_root}/sbin/init")" = "/nix/store/selected-system/init" ] || fail "prep fixture: selected profile did not relink sbin/init"

  rm -f "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  ROCKNIX_GUEST_ROOT="${guest_root}" ROCKNIX_GUEST_AREA="${guest_area}" "${PKG_DIR}/scripts/rocknix-guest-prep" >/dev/null 2>&1
  [ "$(readlink "${guest_root}/init")" = "/nix/store/legacy-system/init" ] || fail "prep fixture: missing selected profile did not fall back to legacy"

  ln -s rocknix-guest-system-1-link "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system"
  rm -f "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system-1-link"
  ln -s /nix/store/missing-system "${guest_root}/nix/var/nix/profiles/per-user/root/rocknix-guest-system-1-link"
  ROCKNIX_GUEST_ROOT="${guest_root}" ROCKNIX_GUEST_AREA="${guest_area}" "${PKG_DIR}/scripts/rocknix-guest-prep" >/dev/null 2>&1
  [ "$(readlink "${guest_root}/init")" = "/nix/store/legacy-system/init" ] || fail "prep fixture: invalid selected profile did not fall back to legacy"

  rm -f "${guest_root}/nix/var/nix/profiles/system"
  if ROCKNIX_GUEST_ROOT="${guest_root}" ROCKNIX_GUEST_AREA="${guest_area}" "${PKG_DIR}/scripts/rocknix-guest-prep" >/dev/null 2>&1; then
    fail "prep fixture: both profiles invalid should fail"
  fi

  rm -rf "${tmp_dir}"
}
run_prep_profile_fixture

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
[ -f "${SYSTEMD_PKG}" ] || fail "missing ROCKNIX systemd package.mk"
[ -f "${OPENSSH_PKG}" ] || fail "missing ROCKNIX openssh package.mk"
grep -q '\[ "\${DEVICE}" = "SM8550" \] && PKG_DEPENDS_TARGET+=" rocknix-guest-substrate"' "${IMAGE_PKG}" \
  || fail "image package must gate rocknix-guest-substrate on DEVICE=SM8550"
grep -q 'SM8550_MINIMAL_HOST' "${SM8550_OPTIONS}" \
  || fail "SM8550 options must expose the minimal-host switch"
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
