#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM

# Shared running-detector for systemd-nspawn guests, used by all layer smokes.
# Mirrors nixctl's nspawn_pid_for_root: identifies nspawn candidates by exec
# name (/proc/<pid>/comm) or by argv[0] basename (so wrapper scripts named
# 'systemd-nspawn' still match), then checks for the guest root in argv. This
# replaces the ps|grep '[s]ystemd-nspawn' idiom that self-matched any caller
# whose argv contained the literal substring.
smoke_nspawn_running() {
  root=$1
  [ -n "${root}" ] || return 1
  [ -d /proc ] || return 1
  norm=${root%/}
  for proc in /proc/[0-9]*; do
    [ -r "${proc}/cmdline" ] || continue
    args=$(tr '\0' '\n' <"${proc}/cmdline" 2>/dev/null) || continue
    [ -n "${args}" ] || continue
    argv0=$(printf '%s\n' "${args}" | head -n 1)
    base=${argv0##*/}
    comm=$(cat "${proc}/comm" 2>/dev/null) || comm=
    if [ "${comm}" != "systemd-nspawn" ] && [ "${base}" != "systemd-nspawn" ]; then
      continue
    fi
    if printf '%s\n' "${args}" | awk -v want="${norm}" '
      {
        a = $0
        sub(/\/+$/, "", a)
        if (a == want) { found = 1; exit }
        if (prev == "--directory" && a == want) { found = 1; exit }
        if (substr(a, 1, 12) == "--directory=") {
          v = substr(a, 13)
          sub(/\/+$/, "", v)
          if (v == want) { found = 1; exit }
        }
        prev = a
      }
      END { exit (found ? 0 : 1) }
    ' 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# Autostart-eligibility check for a systemd unit. Returns 0 only when the
# unit is enabled, enabled-runtime, or alias -- the three states that mean
# "systemd will start this on boot." Static units (no [Install] section,
# like the generated Layer 10 rocknix-guest.service) report 'static' from
# 'systemctl is-enabled', which exits 0 even though the unit is NOT auto-
# started. The legacy 'is-enabled --quiet' exit-code-only check therefore
# misclassified static units as autostart-eligible. This helper inspects
# stdout instead and only honours the documented autostart states.
unit_autostarts() {
  unit=$1
  [ -n "${unit}" ] || return 1
  command -v systemctl >/dev/null 2>&1 || return 1
  state=$(systemctl is-enabled "${unit}" 2>/dev/null) || state=
  case "${state}" in
    enabled|enabled-runtime|alias) return 0 ;;
    *) return 1 ;;
  esac
}

# Locate a smoke-relevant binary by name. Used by hardware-mode device-side
# sections so the packaged smoke at /usr/lib/nix-integration/tests/ can find
# /usr/bin/nixctl and /usr/bin/nix-doctor without depending on sibling
# directories that aren't installed there. Repo invocations fall through to
# ${PKG_DIR}/scripts/<name> as before.
resolve_smoke_bin() {
  name=$1
  [ -n "${name}" ] || return 1
  hit=$(command -v "${name}" 2>/dev/null || true)
  if [ -n "${hit}" ] && [ -x "${hit}" ]; then
    printf '%s\n' "${hit}"
    return 0
  fi
  if [ -x "${PKG_DIR}/scripts/${name}" ]; then
    printf '%s\n' "${PKG_DIR}/scripts/${name}"
    return 0
  fi
  echo "FAIL: smoke cannot resolve ${name}: not on PATH and not at ${PKG_DIR}/scripts/${name}" >&2
  return 1
}

# Map the user's LAYER*_SMOKE inputs to per-layer 'requested' booleans.
# Done early so the U4 hardware-only gate below can read them.
if [ "${LAYER10_SMOKE:-0}" = "1" ] || [ "${LAYER10_SMOKE:-0}" = "proof" ] || [ "${LAYER10_SMOKE:-0}" = "bootable" ]; then
  LAYER10_REQUESTED=1
else
  LAYER10_REQUESTED=0
fi
if [ "${LAYER11_SMOKE:-0}" = "1" ]; then
  LAYER11_REQUESTED=1
else
  LAYER11_REQUESTED=0
fi
if [ "${LAYER12_SMOKE:-0}" = "ssh" ]; then
  LAYER12_REQUESTED=1
else
  LAYER12_REQUESTED=0
fi

# Hardware-only mode: at least one hardware-mode flag is set
# (LAYER10_SMOKE=bootable, LAYER11_SMOKE=1, LAYER12_SMOKE=ssh) AND no
# CI-mode flag is set (LAYER4..LAYER9, LAYER10_SMOKE=proof|1). When this is
# true, skip the CI fixture preamble: those fixtures assume a clean
# unconfigured device and pin error strings (e.g. 'refusing unsafe guest
# root') that don't match real failure paths on a configured device.
HARDWARE_ONLY_MODE=0
if { [ "${LAYER10_SMOKE:-0}" = "bootable" ] || [ "${LAYER11_REQUESTED}" = "1" ] || [ "${LAYER12_REQUESTED}" = "1" ]; } \
   && [ "${LAYER4_SMOKE:-0}" != "1" ] \
   && [ "${LAYER5_SMOKE:-0}" != "1" ] \
   && [ "${LAYER6_SMOKE:-0}" != "1" ] \
   && [ "${LAYER7_SMOKE:-0}" != "1" ] \
   && [ "${LAYER8_SMOKE:-0}" != "1" ] \
   && [ "${LAYER9_SMOKE:-0}" != "1" ] \
   && [ "${LAYER10_SMOKE:-0}" != "proof" ] \
   && [ "${LAYER10_SMOKE:-0}" != "1" ]; then
  HARDWARE_ONLY_MODE=1
fi

if [ "${HARDWARE_ONLY_MODE}" = "0" ]; then
# ---- CI fixture preamble (skipped in hardware-only mode) -------------------

# Layer 5 profile contract: the profile.d snippet must expose the root Nix
# profile before Layer 4 and storage-local user env paths, and must be idempotent.
PROFILE_ENV="${TMP_DIR}/profile-env"
HOME="${TMP_DIR}/home" PATH="/usr/bin:/usr/sbin" /bin/sh -c \
  '. "'"${PKG_DIR}/profile.d/998-nix-integration.conf"'"; . "'"${PKG_DIR}/profile.d/998-nix-integration.conf"'"; printf "%s\n" "$PATH"' \
  >"${PROFILE_ENV}"
PROFILE_PATH=$(cat "${PROFILE_ENV}")
case "${PROFILE_PATH}" in
  "${TMP_DIR}/home/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/storage/bin:"*) ;;
  *) echo "FAIL: profile.d PATH order unexpected: ${PROFILE_PATH}" >&2; exit 1 ;;
esac
case "${PROFILE_PATH}" in
  *".nix-profile/bin"*".nix-profile/bin"*) echo "FAIL: profile.d duplicated .nix-profile path" >&2; exit 1 ;;
esac

mkdir -p "${TMP_DIR}/layer8-doctor-config"
printf 'experimental-features = nix-command flakes\nbuild-users-group =\n' >"${TMP_DIR}/layer8-doctor-config/nix.conf"
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-doctor-smoke.log || true
grep -q 'Layer 8 daemon state: inactive' /tmp/nix-doctor-smoke.log
grep -q 'Layer 8 daemon eligibility:' /tmp/nix-doctor-smoke.log
"${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer8-nixctl-status.log
grep -q 'Layer 8 (experimental daemon) status' /tmp/nix-layer8-nixctl-status.log
grep -q 'fallback:   Layer 4 single-user/root Nix remains primary' /tmp/nix-layer8-nixctl-status.log
NIX_LAYER8_SYSTEMD_DIR="${PKG_DIR}/system.d" \
  "${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer8-unit-status.log
grep -q 'socket:     .*nix-daemon.socket' /tmp/nix-layer8-unit-status.log
grep -q 'service:    .*nix-daemon.service' /tmp/nix-layer8-unit-status.log
FAKE_NSPAWN="${TMP_DIR}/systemd-nspawn"
cat >"${FAKE_NSPAWN}" <<'EOF'
#!/bin/sh
case " $* " in
  *' --boot '*) sleep 300 ;;
  *) echo 'systemd-nspawn smoke-test' ;;
esac
EOF
chmod 0755 "${FAKE_NSPAWN}"
mkdir -p "${TMP_DIR}/layer9-root/etc" "${TMP_DIR}/layer9-state"
NIX_LAYER9_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${TMP_DIR}/layer9-root" \
NIX_LAYER9_STATE_DIR="${TMP_DIR}/layer9-state" \
NIX_LAYER9_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer9-proof-ready-status.log
grep -q 'Layer 9 (nspawn guest proof) status' /tmp/nix-layer9-proof-ready-status.log
grep -q 'state:      proof-ready' /tmp/nix-layer9-proof-ready-status.log
grep -q 'fallback:   host Layers 4/8 remain the recovery path' /tmp/nix-layer9-proof-ready-status.log
NIX_LAYER9_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${TMP_DIR}/layer9-root" \
NIX_LAYER9_STATE_DIR="${TMP_DIR}/layer9-state" \
NIX_LAYER9_SKIP_KERNEL_CHECK=1 \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer9-doctor-proof-ready.log || true
grep -q 'Layer 9 nspawn guest state: proof-ready' /tmp/nix-layer9-doctor-proof-ready.log
grep -q 'Layer 9 nspawn eligibility: available: nspawn guest proof prerequisites present' /tmp/nix-layer9-doctor-proof-ready.log
NIX_LAYER9_NSPAWN_BIN="${TMP_DIR}/missing-nspawn" \
NIX_LAYER9_GUEST_ROOT="${TMP_DIR}/missing-root" \
NIX_LAYER9_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer9-unsupported-status.log
grep -q 'state:      unsupported' /tmp/nix-layer9-unsupported-status.log
mkdir -p "${TMP_DIR}/layer10-proof-root/nix" "${TMP_DIR}/layer10-proof-root/bin" "${TMP_DIR}/layer10-state"
printf '#!/bin/sh\n' >"${TMP_DIR}/layer10-proof-root/bin/sh"
chmod 0755 "${TMP_DIR}/layer10-proof-root/bin/sh"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" guest status >/tmp/nix-layer10-proof-status.log
grep -q 'Layer 10 (managed nspawn guest operations) status' /tmp/nix-layer10-proof-status.log
grep -q 'state:      proof-ready' /tmp/nix-layer10-proof-status.log
grep -q 'mode:       proof' /tmp/nix-layer10-proof-status.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" guest preflight >/tmp/nix-layer10-proof-preflight.log
grep -q 'Layer 10 guest preflight passed' /tmp/nix-layer10-proof-preflight.log
mkdir -p "${TMP_DIR}/layer11-bin" "${TMP_DIR}/layer11-state"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
  "${PKG_DIR}/scripts/nixctl" bridge status >/tmp/nix-layer11-status.log
grep -q 'Layer 11 (one-shot guest-backed bridges) status' /tmp/nix-layer11-status.log
grep -q 'bridges:    0' /tmp/nix-layer11-status.log
grep -q 'eligible:   available: Layer 10 one-shot guest execution ready' /tmp/nix-layer11-status.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
  "${PKG_DIR}/scripts/nixctl" bridge preflight layer11-smoke >/tmp/nix-layer11-preflight.log
grep -q 'Layer 11 bridge preflight passed: layer11-smoke' /tmp/nix-layer11-preflight.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
NIX_LAYER11_NIXCTL_BIN="${PKG_DIR}/scripts/nixctl" \
  "${PKG_DIR}/scripts/nixctl" bridge install layer11-smoke -- /usr/bin/nix --version >/tmp/nix-layer11-install.log
[ -x "${TMP_DIR}/layer11-bin/layer11-smoke" ]
grep -q 'bridge run layer11-smoke' "${TMP_DIR}/layer11-bin/layer11-smoke"
grep -q 'target=' "${TMP_DIR}/layer11-state/bridges/layer11-smoke/metadata"
grep -q "'/usr/bin/nix' '--version'" "${TMP_DIR}/layer11-state/bridges/layer11-smoke/command"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
NIX_LAYER11_NIXCTL_BIN="${PKG_DIR}/scripts/nixctl" \
  "${PKG_DIR}/scripts/nixctl" bridge install layer11-smoke -- /usr/bin/nix-store --version >/tmp/nix-layer11-reinstall.log
grep -q "'/usr/bin/nix-store' '--version'" "${TMP_DIR}/layer11-state/bridges/layer11-smoke/command"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER10_LOG="${TMP_DIR}/layer11-bridge-guest.log" \
NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
  "${TMP_DIR}/layer11-bin/layer11-smoke" >/tmp/nix-layer11-wrapper-run.log
