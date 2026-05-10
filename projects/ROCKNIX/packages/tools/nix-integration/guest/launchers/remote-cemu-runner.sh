#!/bin/sh
# remote-cemu-runner.sh -- host-side unattended Cemu/BOTW benchmark harness.
#
# Runs on the ROCKNIX host. Creates a timestamped run directory under
# /storage/.guest/runs and collects logs, screenshots, title FPS samples,
# governors, thermals, process env, and Vulkan driver evidence.
set -u

PATH=/run/current-system/sw/bin:/usr/bin:/bin:/storage/.guest:$PATH
export PATH

VARIANT="${1:-guest-direct}"
PROFILE="${2:-potato-30}"
DURATION="${3:-90}"
POWER="${RUNNER_POWER:-max}"
RUNNER_SKIP_GPU_SYSFS="${RUNNER_SKIP_GPU_SYSFS:-0}"
RUNNER_GUEST_CMD_TIMEOUT="${RUNNER_GUEST_CMD_TIMEOUT:-12}"
RUNNER_IPC_TIMEOUT="${RUNNER_IPC_TIMEOUT:-5}"
RUNNER_SAMPLE_TITLES="${RUNNER_SAMPLE_TITLES:-1}"
RUNNER_LAUNCH_ONLY="${RUNNER_LAUNCH_ONLY:-0}"
RUNNER_FINAL_CLEANUP="${RUNNER_FINAL_CLEANUP:-1}"
RUNNER_POST_LAUNCH_DELAY="${RUNNER_POST_LAUNCH_DELAY:-15}"
RUNNER_RESTORE_POWER="${RUNNER_RESTORE_POWER:-1}"
RUNNER_LOCK_DIR="${RUNNER_LOCK_DIR:-/storage/.guest/runs/.remote-cemu-runner.lock}"
RUNNER_SNAPSHOT_SETTINGS="${RUNNER_SNAPSHOT_SETTINGS:-1}"
# Optional build-parity hooks. RUNNER_CEMU_START points at a guest
# launcher script (for example a per-run candidate wrapper) and is
# threaded through MangoHud/gamescope wrappers via CEMU_START without
# changing the default Cemu path for normal runs.
RUNNER_CEMU_START="${RUNNER_CEMU_START:-}"
RUNNER_CEMU_AFFINITY_MASK="${RUNNER_CEMU_AFFINITY_MASK:-0xF8}"
# Host-control is diagnostic only. It must be a launcher that knows how to run
# host /usr/bin/cemu through the same guest-visible display path used for the
# candidate run. The runner passes RUN_DIR/PROFILE/VARIANT and display/MangoHud
# env so the launcher can write comparable evidence into RUN_DIR.
RUNNER_HOST_LAUNCHER="${RUNNER_HOST_LAUNCHER:-/storage/bin/botw-potato-30.sh}"
RUNNER_HOST_DISPLAY_ENV="${RUNNER_HOST_DISPLAY_ENV:-XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1}"
ROM="/storage/roms/wiiu/The Legend of Zelda - Breath of the Wild (USA) (DLC) (v208).wua"
RUNNER_CEMU_ROM="${RUNNER_CEMU_ROM:-$ROM}"
TS="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="${RUNNER_RUN_DIR:-/storage/.guest/runs/${TS}-${VARIANT}-${PROFILE}}"
SETTINGS_PATH="/storage/.config/Cemu/settings.xml"
SETTINGS_SNAPSHOT=""
LOCK_HELD=0

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$RUN_DIR/status.log"; }

acquire_lock() {
  if mkdir "$RUNNER_LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
    printf '%s\n' "pid=$$" "run_dir=$RUN_DIR" "variant=$VARIANT" "profile=$PROFILE" "started=$(date -Iseconds)" > "$RUNNER_LOCK_DIR/owner"
    return 0
  fi
  echo "another Cemu runner appears active: $RUNNER_LOCK_DIR" >&2
  [ -f "$RUNNER_LOCK_DIR/owner" ] && cat "$RUNNER_LOCK_DIR/owner" >&2 || true
  return 1
}

release_lock() {
  [ "$LOCK_HELD" = "1" ] || return 0
  rm -rf "$RUNNER_LOCK_DIR" 2>/dev/null || true
  LOCK_HELD=0
}

