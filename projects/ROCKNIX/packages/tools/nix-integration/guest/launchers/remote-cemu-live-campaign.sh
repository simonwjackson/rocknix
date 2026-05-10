#!/bin/sh
# remote-cemu-live-campaign.sh -- one-session live BOTW/Cemu runtime campaign.
#
# Runs on the ROCKNIX host. It launches several Cemu binaries one at a time
# through the same Layer 14 guest pipeline and waits for a human in-game
# checkpoint for each case. The campaign owns cleanup, snapshots, MangoHud CSV
# summaries, and power-state restoration so a full comparison can be gathered
# with one operator session.
set -u

PATH=/run/current-system/sw/bin:/usr/bin:/bin:/storage/.guest:$PATH
export PATH

PROFILE="${CAMPAIGN_PROFILE:-720p-45}"
VARIANT="${CAMPAIGN_VARIANT:-guest-gamescope-mangohud}"
CASE_TIMEOUT="${CAMPAIGN_CASE_TIMEOUT:-900}"
SAMPLE_SECONDS="${CAMPAIGN_SAMPLE_SECONDS:-45}"
RECENT_SAMPLES="${CAMPAIGN_RECENT_SAMPLES:-180}"
APPLY_HOST_TUNE="${CAMPAIGN_APPLY_HOST_TUNE:-1}"
RESTORE_POWER="${CAMPAIGN_RESTORE_POWER:-1}"
SIGNAL_FILE="${CAMPAIGN_SIGNAL_FILE:-/storage/.guest/live-checkpoint}"
CURRENT_CEMU="${CURRENT_CEMU:-/nix/store/wl4g8jjlw6pck4sh4ayah9pdl03z8brp-cemu-2.999.0/bin/Cemu}"
CLASSIC_SDL_CEMU="${CLASSIC_SDL_CEMU:-/nix/store/6sqr7421dzg904dxh9apypmp5z773kzv-cemu-rocknix-style-classic-sdl-2.999.0-rocknix-style-classic-sdl/bin/Cemu}"
ROCKNIX_STYLE_CEMU="${ROCKNIX_STYLE_CEMU:-/nix/store/6r380a086xl04am5kiq0p9bk91wrk0ji-cemu-rocknix-style-2.999.0-rocknix-style/bin/Cemu}"
FAITHFUL_CEMU="${FAITHFUL_CEMU:-}"
ROCKNIX_PACKAGE_CEMU="${ROCKNIX_PACKAGE_CEMU:-}"
TS="$(date '+%Y%m%d-%H%M%S')"
PARENT="${CAMPAIGN_RUN_DIR:-/storage/.guest/runs/${TS}-cemu-live-campaign}"
REPORT="$PARENT/report.md"
SUMMARY="$PARENT/summary.tsv"
TMP="$PARENT/tmp"
CAMPAIGN_LOCK_DIR="${CAMPAIGN_LOCK_DIR:-/storage/.guest/runs/.remote-cemu-live-campaign.lock}"
LOCK_HELD=0

mkdir -p "$PARENT" "$TMP"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$PARENT/status.log"; }

acquire_lock() {
  if mkdir "$CAMPAIGN_LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
    printf '%s\n' "pid=$$" "run_dir=$PARENT" "profile=$PROFILE" "variant=$VARIANT" "started=$(date -Iseconds)" > "$CAMPAIGN_LOCK_DIR/owner"
    return 0
  fi
  echo "another Cemu live campaign appears active: $CAMPAIGN_LOCK_DIR" >&2
  [ -f "$CAMPAIGN_LOCK_DIR/owner" ] && cat "$CAMPAIGN_LOCK_DIR/owner" >&2 || true
  return 1
}

release_lock() {
  [ "$LOCK_HELD" = "1" ] || return 0
  rm -rf "$CAMPAIGN_LOCK_DIR" 2>/dev/null || true
  LOCK_HELD=0
}

guest_pid() {
  main="$(systemctl show -p MainPID --value rocknix-guest-v2.service 2>/dev/null || true)"
  [ -n "$main" ] && [ "$main" != "0" ] || return 1
  pgrep -P "$main" 2>/dev/null | head -1
}

run_guest() {
  seconds="$1"
  shift
  gp="$(guest_pid)" || return 1
  timeout "$seconds" nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "$1"
}

sanitize_label() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '-'
}