grep -q 'systemd-nspawn smoke-test' /tmp/nix-layer11-wrapper-run.log
grep -q 'proof-ready' "${TMP_DIR}/layer10-state/state"
printf 'user-owned\n' >"${TMP_DIR}/layer11-bin/layer11-conflict"
if NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
  NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
  NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
  NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
  NIX_LAYER11_NIXCTL_BIN="${PKG_DIR}/scripts/nixctl" \
  "${PKG_DIR}/scripts/nixctl" bridge install layer11-conflict -- /usr/bin/nix --version >/tmp/nix-layer11-conflict.log 2>&1; then
  echo 'expected Layer 11 install to refuse non-owned conflict' >&2
  exit 1
fi
grep -q 'target exists and is not owned by Layer 11' /tmp/nix-layer11-conflict.log
grep -q 'user-owned' "${TMP_DIR}/layer11-bin/layer11-conflict"
NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
  "${PKG_DIR}/scripts/nixctl" bridge remove layer11-smoke >/tmp/nix-layer11-remove.log
[ ! -e "${TMP_DIR}/layer11-bin/layer11-smoke" ]
[ ! -e "${TMP_DIR}/layer11-state/bridges/layer11-smoke" ]
if NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
  NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
  "${PKG_DIR}/scripts/nixctl" bridge remove layer11-conflict >/tmp/nix-layer11-remove-conflict.log 2>&1; then
  echo 'expected Layer 11 remove to refuse non-owned bridge' >&2
  exit 1
fi
grep -q 'bridge is not Layer 11-owned' /tmp/nix-layer11-remove-conflict.log
if NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
  NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
  NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
  NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
  "${PKG_DIR}/scripts/nixctl" bridge preflight '../bad' >/tmp/nix-layer11-bad-name.log 2>&1; then
  echo 'expected Layer 11 preflight to reject unsafe bridge name' >&2
  exit 1
fi
grep -q 'unsafe bridge name' /tmp/nix-layer11-bad-name.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER11_BIN_DIR="${TMP_DIR}/layer11-bin" \
NIX_LAYER11_STATE_DIR="${TMP_DIR}/layer11-state" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-layer11-doctor.log || true
grep -q 'Layer 11 installed bridge count: 0' /tmp/nix-layer11-doctor.log
grep -q 'Layer 11 bridge eligibility: available: Layer 10 one-shot guest execution ready' /tmp/nix-layer11-doctor.log
mkdir -p "${TMP_DIR}/layer10-boot-root/sbin"
printf '#!/bin/sh\n' >"${TMP_DIR}/layer10-boot-root/sbin/init"
chmod 0755 "${TMP_DIR}/layer10-boot-root/sbin/init"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-boot-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" guest status >/tmp/nix-layer10-boot-status.log
grep -q 'state:      bootable-ready' /tmp/nix-layer10-boot-status.log
grep -q 'mode:       bootable' /tmp/nix-layer10-boot-status.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-boot-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-layer10-doctor-bootable.log || true
grep -q 'Layer 10 guest lifecycle state: bootable-ready' /tmp/nix-layer10-doctor-bootable.log
grep -q 'Layer 10 guest eligibility: available: bootable guest root ready for manual start' /tmp/nix-layer10-doctor-bootable.log
mkdir -p "${TMP_DIR}/layer10-import-src/sbin" "${TMP_DIR}/layer10-import-src/nix/store/fake-systemd/bin"
printf '#!/bin/sh\n' >"${TMP_DIR}/layer10-import-src/sbin/init"
printf '#!/bin/sh\nexit 0\n' >"${TMP_DIR}/layer10-import-src/nix/store/fake-systemd/bin/systemd-nspawn"
chmod 0755 "${TMP_DIR}/layer10-import-src/sbin/init" "${TMP_DIR}/layer10-import-src/nix/store/fake-systemd/bin/systemd-nspawn"
tar -cf "${TMP_DIR}/layer10-bootable.tar" -C "${TMP_DIR}/layer10-import-src" .
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
  "${PKG_DIR}/scripts/nixctl" guest import --bootable "${TMP_DIR}/layer10-bootable.tar" >/tmp/nix-layer10-import.log
[ -x "${TMP_DIR}/layer10-import-root/sbin/init" ]
grep -q 'bootable-ready' "${TMP_DIR}/layer10-import-state/state"
grep -q '^sha256=' "${TMP_DIR}/layer10-import-state/rootfs-provenance"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-layer10-import-doctor.log || true
grep -q 'Layer 10 bootable provenance recorded' /tmp/nix-layer10-import-doctor.log
mkdir -p "${TMP_DIR}/storage-keys"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILayer12RuntimeSmokeKey layer12-smoke\n' >"${TMP_DIR}/storage-keys/authorized_keys"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service status >/tmp/nix-layer12-status-unconfigured.log
grep -q 'Layer 12 (opt-in guest SSH) status' /tmp/nix-layer12-status-unconfigured.log
grep -q 'state:      unconfigured' /tmp/nix-layer12-status-unconfigured.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service preflight ssh >/tmp/nix-layer12-preflight.log
grep -q 'Layer 12 guest SSH preflight passed' /tmp/nix-layer12-preflight.log
if NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
  NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
  NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service enable ssh --port 2222 >/tmp/nix-layer12-enable-missing-keys.log 2>&1; then
  echo 'expected Layer 12 SSH enable to require authorized keys' >&2
  exit 1
fi
grep -q -- '--authorized-keys is required' /tmp/nix-layer12-enable-missing-keys.log
if NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
  NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
  NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service enable ssh --port 22 --authorized-keys "${TMP_DIR}/storage-keys/authorized_keys" >/tmp/nix-layer12-enable-port22.log 2>&1; then
  echo 'expected Layer 12 SSH enable to refuse port 22' >&2
  exit 1
fi
grep -q 'refusing unsafe port: 22' /tmp/nix-layer12-enable-port22.log
if NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
  NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
  NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service enable ssh --port 2223 --authorized-keys "${TMP_DIR}/storage-keys/authorized_keys" >/tmp/nix-layer12-enable-port2223.log 2>&1; then
  echo 'expected Layer 12 SSH enable to reject non-default port until guest config is dynamic' >&2
  exit 1
fi
grep -q 'currently supports only port 2222' /tmp/nix-layer12-enable-port2223.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service enable ssh --port 2222 --authorized-keys "${TMP_DIR}/storage-keys/authorized_keys" >/tmp/nix-layer12-enable.log
grep -q 'Layer 12 guest SSH configured on host port 2222' /tmp/nix-layer12-enable.log
grep -q '^service=ssh' "${TMP_DIR}/layer12-state/ssh/metadata"
grep -q '^state=configured' "${TMP_DIR}/layer12-state/ssh/metadata"
grep -q '^port=2222' "${TMP_DIR}/layer12-state/ssh/metadata"
grep -q '^authorized_keys_sha256=' "${TMP_DIR}/layer12-state/ssh/metadata"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service status >/tmp/nix-layer12-status-ready.log
grep -q 'state:      ready' /tmp/nix-layer12-status-ready.log
grep -q 'port:       2222' /tmp/nix-layer12-status-ready.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-layer12-doctor.log || true
grep -q 'Layer 12 guest SSH state: ready' /tmp/nix-layer12-doctor.log
grep -q 'Layer 12 guest SSH port: 2222' /tmp/nix-layer12-doctor.log
grep -q 'Layer 12 authorized keys checksum recorded' /tmp/nix-layer12-doctor.log
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service disable ssh >/tmp/nix-layer12-disable.log
grep -q 'Layer 12 guest SSH disabled' /tmp/nix-layer12-disable.log
grep -q '^state=disabled' "${TMP_DIR}/layer12-state/ssh/metadata"
if NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service remove ssh >/tmp/nix-layer12-remove-without-yes.log 2>&1; then
  echo 'expected Layer 12 SSH remove to require --yes' >&2
  exit 1
fi
grep -q 'without --yes' /tmp/nix-layer12-remove-without-yes.log
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-state" \
  "${PKG_DIR}/scripts/nixctl" guest service remove ssh --yes >/tmp/nix-layer12-remove.log
grep -q 'Layer 12 guest SSH metadata removed' /tmp/nix-layer12-remove.log
[ ! -e "${TMP_DIR}/layer12-state/ssh" ]
mkdir -p "${TMP_DIR}/layer10-import-symlink-src/sbin" "${TMP_DIR}/layer10-import-symlink-src/nix/store/fake-systemd/bin"
printf '#!/bin/sh\n' >"${TMP_DIR}/layer10-import-symlink-src/nix/store/fake-systemd/bin/init"
printf '#!/bin/sh\nexit 0\n' >"${TMP_DIR}/layer10-import-symlink-src/nix/store/fake-systemd/bin/systemd-nspawn"
chmod 0755 "${TMP_DIR}/layer10-import-symlink-src/nix/store/fake-systemd/bin/init" "${TMP_DIR}/layer10-import-symlink-src/nix/store/fake-systemd/bin/systemd-nspawn"
ln -s /nix/store/fake-systemd/bin/init "${TMP_DIR}/layer10-import-symlink-src/sbin/init"
tar -cf "${TMP_DIR}/layer10-bootable-symlink.tar" -C "${TMP_DIR}/layer10-import-symlink-src" .
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-symlink-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-symlink-state" \
  "${PKG_DIR}/scripts/nixctl" guest import --bootable "${TMP_DIR}/layer10-bootable-symlink.tar" >/tmp/nix-layer10-import-symlink.log
[ -L "${TMP_DIR}/layer10-import-symlink-root/sbin/init" ]
grep -q 'bootable-ready' "${TMP_DIR}/layer10-import-symlink-state/state"
tar -czf "${TMP_DIR}/layer10-bootable.tar.gz" -C "${TMP_DIR}/layer10-import-src" .
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-gzip-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-gzip-state" \
  "${PKG_DIR}/scripts/nixctl" guest import --bootable "${TMP_DIR}/layer10-bootable.tar.gz" >/tmp/nix-layer10-import-gzip.log
[ -x "${TMP_DIR}/layer10-import-gzip-root/sbin/init" ]
grep -q '^sha256=' "${TMP_DIR}/layer10-import-gzip-state/rootfs-provenance"
if NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
  "${PKG_DIR}/scripts/nixctl" guest import --bootable "${TMP_DIR}/layer10-bootable.tar" >/tmp/nix-layer10-import-existing.log 2>&1; then
  echo 'expected Layer 10 bootable import to refuse existing root' >&2
  exit 1
fi
grep -q 'root already exists' /tmp/nix-layer10-import-existing.log
if NIX_LAYER10_GUEST_ROOT="/storage" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-unsafe-state" \
  "${PKG_DIR}/scripts/nixctl" guest import --bootable "${TMP_DIR}/layer10-bootable.tar" >/tmp/nix-layer10-import-unsafe.log 2>&1; then
  echo 'expected Layer 10 bootable import to refuse unsafe root' >&2
  exit 1
fi
grep -q 'refusing unsafe guest root' /tmp/nix-layer10-import-unsafe.log
if NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-missing-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-missing-state" \
  "${PKG_DIR}/scripts/nixctl" guest import --bootable "${TMP_DIR}/missing-layer10.tar" >/tmp/nix-layer10-import-missing.log 2>&1; then
  echo 'expected Layer 10 bootable import to refuse missing artifact' >&2
  exit 1
fi
grep -q 'artifact is not a regular file' /tmp/nix-layer10-import-missing.log
mkdir -p "${TMP_DIR}/layer10-stale-state"
printf 'running\n' >"${TMP_DIR}/layer10-stale-state/state"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-boot-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-stale-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" guest status >/tmp/nix-layer10-stale-status.log
grep -q 'state:      failed' /tmp/nix-layer10-stale-status.log
if NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
  NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-missing-root" \
  NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  "${PKG_DIR}/scripts/nixctl" guest preflight >/tmp/nix-layer10-missing-preflight.log 2>&1; then
  echo 'expected Layer 10 preflight to fail with missing guest root' >&2
  exit 1
fi
grep -q 'guest preflight failed: available: guest root missing' /tmp/nix-layer10-missing-preflight.log
FAKE_LAYER10_SYSTEMCTL="${TMP_DIR}/systemctl-layer10"
cat >"${FAKE_LAYER10_SYSTEMCTL}" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${NIX_SYSTEMCTL_LOG}"
pid_file=${NIX_SYSTEMCTL_PID:-/tmp/nix-layer10-systemctl.pid}
case "$1" in
  is-active)
    if [ -f "${pid_file}" ] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
      echo active
      exit 0
    fi
    echo inactive
    exit 3
    ;;
  daemon-reload) exit 0 ;;
  start)
    "${NIX_LAYER10_NSPAWN_BIN}" --boot --register=no --directory="${NIX_LAYER10_GUEST_ROOT}" >/dev/null 2>&1 &
    echo $! >"${pid_file}"
    exit 0
    ;;
  stop)
    if [ -f "${pid_file}" ]; then
      kill "$(cat "${pid_file}")" 2>/dev/null || true
      rm -f "${pid_file}"
    fi
    exit 0
    ;;
  enable) exit 99 ;;
  *) exit 0 ;;
