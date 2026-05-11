#!/bin/sh
# cemu-sm8550-performance.sh -- measured Thor/SM8550 Cemu performance policy
#
# This helper owns device-specific performance controls for Cemu validation on
# SM8550. It is intentionally outside the generic Cemu package wrapper: CPU/GPU
# sysfs policy and affinity are device/session policy, not Cemu runtime setup.
set -eu

PATH=/run/current-system/sw/bin:/usr/bin:/bin
export PATH

CMD="${1:-apply}"
PROFILE="${2:-540p-45}"
PID="${3:-}"
LOG="${CEMU_PERF_LOG:-/storage/.guest/runs/cemu-sm8550-performance.log}"
P3="${CEMU_POLICY3:-/sys/devices/system/cpu/cpufreq/policy3}"
P7="${CEMU_POLICY7:-/sys/devices/system/cpu/cpufreq/policy7}"
GPU="${CEMU_GPU_DEVFREQ:-/sys/class/devfreq/3d00000.gpu}"
AFFINITY_MASK="${CEMU_AFFINITY_MASK:-0xF8}"

mkdir -p "$(dirname "$LOG")"

write_sysfs() {
  path="$1"
  value="$2"
  [ -n "$value" ] || return 0
  [ -e "$path" ] || return 0
  [ -w "$path" ] || return 0
  printf '%s\n' "$value" > "$path" 2>/dev/null || true
}

profile_values() {
  case "$PROFILE" in
    potato-30)  P3_MAX=1401600; P7_MAX=1478400; GPU_MIN=220000000; GPU_MAX=475000000; GPU_GOV=simple_ondemand ;;
    540p-30)    P3_MAX=1401600; P7_MAX=1478400; GPU_MIN=220000000; GPU_MAX=550000000; GPU_GOV=simple_ondemand ;;
    540p-45)    P3_MAX=2803200; P7_MAX=2956800; GPU_MIN=680000000; GPU_MAX=680000000; GPU_GOV=simple_ondemand ;;
    720p-30)    P3_MAX=1401600; P7_MAX=1478400; GPU_MIN=220000000; GPU_MAX=615000000; GPU_GOV=simple_ondemand ;;
    720p-45)    P3_MAX=2803200; P7_MAX=2956800; GPU_MIN=680000000; GPU_MAX=680000000; GPU_GOV=simple_ondemand ;;
    900p-30)    P3_MAX=1401600; P7_MAX=1478400; GPU_MIN=220000000; GPU_MAX=680000000; GPU_GOV=simple_ondemand ;;
    native-30)  P3_MAX=1401600; P7_MAX=1478400; GPU_MIN=220000000; GPU_MAX=680000000; GPU_GOV=simple_ondemand ;;
    *) echo "Unknown SM8550 Cemu performance profile: $PROFILE" >&2; exit 2 ;;
  esac
}

read_value() {
  path="$1"
  [ -r "$path" ] && tr -d '\n' < "$path" || printf '_'
}

log_state() {
  label="$1"
  {
    echo "[$(date)] $label profile=$PROFILE p3=${P3_MAX:-_} p7=${P7_MAX:-_} gpu=${GPU_GOV:-_}(${GPU_MIN:-_}->${GPU_MAX:-_}) affinity=$AFFINITY_MASK"
    [ -d "$P3" ] && echo "  policy3 governor=$(read_value "$P3/scaling_governor") max=$(read_value "$P3/scaling_max_freq")"
    [ -d "$P7" ] && echo "  policy7 governor=$(read_value "$P7/scaling_governor") max=$(read_value "$P7/scaling_max_freq")"
    [ -d "$GPU" ] && echo "  gpu governor=$(read_value "$GPU/governor") min=$(read_value "$GPU/min_freq") max=$(read_value "$GPU/max_freq") cur=$(read_value "$GPU/cur_freq")"
  } >> "$LOG"
}

apply_profile() {
  profile_values
  log_state before-apply
  if [ -d "$P3" ]; then
    write_sysfs "$P3/scaling_governor" schedutil
    write_sysfs "$P3/scaling_max_freq" "$P3_MAX"
  fi
  if [ -d "$P7" ]; then
    write_sysfs "$P7/scaling_governor" schedutil
    write_sysfs "$P7/scaling_max_freq" "$P7_MAX"
  fi
  # GPU writes may require host privilege depending on nspawn/sysfs behavior.
  # Keep attempts best-effort and let host-tune.sh remain the explicit temporary
  # host adapter for controls the guest cannot own safely yet.
  if [ -d "$GPU" ]; then
    write_sysfs "$GPU/governor" "$GPU_GOV"
    write_sysfs "$GPU/min_freq" "$GPU_MIN"
    write_sysfs "$GPU/max_freq" "$GPU_MAX"
  fi
  log_state after-apply
}

pin_pid() {
  profile_values
  [ -n "$PID" ] || { echo "usage: $0 pin <profile> <pid>" >&2; exit 2; }
  [ -d "/proc/$PID/task" ] || { echo "Cemu PID is not alive: $PID" >&2; exit 1; }
  if [ "$AFFINITY_MASK" != "none" ]; then
    for tid in /proc/"$PID"/task/*; do
      taskset -p "$AFFINITY_MASK" "$(basename "$tid")" >/dev/null 2>&1 || true
    done
  fi
  # Reassert after launch because schedutil/sysfs state may change while Cemu
  # initializes shaders and Vulkan.
  apply_profile
  echo "[$(date)] pin pid=$PID profile=$PROFILE affinity=$AFFINITY_MASK" >> "$LOG"
}

case "$CMD" in
  apply) apply_profile ;;
  pin) pin_pid ;;
  describe) profile_values; echo "profile=$PROFILE p3=$P3_MAX p7=$P7_MAX gpu=$GPU_GOV(${GPU_MIN:-_}->${GPU_MAX:-_}) affinity=$AFFINITY_MASK" ;;
  *) echo "usage: $0 <apply|pin|describe> <profile> [pid]" >&2; exit 2 ;;
esac
