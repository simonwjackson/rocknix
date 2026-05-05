---
title: Power-profile ROCKNIX SM8550 handhelds with CPU and GPU sysfs caps
date: 2026-05-04
category: best-practices
module: ROCKNIX SM8550 power profiling
problem_type: best_practice
component: tooling
severity: low
applies_when:
  - Tuning battery life for lightweight games on ROCKNIX SM8550 handhelds such as AYN Thor or Odin 2-class devices.
  - Validating whether a game remains playable under reduced CPU and GPU clocks.
  - Creating reversible live power profiles without rebuilding the ROCKNIX image.
tags: [rocknix, sm8550, power-profiling, cpufreq, devfreq, battery, steam, gamescope]
---

# Power-profile ROCKNIX SM8550 handhelds with CPU and GPU sysfs caps

## Context

ROCKNIX on SM8550 handhelds exposes enough kernel control to build practical battery-saving profiles without a RyzenAdj-style tool. During Steam/Balatro testing on an AYN Thor, the game remained smooth even at the minimum exposed CPU and GPU clocks, while battery current dropped from roughly `1.75A` to `0.65A-0.75A` and fan noise fell noticeably.

This is a live tuning workflow: apply caps over SSH, validate in-game feel, sample current clocks and battery draw, then restore the original profile when done.

## Guidance

### 1. Discover the available CPU and GPU controls

CPU clusters are exposed through cpufreq policies:

```bash
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo "--- $p ---"
  cat "$p/related_cpus"
  cat "$p/scaling_available_governors"
  cat "$p/scaling_available_frequencies"
done
```

On the AYN Thor tested here:

| Policy | CPUs | Frequency range |
|---|---:|---:|
| `policy0` | `0 1 2` | `307200` - `2016000` |
| `policy3` | `3 4 5 6` | `499200` - `2803200` |
| `policy7` | `7` | `595200` - `2956800` |

GPU devfreq is exposed at:

```text
/sys/class/devfreq/3d00000.gpu
```

Available GPU clocks on Thor:

```text
220000000 295000000 348000000 401000000 475000000 550000000 615000000 680000000
```

### 2. Save a restore script before applying caps

Before changing clocks, write down the current governors and min/max values and generate a restore script:

```bash
STATE=/storage/power-profile-before-test-$(date +%Y%m%d-%H%M%S).txt
RESTORE=/storage/bin/restore_power_profile.sh
mkdir -p /storage/bin

{
  echo "# CPU"
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    echo "$(basename "$p") related_cpus=$(cat "$p/related_cpus") governor=$(cat "$p/scaling_governor") min=$(cat "$p/scaling_min_freq") max=$(cat "$p/scaling_max_freq") cur=$(cat "$p/scaling_cur_freq")"
  done
  echo "# GPU"
  g=/sys/class/devfreq/3d00000.gpu
  echo "gpu governor=$(cat "$g/governor") min=$(cat "$g/min_freq") max=$(cat "$g/max_freq") cur=$(cat "$g/cur_freq")"
} > "$STATE"
```

A restore script can then reapply those saved values. Keep it under `/storage/bin/` so it survives the session:

```bash
ssh root@thor '/storage/bin/restore_power_profile.sh'
```

### 3. Apply progressively lower profiles

Keep all cores online for scheduler responsiveness, then reduce max clocks by cluster. Use `schedutil` for CPU and `simple_ondemand` for GPU unless testing a fixed userspace governor.

#### Ultra Eco

Good first battery-saving target:

```bash
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo schedutil > "$p/scaling_governor" 2>/dev/null || true
done

echo 1113600 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
echo 1536000 > /sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq
echo 1593600 > /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq

g=/sys/class/devfreq/3d00000.gpu
echo simple_ondemand > "$g/governor" 2>/dev/null || true
echo 401000000 > "$g/max_freq"
```

#### Micro Eco

Worked smoothly for Steam/Balatro:

```bash
echo 902400  > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
echo 1171200 > /sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq
echo 1248000 > /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq
echo 348000000 > /sys/class/devfreq/3d00000.gpu/max_freq
```

#### Nano Eco

Still felt smooth in Balatro:

```bash
echo 672000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
echo 940800 > /sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq
echo 998400 > /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq
echo 295000000 > /sys/class/devfreq/3d00000.gpu/max_freq
```

#### Pico Eco

Near the practical floor:

```bash
echo 441600 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
echo 729600 > /sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq
echo 864000 > /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq
echo 220000000 > /sys/class/devfreq/3d00000.gpu/max_freq
```

#### Absolute floor

Minimum exposed CPU and GPU clocks. Balatro still felt fine in this session, but Steam menus or heavier games may lag:

```bash
echo 307200 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
echo 499200 > /sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq
echo 595200 > /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq
echo 220000000 > /sys/class/devfreq/3d00000.gpu/max_freq
```

### 4. Validate that caps are actually active

Do not trust the profile name. Sample the live clocks and compare `cur` against `max`:

```bash
g=/sys/class/devfreq/3d00000.gpu
for i in $(seq 1 12); do
  printf "%02d " "$i"
  for p in /sys/devices/system/cpu/cpufreq/policy0 \
           /sys/devices/system/cpu/cpufreq/policy3 \
           /sys/devices/system/cpu/cpufreq/policy7; do
    printf "%s_cur=%s/max=%s " \
      "$(basename "$p")" \
      "$(cat "$p/scaling_cur_freq")" \
      "$(cat "$p/scaling_max_freq")"
  done
  printf "gpu_cur=%s/max=%s " "$(cat "$g/cur_freq")" "$(cat "$g/max_freq")"
  printf "batt_mA=%s\n" \
    "$(awk -F= '/POWER_SUPPLY_CURRENT_NOW=/ {print int($2/1000)}' /sys/class/power_supply/battery/uevent 2>/dev/null)"
  sleep 1
done
```

At absolute floor, Thor reported:

```text
policy0 cur/max = 307200 / 307200
policy3 cur/max = 499200 / 499200
policy7 cur/max = 595200 / 595200
GPU     cur/max = 220000000 / 220000000
battery current = ~-650mA to -750mA
```

### 5. Estimate savings from current and voltage

ROCKNIX exposes battery current and voltage via sysfs:

```bash
cat /sys/class/power_supply/battery/uevent | grep -E 'POWER_SUPPLY_(VOLTAGE_NOW|CURRENT_NOW|CAPACITY|TEMP)='
```

Approximate power:

```text
watts = abs(current_now microamps) / 1_000_000 * voltage_now microvolts / 1_000_000
```

Measured in this session:

| State | Current | Approx. power |
|---|---:|---:|
| Before limiting | `~1.75A` | `~7.0W` |
| Ultra Eco | `~1.42A` | `~5.7W` |
| Micro/Nano/Pico range | `~0.7A-1.1A` | `~2.8W-4.4W` |
| Absolute floor | `~0.65A-0.75A` | `~2.6W-3.0W` |

That is roughly a `57-64%` reduction versus the initial Steam/Balatro draw, with an expected runtime multiplier around `2.3x-2.7x` for this specific workload.

## Why This Matters

SM8550-class handhelds have much more CPU and GPU headroom than lightweight games need. For Balatro through Steam/FEX/Gamescope, the bottleneck was not raw CPU/GPU frequency; the game remained visually smooth at the minimum exposed clocks. Hard caps reduced heat, reduced fan speed, and cut battery current by more than half.

This is also safer than blindly changing emulator settings: the caps are reversible, live, and easy to validate from sysfs. They do not require rebuilding ROCKNIX or installing third-party power tools.

## When to Apply

- Apply this for lightweight or 2D games where fan noise or battery life matters more than maximum performance.
- Step down gradually for unknown games; validate feel in-game after each profile.
- Keep a restore script before experimenting.
- Avoid applying absolute floor globally for heavy 3D games, shader compilation, downloads, or initial Steam startup unless you have validated them.
- Treat Gamescope settings as a separate layer: CPU/GPU caps are live system-wide, while Gamescope resolution/FSR/frame-limit choices are generally launch-time settings.

## Examples

### Restore the original clocks after testing

```bash
ssh root@thor '/storage/bin/restore_power_profile.sh'
```

A successful restore brought Thor back to:

```text
CPU governor: ondemand
CPU little max: 2.016 GHz
CPU mid max:    2.803 GHz
CPU prime max:  2.956 GHz
GPU governor:   simple_ondemand
GPU max:        680 MHz
```

### Check whether Steam is running under Gamescope

```bash
pgrep -a gamescope
tr '\0' ' ' </proc/$(pgrep -n gamescope)/cmdline
```

Thor's active Steam session was launched under Gamescope with output geometry and MangoApp enabled:

```text
gamescope --prefer-output DSI-2,DSI-1 -W 1080 -H 1920 -r 120 \
  --xwayland-count 2 --mangoapp --backend drm \
  --force-orientation right --use-rotation-shader -b -e -- steam ...
```

Gamescope FSR/NIS is available on this build (`-F fsr`, `-F nis`, `--sharpness`), but for Balatro the sysfs power caps produced the biggest obvious gain without risking text/UI blur.

## Related

- `docs/solutions/performance-issues/ryujinx-smo-1080p60-rocknix-2026-04-28.md` — separate example of per-game performance tuning on ROCKNIX/SM8550.
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` — related SM8550 operational workflow and device context.