esac
EOF
chmod 0755 "${FAKE_LAYER10_SYSTEMCTL}"
FAKE_LAYER10_ACTIVE_SYSTEMCTL="${TMP_DIR}/systemctl-layer10-active-no-process"
cat >"${FAKE_LAYER10_ACTIVE_SYSTEMCTL}" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${NIX_SYSTEMCTL_LOG}"
case "$1" in
  is-active) echo active; exit 0 ;;
  daemon-reload|start|stop) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod 0755 "${FAKE_LAYER10_ACTIVE_SYSTEMCTL}"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-boot-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-active-no-process-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_SYSTEMCTL="${FAKE_LAYER10_ACTIVE_SYSTEMCTL}" \
NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-layer10-active-no-process.log" \
  "${PKG_DIR}/scripts/nixctl" guest status >/tmp/nix-layer10-active-no-process-status.log
 grep -q 'state:      failed' /tmp/nix-layer10-active-no-process-status.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-boot-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-active-no-process-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_SYSTEMCTL="${FAKE_LAYER10_ACTIVE_SYSTEMCTL}" \
NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-layer10-active-no-process.log" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-doctor-state" \
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-doctor-config/nix.conf" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-layer10-active-no-process-doctor.log 2>&1 || true
grep -q 'unit is active but no nspawn process references' /tmp/nix-layer10-active-no-process-doctor.log
if NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
  NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-proof-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-start-proof-state" \
  NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  NIX_SYSTEMCTL="${FAKE_LAYER10_SYSTEMCTL}" \
  NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-layer10-proof.log" \
  "${PKG_DIR}/scripts/nixctl" guest start >/tmp/nix-layer10-proof-start.log 2>&1; then
  echo 'expected Layer 10 start to refuse proof rootfs' >&2
  exit 1
fi
grep -q 'start requires bootable rootfs' /tmp/nix-layer10-proof-start.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-boot-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-start-state" \
NIX_LAYER10_SYSTEMD_DIR="${TMP_DIR}/layer10-systemd" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_SYSTEMCTL="${FAKE_LAYER10_SYSTEMCTL}" \
NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-layer10.log" \
NIX_SYSTEMCTL_PID="${TMP_DIR}/systemctl-layer10.pid" \
  "${PKG_DIR}/scripts/nixctl" guest start >/tmp/nix-layer10-start.log
[ -f "${TMP_DIR}/layer10-systemd/rocknix-guest.service" ]
grep -q -- '--register=no' "${TMP_DIR}/layer10-systemd/rocknix-guest.service"
grep -q -- '--private-network' "${TMP_DIR}/layer10-systemd/rocknix-guest.service"
grep -q 'CPUWeight=1' "${TMP_DIR}/layer10-systemd/rocknix-guest.service"
! grep -q '^\[Install\]' "${TMP_DIR}/layer10-systemd/rocknix-guest.service"
grep -q '^start rocknix-guest.service' "${TMP_DIR}/systemctl-layer10.log"
! grep -q '^enable' "${TMP_DIR}/systemctl-layer10.log"
grep -q 'running' "${TMP_DIR}/layer10-start-state/state"
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-boot-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-start-state" \
NIX_LAYER10_SYSTEMD_DIR="${TMP_DIR}/layer10-systemd" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_SYSTEMCTL="${FAKE_LAYER10_SYSTEMCTL}" \
NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-layer10.log" \
NIX_SYSTEMCTL_PID="${TMP_DIR}/systemctl-layer10.pid" \
  "${PKG_DIR}/scripts/nixctl" guest stop >/tmp/nix-layer10-stop.log
grep -q '^stop rocknix-guest.service' "${TMP_DIR}/systemctl-layer10.log"
grep -q 'stopped' "${TMP_DIR}/layer10-start-state/state"
mkdir -p "${TMP_DIR}/layer12-start-keys"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILayer12StartSmokeKey layer12-start\n' >"${TMP_DIR}/layer12-start-keys/authorized_keys"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-start-state" \
  "${PKG_DIR}/scripts/nixctl" guest service enable ssh --port 2222 --authorized-keys "${TMP_DIR}/layer12-start-keys/authorized_keys" >/tmp/nix-layer12-start-enable.log
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SYSTEMD_DIR="${TMP_DIR}/layer12-systemd" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-start-state" \
NIX_SYSTEMCTL="${FAKE_LAYER10_SYSTEMCTL}" \
NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-layer12.log" \
NIX_SYSTEMCTL_PID="${TMP_DIR}/systemctl-layer12.pid" \
  "${PKG_DIR}/scripts/nixctl" guest start >/tmp/nix-layer12-start.log
[ -f "${TMP_DIR}/layer12-systemd/rocknix-guest.service" ]
! grep -q -- '--private-network' "${TMP_DIR}/layer12-systemd/rocknix-guest.service"
! grep -q -- '--port=tcp:' "${TMP_DIR}/layer12-systemd/rocknix-guest.service"
grep -q -- "--bind-ro=${TMP_DIR}/layer12-start-keys/authorized_keys:/etc/ssh/authorized_keys.d/root" "${TMP_DIR}/layer12-systemd/rocknix-guest.service"
! grep -q -- '--port=tcp:22:22' "${TMP_DIR}/layer12-systemd/rocknix-guest.service"
if NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
  NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
  NIX_LAYER10_SYSTEMD_DIR="${TMP_DIR}/layer12-systemd" \
  NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
  NIX_LAYER12_STATE_DIR="${TMP_DIR}/layer12-start-state" \
  NIX_SYSTEMCTL="${FAKE_LAYER10_SYSTEMCTL}" \
  NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-layer12.log" \
  NIX_SYSTEMCTL_PID="${TMP_DIR}/systemctl-layer12.pid" \
  "${PKG_DIR}/scripts/nixctl" guest start >/tmp/nix-layer12-start-while-running.log 2>&1; then
  echo 'expected Layer 12 start to refuse already-running guest' >&2
  exit 1
fi
grep -q 'already running' /tmp/nix-layer12-start-while-running.log
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-import-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-import-state" \
NIX_LAYER10_SYSTEMD_DIR="${TMP_DIR}/layer12-systemd" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_SYSTEMCTL="${FAKE_LAYER10_SYSTEMCTL}" \
NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl-layer12.log" \
NIX_SYSTEMCTL_PID="${TMP_DIR}/systemctl-layer12.pid" \
  "${PKG_DIR}/scripts/nixctl" guest stop >/tmp/nix-layer12-stop.log
mkdir -p "${TMP_DIR}/nix/store/fake-nix/bin" "${TMP_DIR}/nix/store/fake-nix-store/bin" "${TMP_DIR}/nix/store/fake-bash/bin"
printf '#!/bin/sh\necho nix-fake\n' >"${TMP_DIR}/nix/store/fake-nix/bin/nix"
cat >"${TMP_DIR}/nix/store/fake-nix-store/bin/nix-store" <<EOF
#!/bin/sh
printf '%s\n' '${TMP_DIR}/nix/store/fake-nix' '${TMP_DIR}/nix/store/fake-nix-store' '${TMP_DIR}/nix/store/fake-bash'
EOF
printf '#!/bin/sh\necho bash-fake\n' >"${TMP_DIR}/nix/store/fake-bash/bin/bash"
chmod 0755 "${TMP_DIR}/nix/store/fake-nix/bin/nix" "${TMP_DIR}/nix/store/fake-nix-store/bin/nix-store" "${TMP_DIR}/nix/store/fake-bash/bin/bash"
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-init-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-init-state" \
NIX_LAYER10_NIX_BIN="${TMP_DIR}/nix/store/fake-nix/bin/nix" \
NIX_LAYER10_NIX_STORE_BIN="${TMP_DIR}/nix/store/fake-nix-store/bin/nix-store" \
NIX_LAYER10_BASH_BIN="${TMP_DIR}/nix/store/fake-bash/bin/bash" \
  "${PKG_DIR}/scripts/nixctl" guest init --proof >/tmp/nix-layer10-init-proof.log
[ -L "${TMP_DIR}/layer10-init-root/bin/sh" ]
[ -L "${TMP_DIR}/layer10-init-root/usr/bin/nix" ]
[ -d "${TMP_DIR}/layer10-init-root/nix/store/fake-nix" ]
grep -q 'proof-ready' "${TMP_DIR}/layer10-init-state/state"
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-init-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-init-state" \
NIX_LAYER10_SKIP_KERNEL_CHECK=1 \
NIX_LAYER10_LOG="${TMP_DIR}/layer10-run.log" \
  "${PKG_DIR}/scripts/nixctl" guest run /bin/sh -lc 'nix --version' >/tmp/nix-layer10-run.log
grep -q 'systemd-nspawn smoke-test' /tmp/nix-layer10-run.log
grep -q 'proof-ready' "${TMP_DIR}/layer10-init-state/state"
if NIX_LAYER10_GUEST_ROOT="/storage" \
  NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-unsafe-state" \
  "${PKG_DIR}/scripts/nixctl" guest cleanup --yes >/tmp/nix-layer10-unsafe-cleanup.log 2>&1; then
  echo 'expected Layer 10 cleanup to refuse unsafe root' >&2
  exit 1
fi
grep -q 'guest cleanup: refusing unsafe guest root' /tmp/nix-layer10-unsafe-cleanup.log
NIX_LAYER10_GUEST_ROOT="${TMP_DIR}/layer10-init-root" \
NIX_LAYER10_STATE_DIR="${TMP_DIR}/layer10-init-state" \
  "${PKG_DIR}/scripts/nixctl" guest cleanup --yes >/tmp/nix-layer10-cleanup.log
[ ! -e "${TMP_DIR}/layer10-init-root" ]
[ ! -e "${TMP_DIR}/layer10-init-state" ]
mkdir -p "${TMP_DIR}/layer8-empty-config"
printf 'experimental-features = nix-command flakes\nbuild-users-group =\n' >"${TMP_DIR}/layer8-empty-config/nix.conf"
if NIX_LAYER8_SYSTEMD_DIR="${PKG_DIR}/system.d" \
  NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-empty-config/nix.conf" \
  "${PKG_DIR}/scripts/nixctl" daemon preflight >/tmp/nix-layer8-preflight.log 2>&1; then
  echo 'expected Layer 8 preflight to fail with empty build-users-group' >&2
  exit 1
fi
grep -q 'daemon preflight failed:' /tmp/nix-layer8-preflight.log
FAKE_SYSTEMCTL="${TMP_DIR}/systemctl"
cat >"${FAKE_SYSTEMCTL}" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${NIX_SYSTEMCTL_LOG}"
case "$1" in
  is-active) echo inactive; exit 3 ;;
  enable|disable|stop) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod 0755 "${FAKE_SYSTEMCTL}"
mkdir -p "${TMP_DIR}/layer8-rollback-state"
printf 'active\n' >"${TMP_DIR}/layer8-rollback-state/state"
NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-rollback-state" \
NIX_SYSTEMCTL="${FAKE_SYSTEMCTL}" \
NIX_SYSTEMCTL_LOG="${TMP_DIR}/systemctl.log" \
  "${PKG_DIR}/scripts/nixctl" daemon rollback >/tmp/nix-layer8-rollback.log
[ ! -e "${TMP_DIR}/layer8-rollback-state/state" ]
grep -q 'disable --now nix-daemon.socket' "${TMP_DIR}/systemctl.log"
grep -q 'stop nix-daemon.service' "${TMP_DIR}/systemctl.log"
grep -q 'Layer 8 daemon mode disabled' /tmp/nix-layer8-rollback.log
mkdir -p "${TMP_DIR}/layer8-active-state" "${TMP_DIR}/layer8-active-config"
printf 'active\n' >"${TMP_DIR}/layer8-active-state/state"
printf 'experimental-features = nix-command flakes\nbuild-users-group =\n' >"${TMP_DIR}/layer8-active-config/nix.conf"
if NIX_LAYER8_STATE_DIR="${TMP_DIR}/layer8-active-state" \
  NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-active-config/nix.conf" \
  NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer8-active-missing.log 2>&1; then
  echo 'expected active Layer 8 state without prerequisites to fail doctor' >&2
  exit 1
fi
grep -q 'Layer 8 daemon active but prerequisites are missing' /tmp/nix-layer8-active-missing.log
mkdir -p "${TMP_DIR}/layer8-config"
printf 'build-users-group = nixbld\n' >"${TMP_DIR}/layer8-config/nix.conf"
printf 'nixbld:x:30000:nixbld1,nixbld2\n' >"${TMP_DIR}/layer8-config/group"
NIX_USER_CONFIG_FILE="${TMP_DIR}/layer8-config/nix.conf" \
NIX_GROUP_FILE="${TMP_DIR}/layer8-config/group" \
NIX_LAYER8_SYSTEMD_DIR="${PKG_DIR}/system.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nix-doctor" --offline --no-smoke >/tmp/nix-layer8-build-group.log || true
grep -q 'Layer 8 build-users-group exists: nixbld' /tmp/nix-layer8-build-group.log
grep -q 'Layer 8 socket unit present: .*nix-daemon.socket' /tmp/nix-layer8-build-group.log
grep -q 'Layer 8 service unit present: .*nix-daemon.service' /tmp/nix-layer8-build-group.log
grep -q 'What=/storage/.nix-root' "${PKG_DIR}/system.d/nix.mount"
grep -q 'Where=/nix' "${PKG_DIR}/system.d/nix.mount"
grep -q 'Before=nix.mount' "${PKG_DIR}/system.d/nix-storage-setup.service"