snapshot_settings() {
  [ "$RUNNER_SNAPSHOT_SETTINGS" = "1" ] || return 0
  [ -f "$SETTINGS_PATH" ] || return 0
  SETTINGS_SNAPSHOT="$RUN_DIR/settings.xml.before"
  cp -f "$SETTINGS_PATH" "$SETTINGS_SNAPSHOT" 2>/dev/null || SETTINGS_SNAPSHOT=""
}

restore_settings() {
  [ -n "$SETTINGS_SNAPSHOT" ] || return 0
  [ -f "$SETTINGS_SNAPSHOT" ] || return 0
  cp -f "$SETTINGS_SNAPSHOT" "$SETTINGS_PATH" 2>/dev/null || true
}

restore_power_state() {
  [ "$RUNNER_RESTORE_POWER" = "1" ] || return 0
  [ "$POWER" != "none" ] || return 0
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    min="$(cat "$p/cpuinfo_min_freq" 2>/dev/null || true)"
    max="$(cat "$p/cpuinfo_max_freq" 2>/dev/null || true)"
    [ -n "$min" ] && echo "$min" > "$p/scaling_min_freq" 2>/dev/null || true
    [ -n "$max" ] && echo "$max" > "$p/scaling_max_freq" 2>/dev/null || true
    echo schedutil > "$p/scaling_governor" 2>/dev/null || true
  done
  g=/sys/class/devfreq/3d00000.gpu
  if [ "$RUNNER_SKIP_GPU_SYSFS" != "1" ] && [ -d "$g" ]; then
    echo simple_ondemand > "$g/governor" 2>/dev/null || true
    echo 220000000 > "$g/min_freq" 2>/dev/null || true
    echo 680000000 > "$g/max_freq" 2>/dev/null || true
  fi
}

finish() {
  rc=$?
  trap - EXIT INT TERM
  if [ "$RUNNER_LAUNCH_ONLY" != "1" ]; then
    restore_settings || true
  fi
  restore_power_state || true
  release_lock || true
  exit "$rc"
}

trap finish EXIT INT TERM

guest_pid() {
  main="$(systemctl show -p MainPID --value rocknix-guest-v2.service 2>/dev/null || true)"
  [ -n "$main" ] && [ "$main" != "0" ] || return 1
  pgrep -P "$main" 2>/dev/null | head -1
}

run_guest_timeout() {
  seconds="$1"
  shift
  gp="$(guest_pid)" || return 1
  timeout "$seconds" nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "$1"
}

run_guest() {
  run_guest_timeout "$RUNNER_GUEST_CMD_TIMEOUT" "$1"
}

ensure_guest_sway() {
  # The service can be skipped by a transient ordering cycle after the
  # guest is restarted. For unattended runs, repair that by explicitly
  # starting it and waiting for an IPC socket that responds to swaymsg.
  run_guest_timeout 45 'PATH=/run/current-system/sw/bin:/bin:/usr/bin
if ! ls /run/user/0/sway-ipc.0.*.sock >/dev/null 2>&1; then
  systemctl start rocknix-sway-kiosk.service >/dev/null 2>&1 || true
fi
for i in $(seq 1 30); do
  SOCK=$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1 || true)
  if [ -n "$SOCK" ] && timeout 5 env SWAYSOCK="$SOCK" swaymsg -t get_outputs >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done
exit 1'
}

