#!/bin/sh
# host-tune.sh -- runs on the ROCKNIX HOST, not inside the nspawn guest.
# Applies CPU + GPU sysfs tuning that the guest cannot do because nspawn
# mounts /sys read-only. botw-guest.sh inside the guest covers /sys/.../cpufreq
# (somehow writable for us) but /sys/class/devfreq is RO -- this script
# patches that gap by running on the host.
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
  540p-45)    P3=1785600 P7=1843200 GMIN=                         GGOV=performance ;;
  720p-30)    P3=1401600 P7=1478400 GMIN=220000000 GMAX=615000000 GGOV=simple_ondemand ;;
  720p-45)    P3=2054400 P7=2092800 GMIN=                         GGOV=performance ;;
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