# Layer 6 activation engine smoke against temp surfaces (safe for default CI).
L6_TMP="${TMP_DIR}/layer6"
L6_BUNDLE="${PKG_DIR}/tests/fixtures/layer6-user-env"
mkdir -p "${L6_TMP}/state" "${L6_TMP}/bin" "${L6_TMP}/profile.d"
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" preflight "${L6_BUNDLE}" >/tmp/nix-layer6-preflight-smoke.log
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" activate "${L6_BUNDLE}" >/tmp/nix-layer6-activate-smoke.log
[ -x "${L6_TMP}/bin/rocknix-layer6-smoke" ]
/bin/sh -c '. "'"${L6_TMP}/profile.d/999-rocknix-layer6-smoke"'"; "'"${L6_TMP}/bin/rocknix-layer6-smoke"'"' | grep -q 'rocknix-layer6-smoke:active'
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nixctl" status | grep -q 'Layer 6 (managed user environment) status'
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-layer6-doctor-smoke.log || true
# Doctor may fail because Layer 4 is absent in default CI; assert Layer 6 checks ran.
grep -q 'Layer 6 state: active' /tmp/nix-layer6-doctor-smoke.log
printf 'user-file\n' >"${L6_TMP}/bin/rocknix-layer6-conflict"
mkdir -p "${L6_TMP}/conflict-bundle/files/bin"
printf '#!/bin/sh\necho conflict\n' >"${L6_TMP}/conflict-bundle/files/bin/rocknix-layer6-conflict"
chmod 0755 "${L6_TMP}/conflict-bundle/files/bin/rocknix-layer6-conflict"
printf 'bin|rocknix-layer6-conflict|files/bin/rocknix-layer6-conflict|0755\n' >"${L6_TMP}/conflict-bundle/manifest"
if NIX_LAYER6_STATE_DIR="${L6_TMP}/conflict-state" \
  NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" activate "${L6_TMP}/conflict-bundle" >/tmp/nix-layer6-conflict-smoke.log 2>&1; then
  echo 'expected Layer 6 conflict activation to fail' >&2
  exit 1
fi
grep -q 'target exists and is not owned by Layer 6' /tmp/nix-layer6-conflict-smoke.log
grep -q 'user-file' "${L6_TMP}/bin/rocknix-layer6-conflict"
mkdir -p "${L6_TMP}/empty-bundle"
: >"${L6_TMP}/empty-bundle/manifest"
if NIX_LAYER6_STATE_DIR="${L6_TMP}/empty-state" \
  NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" activate "${L6_TMP}/empty-bundle" >/tmp/nix-layer6-empty-smoke.log 2>&1; then
  echo 'expected Layer 6 empty activation to fail' >&2
  exit 1
fi
grep -q 'bundle manifest contains no activatable files' /tmp/nix-layer6-empty-smoke.log
NIX_LAYER6_STATE_DIR="${L6_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L6_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L6_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" deactivate >/tmp/nix-layer6-deactivate-smoke.log
[ ! -e "${L6_TMP}/bin/rocknix-layer6-smoke" ]
[ ! -e "${L6_TMP}/profile.d/999-rocknix-layer6-smoke" ]

# Layer 7 app experiment smoke against temp surfaces (safe for default CI).
L7_TMP="${TMP_DIR}/layer7"
L7_HOME="${L7_TMP}/home"
L7_BUNDLE="${PKG_DIR}/tests/fixtures/layer7-apps/browser"
mkdir -p "${L7_TMP}/state" "${L7_TMP}/bin" "${L7_TMP}/profile.d" "${L7_HOME}/.nix-profile/bin"
printf '#!/bin/sh\necho fake chromium\n' >"${L7_HOME}/.nix-profile/bin/chromium"
chmod 0755 "${L7_HOME}/.nix-profile/bin/chromium"
NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" activate "${L7_BUNDLE}" >/tmp/nix-layer7-activate-smoke.log
[ -x "${L7_TMP}/bin/rocknix-layer7-browser" ]
HOME="${L7_HOME}" \
ROCKNIX_LAYER7_BROWSER_STATE_DIR="${L7_HOME}/.local/share/nix-apps/layer7/browser" \
  "${L7_TMP}/bin/rocknix-layer7-browser" --check >/tmp/nix-layer7-launcher-check.log
grep -q 'rocknix-layer7-browser:ready' /tmp/nix-layer7-launcher-check.log
grep -q '.nix-profile/bin/chromium' /tmp/nix-layer7-launcher-check.log
if HOME="${L7_HOME}" \
  ROCKNIX_LAYER7_BROWSER_APP="missing-layer7-browser" \
  "${L7_TMP}/bin/rocknix-layer7-browser" --check >/tmp/nix-layer7-missing-check.log 2>&1; then
  echo 'expected Layer 7 missing app check to fail' >&2
  exit 1
fi
grep -q "Layer 7 app binary 'missing-layer7-browser' not found" /tmp/nix-layer7-missing-check.log
mkdir -p "${L7_TMP}/unsafe-bin"
printf '#!/bin/sh\necho unsafe chromium\n' >"${L7_TMP}/unsafe-bin/chromium"
chmod 0755 "${L7_TMP}/unsafe-bin/chromium"
if HOME="${L7_HOME}" \
  ROCKNIX_LAYER7_BROWSER_BIN_PATH="${L7_TMP}/unsafe-bin/chromium" \
  "${L7_TMP}/bin/rocknix-layer7-browser" --check >/tmp/nix-layer7-unsafe-bin.log 2>&1; then
  echo 'expected Layer 7 unsafe binary check to fail' >&2
  exit 1
fi
grep -q 'not Nix-backed' /tmp/nix-layer7-unsafe-bin.log
HOME="${L7_HOME}" \
NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nixctl" status >/tmp/nix-layer7-nixctl-status.log
grep -q 'Layer 7 (app/UI experiment) status' /tmp/nix-layer7-nixctl-status.log
grep -q 'origin:   Nix profile/store' /tmp/nix-layer7-nixctl-status.log
HOME="${L7_HOME}" \
NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-layer7-doctor-smoke.log || true
grep -q 'Layer 7 ready: launcher active with Nix-backed app binary' /tmp/nix-layer7-doctor-smoke.log
if HOME="${L7_HOME}" \
  NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
  NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
  NIX_LAYER7_APP_STATE_DIR="/storage/games-internal/roms/steam" \
  "${PKG_DIR}/scripts/nix-doctor" --offline >/tmp/nix-layer7-unsafe-state.log 2>&1; then
  echo 'expected Layer 7 unsafe state path doctor check to fail' >&2
  exit 1
fi
grep -q 'Layer 7 app state path outside allowed experiment roots' /tmp/nix-layer7-unsafe-state.log
NIX_LAYER6_STATE_DIR="${L7_TMP}/state" \
NIX_LAYER6_BIN_DIR="${L7_TMP}/bin" \
NIX_LAYER6_PROFILE_D_DIR="${L7_TMP}/profile.d" \
  "${PKG_DIR}/scripts/nix-layer-activate" deactivate >/tmp/nix-layer7-deactivate-smoke.log
[ ! -e "${L7_TMP}/bin/rocknix-layer7-browser" ]
[ ! -e "${L7_TMP}/profile.d/999-rocknix-layer7-browser" ]

# Layer 13 host module fixture smoke. This is skipped on minimal build hosts
# without Nix, but runs on developer machines and configured ROCKNIX devices.
if command -v nix >/dev/null 2>&1; then
  L13_TMP="${TMP_DIR}/layer13"
  mkdir -p "${L13_TMP}/bin" "${L13_TMP}/profile.d" "${L13_TMP}/modules"
  cp "${PKG_DIR}/tests/fixtures/modules/host-tools.nix" "${L13_TMP}/modules/host-tools.nix"
  PATH="${PKG_DIR}/scripts:${PATH}" \
  NIX_LAYER13_MODULE_KIT_DIR="${PKG_DIR}/modules" \
  NIX_LAYER13_NIX_BIN="$(command -v nix)" \
  NIX_LAYER13_STATE_DIR="${L13_TMP}/state" \
  NIX_LAYER13_HOST_WORKSPACE="${L13_TMP}/modules" \
  NIX_LAYER13_HOST_MODULE="${L13_TMP}/modules/host-tools.nix" \
  NIX_LAYER6_BIN_DIR="${L13_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L13_TMP}/profile.d" \
    "${PKG_DIR}/scripts/nixctl" module preflight >/tmp/nix-layer13-preflight.log
  PATH="${PKG_DIR}/scripts:${PATH}" \
  NIX_LAYER13_MODULE_KIT_DIR="${PKG_DIR}/modules" \
  NIX_LAYER13_NIX_BIN="$(command -v nix)" \
  NIX_LAYER13_STATE_DIR="${L13_TMP}/state" \
  NIX_LAYER13_HOST_WORKSPACE="${L13_TMP}/modules" \
  NIX_LAYER13_HOST_MODULE="${L13_TMP}/modules/host-tools.nix" \
  NIX_LAYER6_BIN_DIR="${L13_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L13_TMP}/profile.d" \
    "${PKG_DIR}/scripts/nixctl" module apply >/tmp/nix-layer13-apply.log
  "${L13_TMP}/bin/rocknix-fixture-module-hello" >/tmp/nix-layer13-wrapper.log
  grep -q 'rocknix-fixture-module-hello' /tmp/nix-layer13-wrapper.log
  [ -f "${L13_TMP}/profile.d/999-rocknix-fixture-module" ]
  PATH="${PKG_DIR}/scripts:${PATH}" \
  NIX_LAYER13_STATE_DIR="${L13_TMP}/state" \
  NIX_LAYER6_BIN_DIR="${L13_TMP}/bin" \
  NIX_LAYER6_PROFILE_D_DIR="${L13_TMP}/profile.d" \
    "${PKG_DIR}/scripts/nixctl" module deactivate >/tmp/nix-layer13-deactivate.log
  [ ! -e "${L13_TMP}/bin/rocknix-fixture-module-hello" ]

  cp "${PKG_DIR}/tests/fixtures/modules/invalid-host-path.nix" "${L13_TMP}/modules/invalid-host-path.nix"
  if PATH="${PKG_DIR}/scripts:${PATH}" \
    NIX_LAYER13_MODULE_KIT_DIR="${PKG_DIR}/modules" \
    NIX_LAYER13_NIX_BIN="$(command -v nix)" \
    NIX_LAYER13_STATE_DIR="${L13_TMP}/invalid-state" \
    NIX_LAYER13_HOST_MODULE="${L13_TMP}/modules/invalid-host-path.nix" \
    "${PKG_DIR}/scripts/nixctl" module preflight >/tmp/nix-layer13-invalid-host-path.log 2>&1; then
    echo 'expected Layer 13 invalid host path preflight to fail' >&2
    exit 1
  fi
  grep -q 'unsafe file target name' /tmp/nix-layer13-invalid-host-path.log
else
  printf 'nix-integration Layer 13 fixture smoke: skipped (nix unavailable)\n'
fi

# nspawn running detector: regression for the self-match bug.
# Spawn a process whose comm is 'sh' (not 'systemd-nspawn') and whose argv
# contains the literal substring 'systemd-nspawn' AND the configured guest
# root path. The legacy 'ps|grep [s]ystemd-nspawn|grep -F <root>' idiom
# matched this. The new exec-name + argv[0]-basename detector must not.
NSPAWN_IMPOSTOR_ROOT="${TMP_DIR}/layer10-impostor-root"
mkdir -p "${NSPAWN_IMPOSTOR_ROOT}"
NSPAWN_IMPOSTOR_STATE="${TMP_DIR}/layer10-impostor-state"
mkdir -p "${NSPAWN_IMPOSTOR_STATE}"
printf 'mode=bootable\nsource=test\nsource_path=test\nsha256=0\nguest_root=%s\n' \
  "${NSPAWN_IMPOSTOR_ROOT}" >"${NSPAWN_IMPOSTOR_STATE}/rootfs-provenance"
sh -c "sleep 30 # systemd-nspawn --boot --register=no --directory=${NSPAWN_IMPOSTOR_ROOT}" &
NSPAWN_IMPOSTOR_PID=$!
sleep 1
if ! smoke_nspawn_running "${NSPAWN_IMPOSTOR_ROOT}"; then
  : # detector correctly ignores the impostor (comm=sh, argv[0]=sh)
else
  kill "${NSPAWN_IMPOSTOR_PID}" 2>/dev/null || true
  wait "${NSPAWN_IMPOSTOR_PID}" 2>/dev/null || true
  echo 'FAIL: smoke_nspawn_running self-matched a non-nspawn impostor process' >&2
  exit 1