collect_host_state() {
  {
    echo '=== os-release ==='
    cat /etc/os-release 2>/dev/null || true
    echo '=== uptime ==='
    uptime || true
    echo '=== governors ==='
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -d "$p" ] || continue
      echo "$(basename "$p") gov=$(cat "$p/scaling_governor" 2>/dev/null) cur=$(cat "$p/scaling_cur_freq" 2>/dev/null) min=$(cat "$p/scaling_min_freq" 2>/dev/null) max=$(cat "$p/scaling_max_freq" 2>/dev/null) hw=$(cat "$p/cpuinfo_max_freq" 2>/dev/null)"
    done
    g=/sys/class/devfreq/3d00000.gpu
    if [ "$RUNNER_SKIP_GPU_SYSFS" != "1" ] && [ -d "$g" ]; then
      echo "gpu gov=$(cat "$g/governor") cur=$(cat "$g/cur_freq") min=$(cat "$g/min_freq") max=$(cat "$g/max_freq") freqs=$(cat "$g/available_frequencies")"
    else
      echo 'gpu skipped (RUNNER_SKIP_GPU_SYSFS=1 or missing)'
    fi
    echo '=== thermals ==='
    for tz in /sys/class/thermal/thermal_zone*; do
      t="$(cat "$tz/type" 2>/dev/null || true)"
      v="$(cat "$tz/temp" 2>/dev/null || true)"
      [ -n "$t" ] && [ -n "$v" ] && echo "$t $((v/1000))C"
    done | sort
    echo '=== service ==='
    systemctl --no-pager --full status rocknix-guest-v2.service 2>/dev/null | sed -n '1,40p' || true
  } > "$RUN_DIR/host-state.txt" 2>&1
}

set_power() {
  case "$POWER" in
    max)
      for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        max="$(cat "$p/cpuinfo_max_freq" 2>/dev/null || cat "$p/scaling_max_freq")"
        min="$(cat "$p/cpuinfo_min_freq" 2>/dev/null || cat "$p/scaling_min_freq")"
        echo schedutil > "$p/scaling_governor" 2>/dev/null || true
        echo "$min" > "$p/scaling_min_freq" 2>/dev/null || true
        echo "$max" > "$p/scaling_max_freq" 2>/dev/null || true
      done
      g=/sys/class/devfreq/3d00000.gpu
      if [ "$RUNNER_SKIP_GPU_SYSFS" != "1" ] && [ -d "$g" ]; then
        high="$(cat "$g/available_frequencies" | tr ' ' '\n' | sort -n | tail -1)"
        echo "$high" > "$g/max_freq" 2>/dev/null || true
        echo "$high" > "$g/min_freq" 2>/dev/null || true
        echo performance > "$g/governor" 2>/dev/null || true
      fi
      ;;
    profile)
      [ -x /storage/.guest/host-tune.sh ] && /storage/.guest/host-tune.sh "$PROFILE" || true
      ;;
    none) : ;;
    *) echo "unknown RUNNER_POWER=$POWER" >&2; exit 2 ;;
  esac
}

ensure_guest_tool() {
  tool="$1"
  attr="$2"
  run_guest "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin; command -v $tool >/dev/null 2>&1 || nix profile install nixpkgs#$attr" >/dev/null 2>&1 || true
}

write_mangohud_config() {
  run_guest "mkdir -p /storage/.config/MangoHud '$RUN_DIR'; cat > /storage/.config/MangoHud/MangoHud.conf <<'EOF'
legacy_layout=0
fps
frametime
frame_timing
cpu_stats
gpu_stats
gpu_temp
cpu_temp
ram
vram
io_read
io_write
position=top-left
font_size=24
background_alpha=0.45
round_corners=8
output_folder=$RUN_DIR
autostart_log=1
log_duration=$DURATION
EOF"
}