default_cases() {
  printf '%s=%s\n' current-nix-cemu "$CURRENT_CEMU"
  if [ -n "$CLASSIC_SDL_CEMU" ]; then
    printf '%s=%s\n' classic-sdl-cemu "$CLASSIC_SDL_CEMU"
  fi
  if [ -n "$FAITHFUL_CEMU" ]; then
    printf '%s=%s\n' faithful-cemu "$FAITHFUL_CEMU"
  fi
  if [ -n "$ROCKNIX_PACKAGE_CEMU" ]; then
    printf '%s=%s\n' rocknix-package-cemu "$ROCKNIX_PACKAGE_CEMU"
  fi
}

case_specs() {
  if [ -n "${CAMPAIGN_CASES:-}" ]; then
    printf '%s\n' "$CAMPAIGN_CASES"
  else
    default_cases
  fi
}

make_candidate_launcher() {
  label="$1"
  bin="$2"
  safe="$(sanitize_label "$label")"
  wrapper="/storage/.guest/.campaign-cemu-start-${safe}.sh"
  base_start="${CAMPAIGN_CEMU_BASE_START:-/storage/.guest/start_cemu_guest_candidate.sh}"
  case "$VARIANT" in
    *rocknixmesa*) base_start="${CAMPAIGN_CEMU_BASE_START:-/storage/.guest/start_cemu_guest_rocknixmesa.sh}" ;;
  esac
  run_guest 10 "cat > '$wrapper' <<'EOF'
#!/run/current-system/sw/bin/bash
set -eu
export CEMU_BIN='$bin'
exec '$base_start' \"\$@\"
EOF
chmod +x '$wrapper'"
  printf '%s' "$wrapper"
}

restore_power_state() {
  [ "$RESTORE_POWER" = "1" ] || return 0
  log "restoring host CPU/GPU state"
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    max="$(cat "$p/cpuinfo_max_freq" 2>/dev/null || cat "$p/scaling_max_freq" 2>/dev/null || true)"
    [ -n "$max" ] && echo "$max" > "$p/scaling_max_freq" 2>/dev/null || true
    echo schedutil > "$p/scaling_governor" 2>/dev/null || true
  done
  g=/sys/class/devfreq/3d00000.gpu
  if [ -d "$g" ]; then
    echo simple_ondemand > "$g/governor" 2>/dev/null || true
    echo 220000000 > "$g/min_freq" 2>/dev/null || true
    echo 680000000 > "$g/max_freq" 2>/dev/null || true
  fi
}

preflight() {
  log "preflight start"
  {
    echo "=== campaign ==="
    echo "profile=$PROFILE"
    echo "variant=$VARIANT"
    echo "case_timeout=$CASE_TIMEOUT"
    echo "sample_seconds=$SAMPLE_SECONDS"
    echo "signal_file=$SIGNAL_FILE"
    echo "apply_host_tune=$APPLY_HOST_TUNE"
    echo "=== os ==="
    cat /etc/os-release 2>/dev/null || true
    echo "=== guest ==="
    systemctl --no-pager --full status rocknix-guest-v2.service 2>/dev/null | sed -n '1,40p' || true
    echo "guest_pid=$(guest_pid 2>/dev/null || true)"
    echo "=== stale processes ==="
    ps | grep -E 'Cemu|cemu|gamescope|remote-cemu' | grep -v grep || true
  } > "$PARENT/preflight-host.txt" 2>&1

  /storage/.guest/remote-cemu-cleanup.sh > "$PARENT/preflight-cleanup.log" 2>&1 || true

  run_guest 20 'PATH=/run/current-system/sw/bin:/bin:/usr/bin
if ! ls /run/user/0/sway-ipc.0.*.sock >/dev/null 2>&1; then
  systemctl start rocknix-sway-kiosk.service >/dev/null 2>&1 || true
fi
SOCK=$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1 || true)
echo "SOCK=$SOCK"
[ -n "$SOCK" ] && timeout 5 env SWAYSOCK="$SOCK" swaymsg -t get_outputs >/tmp/campaign-sway-outputs.txt 2>&1
rc=$?
echo "swaymsg_rc=$rc"
cat /tmp/campaign-sway-outputs.txt 2>/dev/null || true
exit $rc' > "$PARENT/preflight-guest-sway.txt" 2>&1 || {
    log "preflight failed: guest sway IPC did not respond"
    return 1
  }
  log "preflight ok"
}