fi
NIX_LAYER10_NSPAWN_BIN="${FAKE_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${NSPAWN_IMPOSTOR_ROOT}" \
NIX_LAYER10_STATE_DIR="${NSPAWN_IMPOSTOR_STATE}" \
  "${PKG_DIR}/scripts/nixctl" guest status >"${TMP_DIR}/nspawn-impostor-status.log" 2>&1
if grep -q 'running:    yes' "${TMP_DIR}/nspawn-impostor-status.log"; then
  kill "${NSPAWN_IMPOSTOR_PID}" 2>/dev/null || true
  wait "${NSPAWN_IMPOSTOR_PID}" 2>/dev/null || true
  echo 'FAIL: nixctl guest status reported running=yes for an impostor' >&2
  cat "${TMP_DIR}/nspawn-impostor-status.log" >&2
  exit 1
fi
kill "${NSPAWN_IMPOSTOR_PID}" 2>/dev/null || true
wait "${NSPAWN_IMPOSTOR_PID}" 2>/dev/null || true

printf 'nix-integration runtime smoke passed\n'
else
printf '[smoke] hardware-only mode: skipping CI fixture preamble\n'
fi
# ---- end CI fixture preamble ----------------------------------------------

# ---- Layer 4 device-side smoke (opt-in) ------------------------------------
# Set LAYER4_SMOKE=1 to run the real install/use/uninstall cycle against the
# upstream Nix tarball + cache.nixos.org. This requires the device to have:
#   - /nix bind-mounted from /storage/.nix-root (Layer 3 active)
#   - aarch64
#   - network reachability to releases.nixos.org and cache.nixos.org
#   - >= 1 GB free on /storage
# Not run in default CI; intended for manual validation on hardware.

if [ "${LAYER4_SMOKE:-0}" != "1" ] && [ "${LAYER5_SMOKE:-0}" != "1" ] && [ "${LAYER6_SMOKE:-0}" != "1" ] && [ "${LAYER7_SMOKE:-0}" != "1" ] && [ "${LAYER8_SMOKE:-0}" != "1" ] && [ "${LAYER9_SMOKE:-0}" != "1" ] && [ "${LAYER10_REQUESTED}" != "1" ] && [ "${LAYER11_REQUESTED}" != "1" ] && [ "${LAYER12_REQUESTED}" != "1" ]; then
  printf 'nix-integration Layer 4 smoke: skipped (set LAYER4_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 5 smoke: skipped (set LAYER5_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 6 smoke: skipped (set LAYER6_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 7 smoke: skipped (set LAYER7_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 8 smoke: skipped (set LAYER8_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 9 smoke: skipped (set LAYER9_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 10 smoke: skipped (set LAYER10_SMOKE=proof or bootable to enable)\n'
  printf 'nix-integration Layer 11 smoke: skipped (set LAYER11_SMOKE=1 to enable)\n'
  printf 'nix-integration Layer 12 smoke: skipped (set LAYER12_SMOKE=ssh to enable)\n'
  exit 0
fi

# Device-side smokes use the real package script paths (not the fake-tarball
# harness above), so reset the per-test environment.

NIXCTL=$(resolve_smoke_bin nixctl) || exit 1
DOCTOR=$(resolve_smoke_bin nix-doctor) || exit 1
export NIX_LAYER6_ACTIVATE="${PKG_DIR}/scripts/nix-layer-activate"
L4_LOG=/tmp/nix-integration-layer4-smoke.log
rm -f "${L4_LOG}"

log() {
  printf '[layer4-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L4_LOG}"
}

if [ "${LAYER4_SMOKE:-0}" = "1" ]; then
log 'pre-flight: nixctl status reports current state'
"${NIXCTL}" status >>"${L4_LOG}" 2>&1

log 'install: nixctl install (downloads ~23MB tarball + writes /nix/store)'
start=$(date +%s)
"${NIXCTL}" install >>"${L4_LOG}" 2>&1
log "install completed in $(($(date +%s) - start))s"

log 'verify: real nix is on disk and reports the pinned version'
NIX_BIN=/nix/var/nix/profiles/default/bin/nix
[ -x "${NIX_BIN}" ] || { echo 'FAIL: real nix binary missing after install' >&2; exit 1; }
"${NIX_BIN}" --version >>"${L4_LOG}" 2>&1
"${NIX_BIN}" --version | grep -q 'nix (Nix) ' || { echo 'FAIL: nix --version output unexpected' >&2; exit 1; }

log 'verify: process tree of nix has no legacy portable/proot ancestors'
ps_out=$("${NIX_BIN}" --version 2>&1; ps -ef 2>/dev/null || true)
if printf '%s' "${ps_out}" | grep -qE 'nix-portable|proot'; then
  # Only an issue if those processes are CURRENT ancestors of nix; a parallel
  echo 'FAIL: real Nix smoke saw legacy portable/proot process state' >&2
  exit 1
fi

log 'compat-positive: nix-shell -p jq runs cleanly under real nix'
start=$(date +%s)
echo '{}' | "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' \
  shell nixpkgs#jq --command jq -c . >>"${L4_LOG}" 2>&1 \
  || { echo 'FAIL: nix shell jq smoke failed' >&2; exit 1; }
log "jq smoke completed in $(($(date +%s) - start))s"

log 'doctor: nix-doctor passes with Layer 4 lines present'
"${DOCTOR}" --offline >>"${L4_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed after Layer 4 install' >&2; exit 1; }
grep -q 'Layer 4 detected' "${L4_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 4 presence' >&2; exit 1; }

log 'uninstall: nixctl uninstall --yes returns to Layer 3 substrate'
"${NIXCTL}" uninstall --yes >>"${L4_LOG}" 2>&1
[ ! -x "${NIX_BIN}" ] || { echo 'FAIL: nix binary still present after uninstall' >&2; exit 1; }
[ ! -e "${HOME:-/storage}/.nix-profile" ] || { echo 'FAIL: ~/.nix-profile still present after uninstall' >&2; exit 1; }

log 'idempotency: second uninstall is a clean no-op'
"${NIXCTL}" uninstall --yes 2>&1 | grep -q 'Nothing to uninstall' \
  || { echo 'FAIL: idempotent uninstall did not report no-op' >&2; exit 1; }

log 'verify: legacy portable wrappers are absent after Layer 4 install'
[ ! -e /storage/bin/nix-portable ] || { echo 'FAIL: legacy /storage/bin/nix-portable survived Layer 4 install' >&2; exit 1; }
[ ! -e /storage/bin/nix ] || { echo 'FAIL: legacy /storage/bin/nix survived Layer 4 install' >&2; exit 1; }

printf 'nix-integration Layer 4 smoke passed\n'
printf 'log: %s\n' "${L4_LOG}"
fi

# ---- Layer 5 device-side smoke (opt-in) ------------------------------------
# Set LAYER5_SMOKE=1 to validate persistent Nix profiles for CLI tools on
# hardware. Requires Layer 4 real Nix to already be installed. The default
# package is nixpkgs#hello because it is small and low-conflict.
if [ "${LAYER5_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER6_SMOKE:-0}" != "1" ] && [ "${LAYER7_SMOKE:-0}" != "1" ] && [ "${LAYER8_SMOKE:-0}" != "1" ] && [ "${LAYER9_SMOKE:-0}" != "1" ] && [ "${LAYER10_REQUESTED}" != "1" ] && [ "${LAYER11_REQUESTED}" != "1" ] && [ "${LAYER12_REQUESTED}" != "1" ]; then
    exit 0
  fi
else

L5_LOG=/tmp/nix-integration-layer5-smoke.log
L5_PACKAGE="${LAYER5_SMOKE_PACKAGE:-nixpkgs#hello}"
L5_NAME="${LAYER5_SMOKE_NAME:-hello}"
L5_BIN="${LAYER5_SMOKE_BIN:-hello}"
rm -f "${L5_LOG}"

log5() {
  printf '[layer5-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L5_LOG}"
}

NIX_BIN=/nix/var/nix/profiles/default/bin/nix
[ -x "${NIX_BIN}" ] || { echo 'FAIL: Layer 5 smoke requires Layer 4 real Nix' >&2; exit 1; }
[ -d /nix ] || { echo 'FAIL: /nix missing' >&2; exit 1; }
awk '$2 == "/nix" {found=1} END {exit !found}' /proc/mounts 2>/dev/null \
  || { echo 'FAIL: /nix is not mounted' >&2; exit 1; }

log5 "pre-flight: inspect existing profile"
preexisting=0
if "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' profile list 2>/tmp/layer5-profile-list.err | grep -q "Name:[[:space:]]*${L5_NAME}"; then
  preexisting=1
  log5 "${L5_NAME} is already present; smoke will not remove it"
fi

if [ "${LAYER5_REBOOT_VERIFY:-}" = "verify" ]; then
  log5 'reboot verify: checking existing profile binary after reboot'
  . /etc/profile
  command -v "${L5_BIN}" >>"${L5_LOG}" 2>&1 \
    || { echo "FAIL: ${L5_BIN} not on PATH after reboot" >&2; exit 1; }
  "${L5_BIN}" --version >>"${L5_LOG}" 2>&1 || "${L5_BIN}" >>"${L5_LOG}" 2>&1 \
    || { echo "FAIL: ${L5_BIN} did not run after reboot" >&2; exit 1; }
  printf 'nix-integration Layer 5 reboot smoke passed\n'
  printf 'log: %s\n' "${L5_LOG}"
  exit 0
fi

log5 "install: nix profile install ${L5_PACKAGE}"
"${NIX_BIN}" --extra-experimental-features 'nix-command flakes' profile install "${L5_PACKAGE}" >>"${L5_LOG}" 2>&1 \
  || { echo "FAIL: nix profile install ${L5_PACKAGE} failed" >&2; exit 1; }

log5 'verify: binary exists via profile link and fresh profile-sourced shell'
[ -x "${HOME:-/storage}/.nix-profile/bin/${L5_BIN}" ] \
  || { echo "FAIL: profile binary missing: ${HOME:-/storage}/.nix-profile/bin/${L5_BIN}" >&2; exit 1; }
/bin/sh -c '. /etc/profile; command -v "'"${L5_BIN}"'"; "'"${L5_BIN}"'"' >>"${L5_LOG}" 2>&1 \
  || { echo "FAIL: ${L5_BIN} did not run from a fresh profile-sourced shell" >&2; exit 1; }

log5 'diagnostics: nixctl status and nix-doctor report Layer 5 state'
"${NIXCTL}" status >>"${L5_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 5 smoke' >&2; exit 1; }
grep -q 'Layer 5 (persistent profile) status' "${L5_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 5 section' >&2; exit 1; }
"${DOCTOR}" --offline >>"${L5_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 5 smoke' >&2; exit 1; }
grep -q 'Layer 5 profile link' "${L5_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 5 profile state' >&2; exit 1; }

if [ "${LAYER5_REBOOT_VERIFY:-}" = "prepare" ]; then
  log5 "leaving ${L5_NAME} installed for reboot verification"
  printf 'nix-integration Layer 5 smoke prepared for reboot verification\n'
  printf 'After reboot run: LAYER5_SMOKE=1 LAYER5_REBOOT_VERIFY=verify %s\n' "$0"
  printf 'log: %s\n' "${L5_LOG}"
  exit 0
fi

if [ "${preexisting}" -eq 0 ]; then
  log5 "cleanup: nix profile remove ${L5_NAME}"
  "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' profile remove "${L5_NAME}" >>"${L5_LOG}" 2>&1 \
    || { echo "FAIL: nix profile remove ${L5_NAME} failed" >&2; exit 1; }
else
  log5 "cleanup: leaving pre-existing ${L5_NAME} profile entry intact"
fi

printf 'nix-integration Layer 5 smoke passed\n'
printf 'log: %s\n' "${L5_LOG}"
fi

# ---- Layer 6 device-side smoke (opt-in) ------------------------------------
# Set LAYER6_SMOKE=1 to validate managed storage-local user-environment
# activation on hardware. Requires Layer 4/5 shell integration to be healthy.
if [ "${LAYER6_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER7_SMOKE:-0}" != "1" ] && [ "${LAYER8_SMOKE:-0}" != "1" ] && [ "${LAYER9_SMOKE:-0}" != "1" ] && [ "${LAYER10_REQUESTED}" != "1" ] && [ "${LAYER11_REQUESTED}" != "1" ] && [ "${LAYER12_REQUESTED}" != "1" ]; then
    exit 0
  fi
else

L6_LOG=/tmp/nix-integration-layer6-smoke.log
L6_CACHE=/storage/.cache/nix-layer6-smoke-bundle
L6_BUNDLE="${L6_CACHE}/layer6-user-env"
rm -f "${L6_LOG}"
mkdir -p "${L6_CACHE}"
rm -rf "${L6_BUNDLE}"
cp -R "${PKG_DIR}/tests/fixtures/layer6-user-env" "${L6_BUNDLE}"