prepare_guest_launcher() {
  start='/storage/.guest/start_cemu_guest.sh'
  CEMU_START_LAUNCH='/storage/.guest/start_cemu_guest.sh'
  write_mangohud_config
  case "$VARIANT" in
    guest-direct) start='/storage/.guest/start_cemu_guest.sh' ;;
    guest-direct-mangohud) ensure_guest_tool mangohud mangohud; start='/storage/.guest/start_cemu_guest_mangohud.sh' ;;
    guest-direct-rocknixmesa) start='/storage/.guest/start_cemu_guest_rocknixmesa.sh'; CEMU_START_LAUNCH='/storage/.guest/start_cemu_guest_rocknixmesa.sh' ;;
    guest-direct-rocknixmesa-mangohud) ensure_guest_tool mangohud mangohud; start='/storage/.guest/start_cemu_guest_mangohud.sh'; CEMU_START_LAUNCH='/storage/.guest/start_cemu_guest_rocknixmesa.sh' ;;
    guest-gamescope) ensure_guest_tool gamescope gamescope; start='/storage/.guest/start_cemu_guest_gamescope.sh' ;;
    guest-gamescope-mangohud) ensure_guest_tool gamescope gamescope; ensure_guest_tool mangohud mangohud; start='/storage/.guest/start_cemu_guest_gamescope.sh' ;;
    guest-gamescope-rocknixmesa) ensure_guest_tool gamescope gamescope; start='/storage/.guest/start_cemu_guest_gamescope.sh'; CEMU_START_LAUNCH='/storage/.guest/start_cemu_guest_rocknixmesa.sh' ;;
    guest-gamescope-rocknixmesa-mangohud) ensure_guest_tool gamescope gamescope; ensure_guest_tool mangohud mangohud; start='/storage/.guest/start_cemu_guest_gamescope.sh'; CEMU_START_LAUNCH='/storage/.guest/start_cemu_guest_rocknixmesa.sh' ;;
    host-control) return 0 ;;
    *) echo "unknown variant: $VARIANT" >&2; exit 2 ;;
  esac

  [ -n "$RUNNER_CEMU_START" ] && CEMU_START_LAUNCH="$RUNNER_CEMU_START"

  # Create a per-run launcher so experiments do not mutate the normal BOTW script.
  # botw-guest.sh itself uses swaymsg exec for the final launch, so any
  # experiment env must be injected into that inner sway command as well.
  LAUNCH_ENV="MANGOHUD_CONFIGFILE=/storage/.config/MangoHud/MangoHud.conf CEMU_START=$CEMU_START_LAUNCH CEMU_AFFINITY_MASK=$RUNNER_CEMU_AFFINITY_MASK GS_NESTED_W=640 GS_NESTED_H=360 GS_OUT_W=1920 GS_OUT_H=1080 GS_REFRESH=60 GS_FILTER=fsr GS_SHARPNESS=5 USE_MANGOHUD=0"
  case "$VARIANT" in *mangohud*) LAUNCH_ENV="MANGOHUD_CONFIGFILE=/storage/.config/MangoHud/MangoHud.conf CEMU_START=$CEMU_START_LAUNCH CEMU_AFFINITY_MASK=$RUNNER_CEMU_AFFINITY_MASK GS_NESTED_W=640 GS_NESTED_H=360 GS_OUT_W=1920 GS_OUT_H=1080 GS_REFRESH=60 GS_FILTER=fsr GS_SHARPNESS=5 USE_MANGOHUD=1" ;; esac
  run_guest "PATH=/run/current-system/sw/bin:/bin:/usr/bin; cp -f /storage/.guest/botw-guest.sh /storage/.guest/.runner-botw-${VARIANT}.sh && sed -i 's|/storage/.guest/start_cemu_guest.sh|$start|g; s|swaymsg \"exec |swaymsg \"exec env $LAUNCH_ENV |' /storage/.guest/.runner-botw-${VARIANT}.sh && chmod +x /storage/.guest/.runner-botw-${VARIANT}.sh"

}