apply_case_tune() {
  [ "$APPLY_HOST_TUNE" = "1" ] || return 0
  if [ -x /storage/.guest/host-tune.sh ]; then
    log "applying host tune for $PROFILE"
    # Do not wrap this in timeout: if the GPU driver is already wedged, timeout
    # cannot safely unwind a D-state sysfs write. The campaign preflight should
    # only be run after a clean boot.
    /storage/.guest/host-tune.sh "$PROFILE" > "$PARENT/host-tune-${PROFILE}.log" 2>&1 || true
  fi
}

csv_for_run() {
  # MangoHud names the producer after the wrapped binary. Host controls,
  # renamed candidates, and future profile links do not necessarily produce
  # `.Cemu-wrapped_*.csv`, so accept any non-summary CSV in the run directory.
  find "$1" -maxdepth 1 -type f -name '*.csv' ! -name '*summary*' 2>/dev/null | sort | head -1
}

stats_for_recent() {
  csv="$1"
  out="$2"
  vals="$TMP/vals-$$.txt"
  sorted="$TMP/sorted-$$.txt"
  grep '^[0-9.]' "$csv" 2>/dev/null | tail -n "$RECENT_SAMPLES" | awk -F, 'NF >= 2 { print $1 "," $2 }' > "$vals" || true
  n="$(wc -l < "$vals" | tr -d ' ')"
  if [ "${n:-0}" -eq 0 ]; then
    printf 'n=0\tavg=0\tmin=0\tp1=0\tp10=0\tmedian=0\tmax=0\tbelow15=0\tbelow20=0\tft_avg=0\tft_max=0\n' > "$out"
    rm -f "$vals" "$sorted"
    return 0
  fi
  sort -t, -k1,1n "$vals" > "$sorted"
  awk -F, -v n="$n" '
    BEGIN { p1=int(n*0.01)+1; p10=int(n*0.10)+1; med=int(n*0.50)+1 }
    {
      fps=$1; ft=$2
      s += fps; fts += ft
      if (NR == 1) min=fps
      if (NR == p1) p1v=fps
      if (NR == p10) p10v=fps
      if (NR == med) medv=fps
      if (fps < 15) b15++
      if (fps < 20) b20++
      if (ft > ftmax) ftmax=ft
      max=fps
    }
    END {
      printf "n=%d\tavg=%.2f\tmin=%.2f\tp1=%.2f\tp10=%.2f\tmedian=%.2f\tmax=%.2f\tbelow15=%d\tbelow20=%d\tft_avg=%.2f\tft_max=%.2f\n", n, s/n, min, p1v, p10v, medv, max, b15+0, b20+0, fts/n, ftmax
    }
  ' "$sorted" > "$out"
  rm -f "$vals" "$sorted"
}

field_from_stats() {
  key="$1"
  file="$2"
  tr '\t' '\n' < "$file" | awk -F= -v k="$key" '$1 == k { print $2; exit }'
}

collect_snapshot() {
  label="$1"
  bin="$2"
  run_dir="$3"
  snap="$run_dir/live-checkpoint"
  mkdir -p "$snap"
  log "collecting checkpoint snapshot for $label"
  {
    echo "=== checkpoint ==="
    date -Iseconds
    echo "label=$label"
    echo "bin=$bin"
    echo "profile=$PROFILE"
    echo "variant=$VARIANT"
    echo "--- user signal ---"
    cat "$SIGNAL_FILE" 2>/dev/null || true
    echo "=== host thermals ==="
    for tz in /sys/class/thermal/thermal_zone*; do
      t="$(cat "$tz/type" 2>/dev/null || true)"
      v="$(cat "$tz/temp" 2>/dev/null || true)"
      [ -n "$t" ] && [ -n "$v" ] && echo "$t $((v/1000))C"
    done | sort
    echo "=== host cpufreq ==="
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -d "$p" ] || continue
      echo "$(basename "$p") gov=$(cat "$p/scaling_governor" 2>/dev/null) cur=$(cat "$p/scaling_cur_freq" 2>/dev/null) min=$(cat "$p/scaling_min_freq" 2>/dev/null) max=$(cat "$p/scaling_max_freq" 2>/dev/null)"
    done
  } > "$snap/host.txt" 2>&1

  run_guest 12 "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin
PID=\$( (pgrep -x Cemu; pgrep -x cemu) 2>/dev/null | head -1 || true)
echo \"CEMU_PID=\${PID:-NONE}\"
[ -n \"\${PID:-}\" ] && ps -o pid,stat,pcpu,pmem,rss,vsz,comm,args -p \"\$PID\" || true
if [ -n \"\${PID:-}\" ]; then
  echo '=== hot threads ==='
  ps -T -p \"\$PID\" -o tid,pcpu,comm | sort -k2 -nr | head -30 || true
  echo '=== scheduler / cgroup ==='
  cat /proc/\$PID/status | grep -E 'Cpus_allowed|Mems_allowed|voluntary_ctxt|nonvoluntary_ctxt|Threads' || true
  cat /proc/\$PID/cgroup || true
  echo '=== env runtime ==='
  tr '\\0' '\\n' < /proc/\$PID/environ | grep -E '^(MANGOHUD|LD_PRELOAD|VK_|MESA|XDG_|HOME|WAYLAND|SDL)=' | sort || true
  echo '=== maps runtime ==='
  awk '{print \$6}' /proc/\$PID/maps | grep -E 'vulkan|mesa|freedreno|Mango|gamescope|libdrm|wayland|gbm|SDL|wx|gtk' | sort -u || true
fi
echo '=== pressure ==='
cat /proc/pressure/cpu 2>/dev/null || true
cat /proc/pressure/io 2>/dev/null || true
echo '=== cache shape ==='
find /storage/.cache/Cemu/shaderCache -maxdepth 2 -type f -exec ls -lh {} \\; 2>/dev/null | sort || true
echo '=== title sample ==='
SOCK=\$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1 || true)
[ -n \"\$SOCK\" ] && timeout 5 env SWAYSOCK=\$SOCK swaymsg -t get_tree 2>/dev/null | grep '\"name\".*Cemu' | head -1 || true
" > "$snap/guest.txt" 2>&1 || true

  run_guest 8 "PATH=/run/current-system/sw/bin:/bin:/usr/bin; export XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1; grim -o DSI-2 '$snap/screenshot-DSI2.png' 2>/dev/null || true" >/dev/null 2>&1 || true

  sleep "$SAMPLE_SECONDS"
  csv="$(csv_for_run "$run_dir")"
  if [ -n "$csv" ]; then
    cp "$csv" "$snap/$(basename "$csv")" 2>/dev/null || true
    stats_for_recent "$csv" "$snap/recent-fps.tsv"
  else
    printf 'n=0\tavg=0\tmin=0\tp1=0\tp10=0\tmedian=0\tmax=0\tbelow15=0\tbelow20=0\tft_avg=0\tft_max=0\n' > "$snap/recent-fps.tsv"
  fi
}

run_case() {
  label="$1"
  bin="$2"
  safe="$(sanitize_label "$label")"
  run_dir="$PARENT/${safe}-${VARIANT}-${PROFILE}"
  mkdir -p "$run_dir"
  rm -f "$SIGNAL_FILE"

  if ! run_guest 6 "test -x '$bin'" >/dev/null 2>&1; then
    log "skip $label: binary missing in guest: $bin"
    printf '%s\tSKIP\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$bin" "$run_dir" 0 0 0 0 >> "$SUMMARY"
    return 0
  fi

  wrapper="$(make_candidate_launcher "$label" "$bin")"
  log "case start label=$label bin=$bin run=$run_dir"
  apply_case_tune
  RUNNER_POWER=none \
  RUNNER_SKIP_GPU_SYSFS=1 \
  RUNNER_LAUNCH_ONLY=1 \
  RUNNER_SAMPLE_TITLES=0 \
  RUNNER_FINAL_CLEANUP=0 \
  RUNNER_RUN_DIR="$run_dir" \
  RUNNER_CEMU_START="$wrapper" \
  /storage/.guest/remote-cemu-runner.sh "$VARIANT" "$PROFILE" "$CASE_TIMEOUT" > "$run_dir/runner-launch.log" 2>&1 || {
    log "case launch failed label=$label"
    printf '%s\tLAUNCH_FAIL\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$bin" "$run_dir" 0 0 0 0 >> "$SUMMARY"
    /storage/.guest/remote-cemu-cleanup.sh >> "$run_dir/cleanup.log" 2>&1 || true
    return 0
  }

  log "case $label launched. Get BOTW in-game, then run: echo '<visible FPS / notes>' > $SIGNAL_FILE"
  timeout_at=$(( $(date +%s) + CASE_TIMEOUT ))
  status="NO_CHECKPOINT"
  while [ "$(date +%s)" -lt "$timeout_at" ]; do
    if [ -f "$SIGNAL_FILE" ]; then
      status="CHECKPOINT"
      break
    fi
    if ! run_guest 5 "(pgrep -x Cemu || pgrep -x cemu) >/dev/null 2>&1" >/dev/null 2>&1; then
      status="CEMU_EXITED"
      break
    fi
    sleep 3
  done

  if [ "$status" = "CHECKPOINT" ]; then
    collect_snapshot "$label" "$bin" "$run_dir"
  else
    log "case $label ended without checkpoint: $status"
  fi

  /storage/.guest/remote-cemu-cleanup.sh >> "$run_dir/cleanup.log" 2>&1 || true
  sleep 3

  stats="$run_dir/live-checkpoint/recent-fps.tsv"
  [ -f "$stats" ] || printf 'n=0\tavg=0\tmin=0\tp1=0\tp10=0\tmedian=0\tmax=0\tbelow15=0\tbelow20=0\tft_avg=0\tft_max=0\n' > "$stats"
  n="$(field_from_stats n "$stats")"
  avg="$(field_from_stats avg "$stats")"
  p10="$(field_from_stats p10 "$stats")"
  median="$(field_from_stats median "$stats")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$status" "$bin" "$run_dir" "${n:-0}" "${avg:-0}" "${p10:-0}" "${median:-0}" >> "$SUMMARY"
  log "case done label=$label status=$status recent_avg=${avg:-0} recent_median=${median:-0}"
}

write_report() {
  {
    echo "# Cemu live campaign"
    echo
    echo "- Timestamp: $(date -Iseconds)"
    echo "- Profile: $PROFILE"
    echo "- Variant: $VARIANT"
    echo "- Case timeout: $CASE_TIMEOUT seconds"
    echo "- Sample seconds after checkpoint: $SAMPLE_SECONDS"
    echo "- Signal file: $SIGNAL_FILE"
    echo
    echo "## Operator checkpoint command"
    echo
    echo 'After each launch reaches real in-game control, run:'
    echo
    echo '```sh'
    echo "echo 'visible FPS: <value>; notes: <loading/stutter>' > $SIGNAL_FILE"
    echo '```'
    echo
    echo "## Summary"
    echo
    echo "| Label | Status | Recent n | Recent avg | Recent p10 | Recent median | Run directory |"
    echo "|---|---|---:|---:|---:|---:|---|"
    awk -F '\t' 'NR > 1 { printf "| `%s` | `%s` | %s | %s | %s | %s | `%s` |\n", $1,$2,$5,$6,$7,$8,$4 }' "$SUMMARY"
    echo
    echo "## Interpretation"
    echo
    echo "- Trust live in-game MangoHud/user-visible FPS over title/loading samples."
    echo "- If the faithful Cemu candidate materially beats current Nix Cemu, promote it only after one more same-scene confirmation run."
    echo "- If classic SDL2 materially beats current Nix Cemu but faithful does not, inspect the Cubeb/non-PIE deltas before promotion."
    echo "- If all guest-native candidates are poor, continue with remaining dependency-stack, cache, and CPU/nspawn scheduler diagnostics using the captured process maps and pressure data."
  } > "$REPORT"
}

trap 'log "campaign interrupted"; /storage/.guest/remote-cemu-cleanup.sh >> "$PARENT/final-cleanup.log" 2>&1 || true; restore_power_state || true; write_report || true; release_lock || true' INT TERM EXIT

printf 'label\tstatus\tbin\trun_dir\tn_recent\tavg_recent\tp10_recent\tmedian_recent\n' > "$SUMMARY"
cat > "$REPORT" <<EOF
# Cemu live campaign

Campaign is running. Watch $PARENT/status.log.
EOF

acquire_lock || exit 3
log "campaign start parent=$PARENT"
preflight || exit 1

case_specs | while IFS= read -r spec; do
  [ -n "$spec" ] || continue
  label="${spec%%=*}"
  bin="${spec#*=}"
  [ "$label" != "$bin" ] || label="candidate"
  run_case "$label" "$bin"
done

restore_power_state
write_report
log "campaign done: $REPORT"
release_lock
trap - INT TERM EXIT
printf '%s\n' "$PARENT"