log6() {
  printf '[layer6-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L6_LOG}"
}

NIX_BIN=/nix/var/nix/profiles/default/bin/nix
[ -x "${NIX_BIN}" ] || { echo 'FAIL: Layer 6 smoke requires Layer 4 real Nix' >&2; exit 1; }
[ -d "${HOME:-/storage}/.nix-profile/bin" ] || { echo 'FAIL: Layer 6 smoke requires Layer 5 profile bin' >&2; exit 1; }
[ -w /storage ] || { echo 'FAIL: /storage is not writable' >&2; exit 1; }

if [ "${LAYER6_REBOOT_VERIFY:-}" = "verify" ]; then
  log6 'reboot verify: checking existing Layer 6 managed files after reboot'
  . /etc/profile
  command -v rocknix-layer6-smoke >>"${L6_LOG}" 2>&1 \
    || { echo 'FAIL: rocknix-layer6-smoke not on PATH after reboot' >&2; exit 1; }
  rocknix-layer6-smoke >>"${L6_LOG}" 2>&1 \
    || { echo 'FAIL: rocknix-layer6-smoke did not run after reboot' >&2; exit 1; }
  "${NIXCTL}" status >>"${L6_LOG}" 2>&1 \
    || { echo 'FAIL: nixctl status failed during Layer 6 reboot verify' >&2; exit 1; }
  "${DOCTOR}" --offline >>"${L6_LOG}" 2>&1 \
    || { echo 'FAIL: nix-doctor failed during Layer 6 reboot verify' >&2; exit 1; }
  if [ "${LAYER6_KEEP:-0}" != "1" ]; then
    "${NIXCTL}" user-env deactivate >>"${L6_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 6 deactivate failed after reboot verify' >&2; exit 1; }
  fi
  printf 'nix-integration Layer 6 reboot smoke passed\n'
  printf 'log: %s\n' "${L6_LOG}"
  exit 0
fi

log6 'pre-flight: Layer 6 activation bundle'
"${NIXCTL}" user-env preflight "${L6_BUNDLE}" >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 6 preflight failed' >&2; exit 1; }

log6 'activate: Layer 6 smoke bundle'
"${NIXCTL}" user-env activate "${L6_BUNDLE}" >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 6 activation failed' >&2; exit 1; }

log6 'verify: wrapper and profile snippet work in a fresh shell'
/bin/sh -c '. /etc/profile; command -v rocknix-layer6-smoke; rocknix-layer6-smoke' >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 6 managed wrapper did not run from a fresh shell' >&2; exit 1; }

grep -q 'rocknix-layer6-smoke:active' "${L6_LOG}" \
  || { echo 'FAIL: Layer 6 profile snippet did not set smoke environment' >&2; exit 1; }

log6 'diagnostics: nixctl status and nix-doctor report Layer 6 state'
"${NIXCTL}" status >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 6 smoke' >&2; exit 1; }
grep -q 'Layer 6 (managed user environment) status' "${L6_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 6 section' >&2; exit 1; }
"${DOCTOR}" --offline >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 6 smoke' >&2; exit 1; }
grep -q 'Layer 6 state: active' "${L6_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 6 active state' >&2; exit 1; }

log6 'conflict: non-owned target is refused and preserved'
printf 'user-owned\n' >/storage/bin/rocknix-layer6-conflict
mkdir -p /storage/.cache/nix-layer6-conflict/files/bin
printf '#!/bin/sh\necho conflict\n' >/storage/.cache/nix-layer6-conflict/files/bin/rocknix-layer6-conflict
chmod 0755 /storage/.cache/nix-layer6-conflict/files/bin/rocknix-layer6-conflict
printf 'bin|rocknix-layer6-conflict|files/bin/rocknix-layer6-conflict|0755\n' >/storage/.cache/nix-layer6-conflict/manifest
if "${NIXCTL}" user-env activate /storage/.cache/nix-layer6-conflict >>"${L6_LOG}" 2>&1; then
  echo 'FAIL: Layer 6 conflict activation unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'user-owned' /storage/bin/rocknix-layer6-conflict \
  || { echo 'FAIL: Layer 6 conflict target was modified' >&2; exit 1; }
rm -f /storage/bin/rocknix-layer6-conflict
rm -rf /storage/.cache/nix-layer6-conflict

if [ "${LAYER6_REBOOT_VERIFY:-}" = "prepare" ]; then
  log6 'leaving Layer 6 smoke bundle active for reboot verification'
  printf 'nix-integration Layer 6 smoke prepared for reboot verification\n'
  printf 'After reboot run: LAYER6_SMOKE=1 LAYER6_REBOOT_VERIFY=verify %s\n' "$0"
  printf 'log: %s\n' "${L6_LOG}"
  exit 0
fi

log6 'cleanup: deactivate Layer 6 smoke bundle'
"${NIXCTL}" user-env deactivate >>"${L6_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 6 deactivate failed' >&2; exit 1; }
[ ! -e /storage/bin/rocknix-layer6-smoke ] \
  || { echo 'FAIL: Layer 6 wrapper still present after deactivate' >&2; exit 1; }
[ ! -e /storage/.config/profile.d/999-rocknix-layer6-smoke ] \
  || { echo 'FAIL: Layer 6 profile snippet still present after deactivate' >&2; exit 1; }

printf 'nix-integration Layer 6 smoke passed\n'
printf 'log: %s\n' "${L6_LOG}"
fi

# ---- Layer 7 device-side smoke (opt-in) ------------------------------------
# Set LAYER7_SMOKE=1 to validate the first Nix-managed app launcher on
# hardware. This smoke intentionally checks readiness and activation; actual
# visual confirmation remains operator-observed because CI cannot inspect the
# handheld screen.
if [ "${LAYER7_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER8_SMOKE:-0}" != "1" ] && [ "${LAYER9_SMOKE:-0}" != "1" ] && [ "${LAYER10_REQUESTED}" != "1" ] && [ "${LAYER11_REQUESTED}" != "1" ] && [ "${LAYER12_REQUESTED}" != "1" ]; then
    exit 0
  fi
else

L7_LOG=/tmp/nix-integration-layer7-smoke.log
L7_CACHE=/storage/.cache/nix-layer7-browser-bundle
L7_BUNDLE="${L7_CACHE}/browser"
L7_BIN="${LAYER7_SMOKE_BIN:-chromium}"
L7_LAUNCHER=/storage/bin/rocknix-layer7-browser
rm -f "${L7_LOG}"
mkdir -p "${L7_CACHE}"
rm -rf "${L7_BUNDLE}"
cp -R "${PKG_DIR}/tests/fixtures/layer7-apps/browser" "${L7_BUNDLE}"

log7() {
  printf '[layer7-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L7_LOG}"
}

[ -d "${HOME:-/storage}/.nix-profile/bin" ] || { echo 'FAIL: Layer 7 smoke requires Layer 5 profile bin' >&2; exit 1; }
[ -x "${HOME:-/storage}/.nix-profile/bin/${L7_BIN}" ] || { echo "FAIL: Layer 7 smoke requires ${L7_BIN} in the Nix user profile" >&2; exit 1; }
[ -w /storage ] || { echo 'FAIL: /storage is not writable' >&2; exit 1; }

if [ "${LAYER7_REBOOT_VERIFY:-}" != "verify" ] && [ "${LAYER7_ALLOW_ACTIVE_LAYER6:-0}" != "1" ]; then
  existing_state=$(${NIX_LAYER6_ACTIVATE} status 2>/dev/null | awk '/state:/ {print $2; exit}' || echo absent)
  if [ "${existing_state}" = "active" ]; then
    echo 'FAIL: Layer 7 smoke requires no pre-existing active Layer 6 bundle; deactivate it first or set LAYER7_ALLOW_ACTIVE_LAYER6=1' >&2
    exit 1
  fi
fi

if [ "${LAYER7_REBOOT_VERIFY:-}" = "verify" ]; then
  log7 'reboot verify: checking existing Layer 7 launcher after reboot'
  . /etc/profile
  [ -x "${L7_LAUNCHER}" ] || { echo 'FAIL: Layer 7 launcher missing after reboot' >&2; exit 1; }
  ROCKNIX_LAYER7_BROWSER_APP="${L7_BIN}" "${L7_LAUNCHER}" --check >>"${L7_LOG}" 2>&1 \
    || { echo 'FAIL: Layer 7 launcher readiness failed after reboot' >&2; exit 1; }
  "${NIXCTL}" status >>"${L7_LOG}" 2>&1 \
    || { echo 'FAIL: nixctl status failed during Layer 7 reboot verify' >&2; exit 1; }
  "${DOCTOR}" --offline >>"${L7_LOG}" 2>&1 \
    || { echo 'FAIL: nix-doctor failed during Layer 7 reboot verify' >&2; exit 1; }
  if [ "${LAYER7_KEEP:-0}" != "1" ]; then
    "${NIXCTL}" user-env deactivate >>"${L7_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 7 deactivate failed after reboot verify' >&2; exit 1; }
  fi
  printf 'nix-integration Layer 7 reboot smoke passed\n'
  printf 'log: %s\n' "${L7_LOG}"
  exit 0
fi

log7 'pre-flight: Layer 7 browser activation bundle'
"${NIXCTL}" user-env preflight "${L7_BUNDLE}" >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 7 preflight failed' >&2; exit 1; }

log7 'activate: Layer 7 browser launcher bundle'
"${NIXCTL}" user-env activate "${L7_BUNDLE}" >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 7 activation failed' >&2; exit 1; }

log7 'verify: launcher readiness uses Nix profile binary'
ROCKNIX_LAYER7_BROWSER_APP="${L7_BIN}" "${L7_LAUNCHER}" --check >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 7 launcher readiness check failed' >&2; exit 1; }
grep -q 'rocknix-layer7-browser:ready' "${L7_LOG}" \
  || { echo 'FAIL: Layer 7 launcher did not report ready' >&2; exit 1; }

log7 'diagnostics: nixctl status and nix-doctor report Layer 7 state'
NIX_LAYER7_APP_BIN="${L7_BIN}" "${NIXCTL}" status >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 7 smoke' >&2; exit 1; }
grep -q 'Layer 7 (app/UI experiment) status' "${L7_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 7 section' >&2; exit 1; }
NIX_LAYER7_APP_BIN="${L7_BIN}" "${DOCTOR}" --offline >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 7 smoke' >&2; exit 1; }
grep -q 'Layer 7 ready' "${L7_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 7 readiness' >&2; exit 1; }

if [ "${LAYER7_REBOOT_VERIFY:-}" = "prepare" ]; then
  log7 'leaving Layer 7 launcher active for reboot verification'
  printf 'nix-integration Layer 7 smoke prepared for reboot verification\n'
  printf 'After reboot run: LAYER7_SMOKE=1 LAYER7_REBOOT_VERIFY=verify %s\n' "$0"
  printf 'log: %s\n' "${L7_LOG}"
  exit 0
fi

log7 'cleanup: deactivate Layer 7 launcher bundle'
"${NIXCTL}" user-env deactivate >>"${L7_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 7 deactivate failed' >&2; exit 1; }
[ ! -e /storage/bin/rocknix-layer7-browser ] \
  || { echo 'FAIL: Layer 7 launcher still present after deactivate' >&2; exit 1; }
[ ! -e /storage/.config/profile.d/999-rocknix-layer7-browser ] \
  || { echo 'FAIL: Layer 7 profile snippet still present after deactivate' >&2; exit 1; }

printf 'nix-integration Layer 7 smoke passed\n'
printf 'log: %s\n' "${L7_LOG}"
fi

# ---- Layer 8 device-side smoke (opt-in) ------------------------------------
# Set LAYER8_SMOKE=1 to validate experimental nix-daemon mode on hardware.
# Requires Layer 4 real Nix, image-time daemon build identities/config, and
# opt-in daemon units. Default CI never starts systemd units.
if [ "${LAYER8_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER9_SMOKE:-0}" != "1" ] && [ "${LAYER10_REQUESTED}" != "1" ] && [ "${LAYER11_REQUESTED}" != "1" ] && [ "${LAYER12_REQUESTED}" != "1" ]; then
    exit 0
  fi
else

L8_LOG=/tmp/nix-integration-layer8-smoke.log
rm -f "${L8_LOG}"

log8() {
  printf '[layer8-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L8_LOG}"
}

NIX_BIN=/nix/var/nix/profiles/default/bin/nix
[ -x "${NIX_BIN}" ] || { echo 'FAIL: Layer 8 smoke requires Layer 4 real Nix' >&2; exit 1; }
[ -x /nix/var/nix/profiles/default/bin/nix-daemon ] || { echo 'FAIL: Layer 8 smoke requires nix-daemon in the Nix default profile' >&2; exit 1; }
awk '$2 == "/nix" {found=1} END {exit !found}' /proc/mounts 2>/dev/null \
  || { echo 'FAIL: /nix is not mounted' >&2; exit 1; }