launch_variant() {
  case "$VARIANT" in
    host-control)
      log "launching host control via $RUNNER_HOST_LAUNCHER"
      [ -x "$RUNNER_HOST_LAUNCHER" ] || { log "missing host control launcher: $RUNNER_HOST_LAUNCHER"; return 2; }
      env \
        RUN_DIR="$RUN_DIR" \
        PROFILE="$PROFILE" \
        VARIANT="$VARIANT" \
        CEMU_ROM="$RUNNER_CEMU_ROM" \
        MANGOHUD_CONFIGFILE=/storage/.config/MangoHud/MangoHud.conf \
        $RUNNER_HOST_DISPLAY_ENV \
        "$RUNNER_HOST_LAUNCHER" "$PROFILE" > "$RUN_DIR/host-control-launch.log" 2>&1 &
      ;;
    guest-gamescope|guest-gamescope-mangohud|guest-gamescope-rocknixmesa|guest-gamescope-rocknixmesa-mangohud)
      use_mh=0
      case "$VARIANT" in *mangohud*) use_mh=1 ;; esac
      run_guest_timeout "$RUNNER_IPC_TIMEOUT" "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin; SOCK=\$(ls /run/user/0/sway-ipc.0.*.sock | head -1); timeout $RUNNER_IPC_TIMEOUT env SWAYSOCK=\$SOCK swaymsg \"exec env GS_NESTED_W=640 GS_NESTED_H=360 GS_OUT_W=1920 GS_OUT_H=1080 GS_REFRESH=60 GS_FILTER=fsr GS_SHARPNESS=5 USE_MANGOHUD=$use_mh MANGOHUD_CONFIGFILE=/storage/.config/MangoHud/MangoHud.conf CEMU_START=$CEMU_START_LAUNCH CEMU_AFFINITY_MASK=$RUNNER_CEMU_AFFINITY_MASK CEMU_ROM='$RUNNER_CEMU_ROM' /storage/.guest/.runner-botw-${VARIANT}.sh $PROFILE\" >/dev/null"
      ;;
    guest-direct|guest-direct-mangohud|guest-direct-rocknixmesa|guest-direct-rocknixmesa-mangohud)
      run_guest_timeout "$RUNNER_IPC_TIMEOUT" "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin; SOCK=\$(ls /run/user/0/sway-ipc.0.*.sock | head -1); timeout $RUNNER_IPC_TIMEOUT env SWAYSOCK=\$SOCK swaymsg \"exec env MANGOHUD_CONFIGFILE=/storage/.config/MangoHud/MangoHud.conf CEMU_START=$CEMU_START_LAUNCH CEMU_AFFINITY_MASK=$RUNNER_CEMU_AFFINITY_MASK CEMU_ROM='$RUNNER_CEMU_ROM' /storage/.guest/.runner-botw-${VARIANT}.sh $PROFILE\" >/dev/null"
      ;;
  esac
}

collect_host_control_state() {
  [ "$VARIANT" = "host-control" ] || return 0
  {
    printf '=== host-control launcher ===\n'
    printf 'RUNNER_HOST_LAUNCHER=%s\n' "$RUNNER_HOST_LAUNCHER"
    printf 'RUNNER_HOST_DISPLAY_ENV=%s\n' "$RUNNER_HOST_DISPLAY_ENV"
    printf 'PROFILE=%s\n' "$PROFILE"
    printf 'RUN_DIR=%s\n' "$RUN_DIR"
    printf '=== process list ===\n'
    ps | grep -E 'Cemu|cemu|gamescope|mangohud' | grep -v grep || true
    PID=$(ps -eo pid=,comm=,args= | awk '$2 == "cemu" && $0 ~ /\/usr\/bin\/cemu/ { print $1; found=1; exit } $2 == "Cemu" && found != 1 { candidate=$1 } END { if (!found && candidate != "") print candidate }' || true)
    printf 'CEMU_PID=%s\n' "${PID:-NONE}"
    if [ -n "${PID:-}" ]; then
      printf '=== cemu ps ===\n'
      ps -o pid,stat,pcpu,pmem,rss,vsz,comm,args -p "$PID" || true
      printf '=== cemu env ===\n'
      tr '\0' '\n' < /proc/$PID/environ | grep -E '^(MANGOHUD|LD_PRELOAD|VK_|MESA|XDG_|HOME|WAYLAND|SDL)=' | sort || true
      printf '=== cemu maps runtime ===\n'
      awk '{print $6}' /proc/$PID/maps | grep -E 'vulkan|mesa|freedreno|Mango|gamescope|libdrm|wayland|gbm|SDL|wx|gtk' | sort -u || true
      printf '=== hot threads ===\n'
      ps -T -p "$PID" -o tid,pcpu,comm | sort -k2 -nr | head -20 || true
    fi
    printf '=== host cemu log tail ===\n'
    tail -240 /storage/.config/Cemu/share/log.txt 2>/dev/null || true
  } > "$RUN_DIR/host-control-state.txt" 2>&1
}

