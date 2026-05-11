#!/bin/sh
# host-tune.sh -- runs on the ROCKNIX HOST, not inside the nspawn guest.
# temporary host adapter for privileged sysfs tuning. The guest-side
# cemu-sm8550-performance.sh owns the measured SM8550 policy and attempts the
# same writes from inside nspawn; this host helper patches the remaining gap for
# controls (especially GPU devfreq) that the guest cannot safely own yet.
#
# Usage (from any shell on Thor):
#   /storage/.guest/host-tune.sh <profile>
# Profiles match botw-guest.sh: potato-30 540p-30 540p-45 720p-30 720p-45
#                                900p-30 native-30
set -eu
P="${1:-}"
case "$P" in
  potato-30)  P3=1401600 P7=1478400 GMIN=220000000 GMAX=475000000 GGOV=simple_ondemand ;;
  540p-30)    P3=1401600 P7=1478400 GMIN=220000000 GMAX=550000000 GGOV=simple_ondemand ;;
  540p-45)    P3=2803200 P7=2956800 GMIN=680000000 GMAX=680000000 GGOV=simple_ondemand ;;
  720p-30)    P3=1401600 P7=1478400 GMIN=220000000 GMAX=615000000 GGOV=simple_ondemand ;;
  720p-45)    P3=2803200 P7=2956800 GMIN=680000000 GMAX=680000000 GGOV=simple_ondemand ;;
  900p-30)    P3=1401600 P7=1478400 GMIN=220000000 GMAX=680000000 GGOV=simple_ondemand ;;
  native-30)  P3=1401600 P7=1478400 GMIN=220000000 GMAX=680000000 GGOV=simple_ondemand ;;
  *) echo "usage: $0 <potato-30|540p-30|540p-45|720p-30|720p-45|900p-30|native-30>" >&2; exit 1 ;;
esac

# CPU
echo schedutil > /sys/devices/system/cpu/cpufreq/policy3/scaling_governor 2>/dev/null || true
echo schedutil > /sys/devices/system/cpu/cpufreq/policy7/scaling_governor 2>/dev/null || true
echo "$P3" > /sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq
echo "$P7" > /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq

# GPU (this is the one that fails inside the guest)
echo "$GGOV" > /sys/class/devfreq/3d00000.gpu/governor
[ -n "${GMIN:-}" ] && echo "$GMIN" > /sys/class/devfreq/3d00000.gpu/min_freq
[ -n "${GMAX:-}" ] && echo "$GMAX" > /sys/class/devfreq/3d00000.gpu/max_freq

echo "host-tune $P: cpu=$P3/$P7 gpu=$GGOV/${GMIN:-?}->${GMAX:-?} cur=$(cat /sys/class/devfreq/3d00000.gpu/cur_freq)"