if [ "${LAYER8_REBOOT_VERIFY:-}" = "verify" ]; then
  log8 'reboot verify: checking daemon mode after reboot'
  "${NIXCTL}" daemon status >>"${L8_LOG}" 2>&1 \
    || { echo 'FAIL: nixctl daemon status failed during Layer 8 reboot verify' >&2; exit 1; }
  NIX_REMOTE=daemon "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' store ping >>"${L8_LOG}" 2>&1 \
    || { echo 'FAIL: daemon store ping failed after reboot' >&2; exit 1; }
  "${DOCTOR}" --offline >>"${L8_LOG}" 2>&1 \
    || { echo 'FAIL: nix-doctor failed during Layer 8 reboot verify' >&2; exit 1; }
  if [ "${LAYER8_KEEP:-0}" != "1" ]; then
    "${NIXCTL}" daemon disable >>"${L8_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 8 daemon disable failed after reboot verify' >&2; exit 1; }
  fi
  printf 'nix-integration Layer 8 reboot smoke passed\n'
  printf 'log: %s\n' "${L8_LOG}"
  exit 0
fi

log8 'pre-flight: Layer 8 daemon prerequisites'
"${NIXCTL}" daemon preflight >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 8 daemon preflight failed' >&2; exit 1; }

log8 'enable: Layer 8 daemon socket'
"${NIXCTL}" daemon enable >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 8 daemon enable failed' >&2; exit 1; }

log8 'verify: client talks to daemon'
NIX_REMOTE=daemon "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' store ping >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: daemon store ping failed' >&2; exit 1; }

log8 'verify: trivial cached package through daemon'
NIX_REMOTE=daemon "${NIX_BIN}" --extra-experimental-features 'nix-command flakes' run nixpkgs#hello >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: daemon nix run hello smoke failed' >&2; exit 1; }

grep -q 'Hello, world!' "${L8_LOG}" \
  || { echo 'FAIL: daemon hello smoke did not print expected output' >&2; exit 1; }

log8 'diagnostics: nixctl status and nix-doctor report Layer 8 state'
"${NIXCTL}" status >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 8 smoke' >&2; exit 1; }
grep -q 'Layer 8 (experimental daemon) status' "${L8_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 8 section' >&2; exit 1; }
"${DOCTOR}" --offline >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 8 smoke' >&2; exit 1; }
grep -q 'Layer 8 daemon state' "${L8_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 8 state' >&2; exit 1; }

if [ "${LAYER8_REBOOT_VERIFY:-}" = "prepare" ]; then
  log8 'leaving Layer 8 daemon active for reboot verification'
  printf 'nix-integration Layer 8 smoke prepared for reboot verification\n'
  printf 'After reboot run: LAYER8_SMOKE=1 LAYER8_REBOOT_VERIFY=verify %s\n' "$0"
  printf 'log: %s\n' "${L8_LOG}"
  exit 0
fi

log8 'cleanup: disable Layer 8 daemon mode'
"${NIXCTL}" daemon disable >>"${L8_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 8 daemon disable failed' >&2; exit 1; }

printf 'nix-integration Layer 8 smoke passed\n'
printf 'log: %s\n' "${L8_LOG}"
fi

# ---- Layer 9 device-side smoke (opt-in) ------------------------------------
# Set LAYER9_SMOKE=1 to validate a manually started systemd-nspawn guest proof
# on hardware. Requires a Layer 9-enabled image and a pre-staged guest rootfs.
# The smoke does not download or generate the rootfs and never enables a unit.
if [ "${LAYER9_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER10_REQUESTED}" != "1" ] && [ "${LAYER11_REQUESTED}" != "1" ] && [ "${LAYER12_REQUESTED}" != "1" ]; then
    exit 0
  fi
else

L9_LOG=/tmp/nix-integration-layer9-smoke.log
L9_NSPAWN="${LAYER9_NSPAWN_BIN:-${NIX_LAYER9_NSPAWN_BIN:-/usr/bin/systemd-nspawn}}"
L9_ROOT="${LAYER9_GUEST_ROOT:-${NIX_LAYER9_GUEST_ROOT:-/storage/machines/rocknix-guest}}"
L9_TIMEOUT="${LAYER9_TIMEOUT:-30}"
L9_PROOF_COMMAND="${LAYER9_PROOF_COMMAND:-printf 'layer9-guest-proof\\n'; if command -v nix >/dev/null 2>&1; then nix --version; fi}"
rm -f "${L9_LOG}"

log9() {
  printf '[layer9-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L9_LOG}"
}

layer9_guest_running() {
  smoke_nspawn_running "${L9_ROOT}"
}

layer9_no_enabled_unit() {
  unit_autostarts systemd-nspawn@rocknix-guest.service && return 1
  return 0
}

[ -x "${L9_NSPAWN}" ] || { echo "FAIL: Layer 9 smoke requires executable systemd-nspawn at ${L9_NSPAWN}" >&2; exit 1; }
[ -d "${L9_ROOT}" ] || { echo "FAIL: Layer 9 smoke requires staged guest rootfs at ${L9_ROOT}" >&2; exit 1; }
[ -d "${L9_ROOT}/etc" ] || [ -d "${L9_ROOT}/usr" ] || [ -d "${L9_ROOT}/nix" ] \
  || { echo "FAIL: Layer 9 guest root does not look proof-ready: ${L9_ROOT}" >&2; exit 1; }
command -v timeout >/dev/null 2>&1 \
  || { echo 'FAIL: Layer 9 smoke requires timeout to keep the guest proof bounded' >&2; exit 1; }
layer9_no_enabled_unit \
  || { echo 'FAIL: Layer 9 found an enabled systemd-nspawn guest unit before smoke' >&2; exit 1; }

log9 'pre-flight: Layer 9 nspawn diagnostics'
NIX_LAYER9_NSPAWN_BIN="${L9_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${L9_ROOT}" \
  "${NIXCTL}" status >>"${L9_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed during Layer 9 preflight' >&2; exit 1; }
grep -q 'Layer 9 (nspawn guest proof) status' "${L9_LOG}" \
  || { echo 'FAIL: nixctl status did not report Layer 9 section' >&2; exit 1; }
NIX_LAYER9_NSPAWN_BIN="${L9_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${L9_ROOT}" \
  "${DOCTOR}" --offline >>"${L9_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 9 preflight' >&2; exit 1; }
grep -q 'Layer 9 nspawn guest state' "${L9_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 9 state' >&2; exit 1; }

log9 'start: bounded systemd-nspawn guest proof command'
timeout "${L9_TIMEOUT}" "${L9_NSPAWN}" --quiet --register=no --directory="${L9_ROOT}" /bin/sh -lc "${L9_PROOF_COMMAND}" >>"${L9_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 9 nspawn proof command failed' >&2; layer9_guest_running && pkill -f "systemd-nspawn.*${L9_ROOT}" 2>/dev/null || true; exit 1; }
grep -q 'layer9-guest-proof' "${L9_LOG}" \
  || { echo 'FAIL: Layer 9 guest proof marker missing' >&2; exit 1; }

log9 'cleanup: verify no guest process or enabled guest unit remains'
if layer9_guest_running; then
  pkill -f "systemd-nspawn.*${L9_ROOT}" 2>/dev/null || true
  sleep 1
fi
layer9_guest_running \
  && { echo 'FAIL: Layer 9 guest process still running after proof' >&2; exit 1; }
layer9_no_enabled_unit \
  || { echo 'FAIL: Layer 9 found enabled systemd-nspawn guest unit after smoke' >&2; exit 1; }

log9 'diagnostics: post-proof host Layer 9 status remains readable'
NIX_LAYER9_NSPAWN_BIN="${L9_NSPAWN}" \
NIX_LAYER9_GUEST_ROOT="${L9_ROOT}" \
  "${NIXCTL}" status >>"${L9_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl status failed after Layer 9 proof' >&2; exit 1; }

printf 'nix-integration Layer 9 smoke passed\n'
printf 'log: %s\n' "${L9_LOG}"
fi

# ---- Layer 10 device-side smoke (opt-in) -----------------------------------
# Set LAYER10_SMOKE=proof to validate proof-mode run/shell operations on
# hardware. Set LAYER10_SMOKE=bootable to validate manual bootable guest
# start/stop with resource-bounded disabled unit generation. Default CI never
# starts a real nspawn guest.
if [ "${LAYER10_SMOKE:-0}" != "1" ] && [ "${LAYER10_SMOKE:-0}" != "proof" ] && [ "${LAYER10_SMOKE:-0}" != "bootable" ]; then
  if [ "${LAYER11_REQUESTED}" != "1" ] && [ "${LAYER12_REQUESTED}" != "1" ]; then
    exit 0
  fi
else

L10_LOG=/tmp/nix-integration-layer10-smoke.log
L10_MODE="${LAYER10_SMOKE:-proof}"
[ "${L10_MODE}" = "1" ] && L10_MODE=proof
L10_NSPAWN="${LAYER10_NSPAWN_BIN:-${NIX_LAYER10_NSPAWN_BIN:-/usr/bin/systemd-nspawn}}"
L10_ROOT="${LAYER10_GUEST_ROOT:-${NIX_LAYER10_GUEST_ROOT:-/storage/machines/rocknix-guest}}"
L10_STATE="${LAYER10_STATE_DIR:-${NIX_LAYER10_STATE_DIR:-/storage/.config/nix-integration/layer10}}"
L10_PROVENANCE="${L10_STATE}/rootfs-provenance"
L10_TIMEOUT="${LAYER10_TIMEOUT:-45}"
L10_PROOF_COMMAND="${LAYER10_PROOF_COMMAND:-printf 'layer10-guest-proof\\n'; if command -v nix >/dev/null 2>&1; then nix --version; fi}"
rm -f "${L10_LOG}"

log10() {
  printf '[layer10-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L10_LOG}"
}

layer10_guest_running() {
  smoke_nspawn_running "${L10_ROOT}"
}

layer10_no_enabled_unit() {
  unit_autostarts rocknix-guest.service && return 1
  unit_autostarts systemd-nspawn@rocknix-guest.service && return 1
  return 0
}

[ -x "${L10_NSPAWN}" ] || { echo "FAIL: Layer 10 smoke requires executable systemd-nspawn at ${L10_NSPAWN}" >&2; exit 1; }
[ -d "${L10_ROOT}" ] || { echo "FAIL: Layer 10 smoke requires staged guest rootfs at ${L10_ROOT}" >&2; exit 1; }
layer10_no_enabled_unit \
  || { echo 'FAIL: Layer 10 found an enabled guest unit before smoke' >&2; exit 1; }

log10 'pre-flight: Layer 10 guest diagnostics'
NIX_LAYER10_NSPAWN_BIN="${L10_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${L10_ROOT}" \
NIX_LAYER10_STATE_DIR="${L10_STATE}" \
  "${NIXCTL}" guest status >>"${L10_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl guest status failed during Layer 10 preflight' >&2; exit 1; }
grep -q 'Layer 10 (managed nspawn guest operations) status' "${L10_LOG}" \
  || { echo 'FAIL: nixctl guest status did not report Layer 10 section' >&2; exit 1; }
NIX_LAYER10_NSPAWN_BIN="${L10_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${L10_ROOT}" \
NIX_LAYER10_STATE_DIR="${L10_STATE}" \
  "${DOCTOR}" --offline >>"${L10_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed during Layer 10 preflight' >&2; exit 1; }
grep -q 'Layer 10 guest lifecycle state' "${L10_LOG}" \
  || { echo 'FAIL: nix-doctor did not report Layer 10 lifecycle state' >&2; exit 1; }