collect_guest_state() {
  if [ "$VARIANT" = "host-control" ]; then
    collect_host_control_state
    return 0
  fi
  gp="$(guest_pid || true)"
  [ -n "$gp" ] || return 0
  timeout 12 nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh <<EOF > "$RUN_DIR/guest-state.txt" 2>&1 || true
PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin
printf '=== process list ===\n'
ps aux | grep -E 'Cemu|cemu|gamescope|mangohud' | grep -v grep || true
PID=\$(pgrep -x Cemu 2>/dev/null | head -1 || true)
[ -n "\$PID" ] || PID=\$(pgrep -x cemu 2>/dev/null | head -1 || true)
printf 'CEMU_PID=%s\n' "\${PID:-NONE}"
if [ -n "\${PID:-}" ]; then
  printf '=== cemu ps ===\n'
  ps -o pid,stat,pcpu,pmem,rss,vsz,comm,args -p "\$PID" || true
  printf '=== cemu env ===\n'
  tr '\0' '\n' < /proc/\$PID/environ | grep -E '^(MANGOHUD|LD_PRELOAD|VK_|MESA|XDG_|HOME|WAYLAND|SDL)=' | sort || true
  printf '=== cemu maps runtime ===\n'
  awk '{print \$6}' /proc/\$PID/maps | grep -E 'vulkan|mesa|freedreno|Mango|gamescope|libdrm|wayland|gbm|SDL' | sort -u || true
  printf '=== hot threads ===\n'
  ps -T -p "\$PID" -o tid,pcpu,comm | sort -k2 -nr | head -20 || true
  printf '=== affinity sample ===\n'
  for t in \$(ls /proc/\$PID/task | head -8); do taskset -p "\$t" 2>/dev/null || true; done
fi
printf '=== cgroups / pressure ===\n'
cat /proc/pressure/cpu 2>/dev/null || true
cat /proc/pressure/io 2>/dev/null || true
printf '=== cache shape ===\n'
find /storage/.cache/Cemu/shaderCache -maxdepth 2 -type f -exec ls -lh {} \; 2>/dev/null | sort || true
printf '=== cemu log tail ===\n'
tail -240 /storage/.config/Cemu/share/log.txt 2>/dev/null || true
printf '=== stdout log tail ===\n'
tail -240 /storage/.guest/runs/cemu-stdout.log 2>/dev/null || true
EOF
  timeout 8 nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "PATH=/run/current-system/sw/bin:/bin:/usr/bin; export XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1; grim -o DSI-2 '$RUN_DIR/screenshot-DSI2.png' 2>/dev/null || true" >/dev/null 2>&1 || true
}

sample_titles() {
  [ "$RUNNER_SAMPLE_TITLES" = "1" ] || return 0
  gp="$(guest_pid || true)"
  [ -n "$gp" ] || return 0
  end=$(( $(date +%s) + DURATION ))
  while [ "$(date +%s)" -lt "$end" ]; do
    timeout 6 nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "PATH=/run/current-system/sw/bin:/bin:/usr/bin; SOCK=\$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1); [ -n \"\$SOCK\" ] && timeout $RUNNER_IPC_TIMEOUT env SWAYSOCK=\$SOCK swaymsg -t get_tree 2>/dev/null | grep '\"name\".*Cemu' | head -1 || true" >> "$RUN_DIR/title-samples.log" 2>&1 || true
    sleep 2
  done
}

mkdir -p "$RUN_DIR"
acquire_lock || exit 3
log "runner start variant=$VARIANT profile=$PROFILE duration=$DURATION power=$POWER launch_only=$RUNNER_LAUNCH_ONLY"
snapshot_settings
collect_host_state

if ! /storage/.guest/remote-cemu-cleanup.sh >> "$RUN_DIR/cleanup.log" 2>&1; then
  log "initial cleanup failed; stale emulator processes remain"
  exit 4
fi
prepare_guest_launcher
ensure_guest_sway
set_power
launch_variant

# Launchers often downcap after start; re-apply selected power after a short delay.
sleep "$RUNNER_POST_LAUNCH_DELAY"
set_power

if [ "$RUNNER_LAUNCH_ONLY" = "1" ]; then
  collect_guest_state
  collect_host_state
  log "runner launch-only done: $RUN_DIR"
  printf '%s\n' "$RUN_DIR"
  exit 0
fi

sample_titles
collect_guest_state
collect_host_state
if [ "$RUNNER_FINAL_CLEANUP" = "1" ]; then
  if ! /storage/.guest/remote-cemu-cleanup.sh >> "$RUN_DIR/cleanup.log" 2>&1; then
    log "final cleanup failed; stale emulator processes remain"
    exit 5
  fi
fi
log "runner done: $RUN_DIR"
printf '%s\n' "$RUN_DIR"