case "${L10_MODE}" in
  proof)
    log10 'proof: bounded nixctl guest run command'
    NIX_LAYER10_NSPAWN_BIN="${L10_NSPAWN}" \
    NIX_LAYER10_GUEST_ROOT="${L10_ROOT}" \
    NIX_LAYER10_STATE_DIR="${L10_STATE}" \
    NIX_LAYER10_TIMEOUT="${L10_TIMEOUT}" \
    NIX_LAYER10_LOG="${L10_LOG}.guest" \
      "${NIXCTL}" guest run /bin/sh -lc "${L10_PROOF_COMMAND}" >>"${L10_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 10 proof-mode guest run failed' >&2; layer10_guest_running && pkill -f "systemd-nspawn.*${L10_ROOT}" 2>/dev/null || true; exit 1; }
    grep -q 'layer10-guest-proof' "${L10_LOG}" \
      || { echo 'FAIL: Layer 10 guest proof marker missing' >&2; exit 1; }
    ;;
  bootable)
    log10 'pre-flight: bootable provenance'
    [ -f "${L10_PROVENANCE}" ] || { echo "FAIL: Layer 10 bootable smoke requires provenance metadata at ${L10_PROVENANCE}" >&2; exit 1; }
    grep -q '^sha256=' "${L10_PROVENANCE}" \
      || { echo "FAIL: Layer 10 bootable provenance missing sha256: ${L10_PROVENANCE}" >&2; exit 1; }
    log10 "provenance: $(grep '^sha256=' "${L10_PROVENANCE}" | head -1)"
    log10 'start: manual bootable guest start'
    NIX_LAYER10_NSPAWN_BIN="${L10_NSPAWN}" \
    NIX_LAYER10_GUEST_ROOT="${L10_ROOT}" \
    NIX_LAYER10_STATE_DIR="${L10_STATE}" \
      "${NIXCTL}" guest start >>"${L10_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 10 bootable guest start failed' >&2; exit 1; }
    NIX_LAYER10_NSPAWN_BIN="${L10_NSPAWN}" \
    NIX_LAYER10_GUEST_ROOT="${L10_ROOT}" \
    NIX_LAYER10_STATE_DIR="${L10_STATE}" \
      "${NIXCTL}" guest status >>"${L10_LOG}" 2>&1 \
      || { echo 'FAIL: nixctl guest status failed after Layer 10 start' >&2; exit 1; }
    grep -q 'state:      running' "${L10_LOG}" \
      || { echo 'FAIL: Layer 10 status did not report running after start' >&2; exit 1; }
    log10 'stop: manual bootable guest stop'
    NIX_LAYER10_GUEST_ROOT="${L10_ROOT}" \
    NIX_LAYER10_STATE_DIR="${L10_STATE}" \
      "${NIXCTL}" guest stop >>"${L10_LOG}" 2>&1 \
      || { echo 'FAIL: Layer 10 bootable guest stop failed' >&2; exit 1; }
    ;;
  *)
    echo "FAIL: unknown LAYER10_SMOKE mode: ${L10_MODE}" >&2
    exit 1
    ;;
esac

log10 'cleanup: verify no guest process or enabled guest unit remains'
if layer10_guest_running; then
  pkill -f "systemd-nspawn.*${L10_ROOT}" 2>/dev/null || true
  sleep 1
fi
layer10_guest_running \
  && { echo 'FAIL: Layer 10 guest process still running after smoke' >&2; exit 1; }
layer10_no_enabled_unit \
  || { echo 'FAIL: Layer 10 found enabled guest unit after smoke' >&2; exit 1; }

log10 'diagnostics: post-smoke host Layer 10 status remains readable'
NIX_LAYER10_NSPAWN_BIN="${L10_NSPAWN}" \
NIX_LAYER10_GUEST_ROOT="${L10_ROOT}" \
NIX_LAYER10_STATE_DIR="${L10_STATE}" \
  "${NIXCTL}" guest status >>"${L10_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl guest status failed after Layer 10 smoke' >&2; exit 1; }

printf 'nix-integration Layer 10 smoke passed (%s)\n' "${L10_MODE}"
printf 'log: %s\n' "${L10_LOG}"
fi

# ---- Layer 11 device-side smoke (opt-in) -----------------------------------
# Set LAYER11_SMOKE=1 to validate one-shot host -> guest bridge execution on
# hardware. Requires Layer 10 proof-mode readiness and removes the temporary
# bridge before exiting.
if [ "${LAYER11_SMOKE:-0}" != "1" ]; then
  if [ "${LAYER12_REQUESTED}" != "1" ]; then
    exit 0
  fi
else

L11_LOG=/tmp/nix-integration-layer11-smoke.log
L11_NAME="${LAYER11_BRIDGE_NAME:-layer11-nix-version}"
L11_ROOT="${LAYER11_GUEST_ROOT:-${NIX_LAYER10_GUEST_ROOT:-/storage/machines/rocknix-guest}}"
L11_STATE="${LAYER11_STATE_DIR:-${NIX_LAYER11_STATE_DIR:-/storage/.config/nix-integration/layer11}}"
L11_BIN_DIR="${LAYER11_BIN_DIR:-${NIX_LAYER11_BIN_DIR:-/storage/bin}}"
rm -f "${L11_LOG}"

log11() {
  printf '[layer11-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L11_LOG}"
}

layer11_guest_running() {
  smoke_nspawn_running "${L11_ROOT}"
}

log11 'pre-flight: Layer 11 bridge diagnostics'
NIX_LAYER10_GUEST_ROOT="${L11_ROOT}" \
NIX_LAYER11_STATE_DIR="${L11_STATE}" \
NIX_LAYER11_BIN_DIR="${L11_BIN_DIR}" \
  "${NIXCTL}" bridge status >>"${L11_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl bridge status failed during Layer 11 preflight' >&2; exit 1; }
NIX_LAYER10_GUEST_ROOT="${L11_ROOT}" \
NIX_LAYER11_STATE_DIR="${L11_STATE}" \
NIX_LAYER11_BIN_DIR="${L11_BIN_DIR}" \
  "${NIXCTL}" bridge preflight "${L11_NAME}" >>"${L11_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl bridge preflight failed during Layer 11 smoke' >&2; exit 1; }

log11 'install: temporary one-shot bridge'
NIX_LAYER10_GUEST_ROOT="${L11_ROOT}" \
NIX_LAYER11_STATE_DIR="${L11_STATE}" \
NIX_LAYER11_BIN_DIR="${L11_BIN_DIR}" \
  "${NIXCTL}" bridge install "${L11_NAME}" -- /usr/bin/nix --version >>"${L11_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 11 bridge install failed' >&2; exit 1; }

log11 'run: host bridge invokes guest-backed command'
NIX_LAYER10_GUEST_ROOT="${L11_ROOT}" \
NIX_LAYER11_STATE_DIR="${L11_STATE}" \
NIX_LAYER11_BIN_DIR="${L11_BIN_DIR}" \
  "${L11_BIN_DIR}/${L11_NAME}" >>"${L11_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 11 bridge run failed' >&2; exit 1; }
grep -q 'nix (Nix)' "${L11_LOG}" \
  || { echo 'FAIL: Layer 11 bridge output did not include nix version' >&2; exit 1; }

log11 'cleanup: verify no guest process remains and remove bridge'
if layer11_guest_running; then
  pkill -f "systemd-nspawn.*${L11_ROOT}" 2>/dev/null || true
  sleep 1
fi
layer11_guest_running \
  && { echo 'FAIL: Layer 11 bridge left guest process running' >&2; exit 1; }
NIX_LAYER11_STATE_DIR="${L11_STATE}" \
NIX_LAYER11_BIN_DIR="${L11_BIN_DIR}" \
  "${NIXCTL}" bridge remove "${L11_NAME}" >>"${L11_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 11 bridge remove failed' >&2; exit 1; }
[ ! -e "${L11_BIN_DIR}/${L11_NAME}" ] \
  || { echo 'FAIL: Layer 11 bridge wrapper survived cleanup' >&2; exit 1; }

printf 'nix-integration Layer 11 smoke passed\n'
printf 'log: %s\n' "${L11_LOG}"
fi

# ---- Layer 12 device-side smoke (opt-in) -----------------------------------
# Set LAYER12_SMOKE=ssh to validate key-only guest SSH on an alternate host
# port. Requires a Layer 10b bootable root with provenance and an operator
# supplied keypair whose public key appears in LAYER12_AUTHORIZED_KEYS.
if [ "${LAYER12_SMOKE:-0}" != "ssh" ]; then
  exit 0
fi

L12_LOG=/tmp/nix-integration-layer12-smoke.log
L12_ROOT="${LAYER12_GUEST_ROOT:-${NIX_LAYER10_GUEST_ROOT:-/storage/machines/rocknix-guest}}"
L12_L10_STATE="${LAYER12_LAYER10_STATE_DIR:-${NIX_LAYER10_STATE_DIR:-/storage/.config/nix-integration/layer10}}"
L12_STATE="${LAYER12_STATE_DIR:-${NIX_LAYER12_STATE_DIR:-/storage/.config/nix-integration/layer12}}"
L12_PORT="${LAYER12_SSH_PORT:-2222}"
L12_KEYS="${LAYER12_AUTHORIZED_KEYS:-/storage/.ssh/authorized_keys}"
L12_IDENTITY="${LAYER12_SSH_IDENTITY:-/storage/.ssh/id_ed25519}"
L12_HOST="${LAYER12_SSH_HOST:-127.0.0.1}"
L12_TIMEOUT="${LAYER12_TIMEOUT:-30}"
rm -f "${L12_LOG}"

log12() {
  printf '[layer12-smoke] %s\n' "$*"
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >>"${L12_LOG}"
}

layer12_guest_running() {
  smoke_nspawn_running "${L12_ROOT}"
}

layer12_stop_guest() {
  NIX_LAYER10_GUEST_ROOT="${L12_ROOT}" \
  NIX_LAYER10_STATE_DIR="${L12_L10_STATE}" \
    "${NIXCTL}" guest stop >>"${L12_LOG}" 2>&1 || true
}

[ -f "${L12_L10_STATE}/rootfs-provenance" ] \
  || { echo "FAIL: Layer 12 smoke requires Layer 10b provenance at ${L12_L10_STATE}/rootfs-provenance" >&2; exit 1; }
grep -q '^sha256=' "${L12_L10_STATE}/rootfs-provenance" \
  || { echo 'FAIL: Layer 12 smoke requires Layer 10b provenance sha256' >&2; exit 1; }
[ -s "${L12_KEYS}" ] \
  || { echo "FAIL: Layer 12 smoke requires authorized keys at ${L12_KEYS}" >&2; exit 1; }
[ -s "${L12_IDENTITY}" ] \
  || { echo "FAIL: Layer 12 smoke requires SSH identity at ${L12_IDENTITY}" >&2; exit 1; }
command -v ssh >/dev/null 2>&1 \
  || { echo 'FAIL: Layer 12 smoke requires ssh client' >&2; exit 1; }

case "${L12_PORT}" in
  22) echo 'FAIL: Layer 12 smoke refuses host port 22' >&2; exit 1 ;;
esac

log12 'pre-flight: Layer 12 guest SSH diagnostics'
NIX_LAYER10_GUEST_ROOT="${L12_ROOT}" \
NIX_LAYER10_STATE_DIR="${L12_L10_STATE}" \
NIX_LAYER12_STATE_DIR="${L12_STATE}" \
  "${NIXCTL}" guest service status >>"${L12_LOG}" 2>&1 \
  || { echo 'FAIL: nixctl guest service status failed during Layer 12 preflight' >&2; exit 1; }

log12 'configure: opt-in guest SSH metadata'
NIX_LAYER10_GUEST_ROOT="${L12_ROOT}" \
NIX_LAYER10_STATE_DIR="${L12_L10_STATE}" \
NIX_LAYER12_STATE_DIR="${L12_STATE}" \
  "${NIXCTL}" guest service enable ssh --port "${L12_PORT}" --authorized-keys "${L12_KEYS}" >>"${L12_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 12 guest SSH enable failed' >&2; exit 1; }

log12 'start: bootable guest with SSH exposure'
NIX_LAYER10_GUEST_ROOT="${L12_ROOT}" \
NIX_LAYER10_STATE_DIR="${L12_L10_STATE}" \
NIX_LAYER12_STATE_DIR="${L12_STATE}" \
  "${NIXCTL}" guest start >>"${L12_LOG}" 2>&1 \
  || { echo 'FAIL: Layer 12 guest start failed' >&2; layer12_stop_guest; exit 1; }

log12 'ssh: execute guest nix version command'
waited=0
while [ "${waited}" -lt "${L12_TIMEOUT}" ]; do
  if ssh -i "${L12_IDENTITY}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/tmp/nix-layer12-known-hosts \
      -o ConnectTimeout=3 \
      -p "${L12_PORT}" "root@${L12_HOST}" /usr/bin/nix --version >>"${L12_LOG}" 2>&1; then
    break
  fi
  waited=$((waited + 3))
  sleep 3
done
grep -q 'nix (Nix)' "${L12_LOG}" \
  || { echo 'FAIL: Layer 12 guest SSH did not return nix version' >&2; layer12_stop_guest; exit 1; }

log12 'stop: remove live SSH exposure'
layer12_stop_guest
sleep 1
layer12_guest_running \
  && { echo 'FAIL: Layer 12 guest process still running after stop' >&2; exit 1; }
if ssh -i "${L12_IDENTITY}" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/tmp/nix-layer12-known-hosts \
    -o ConnectTimeout=3 \
    -p "${L12_PORT}" "root@${L12_HOST}" /usr/bin/nix --version >>"${L12_LOG}" 2>&1; then
  echo 'FAIL: Layer 12 guest SSH still reachable after guest stop' >&2
  exit 1
fi

log12 'diagnostics: Layer 12 doctor remains readable'
NIX_LAYER10_GUEST_ROOT="${L12_ROOT}" \
NIX_LAYER10_STATE_DIR="${L12_L10_STATE}" \
NIX_LAYER12_STATE_DIR="${L12_STATE}" \
  "${DOCTOR}" --offline >>"${L12_LOG}" 2>&1 \
  || { echo 'FAIL: nix-doctor failed after Layer 12 smoke' >&2; exit 1; }

printf 'nix-integration Layer 12 smoke passed (ssh)\n'
printf 'log: %s\n' "${L12_LOG}"
