#!/bin/sh
# remote-cemu-runtime-ab.sh -- host-side Cemu binary A/B harness.
#
# Runs current guest Cemu and one or more candidate guest Cemu binaries
# through the same remote-cemu-runner display/session envelope. It is
# intentionally conservative: candidates are selected with CEMU_BIN and
# the normal guest launcher still owns config/cache setup.
set -u

PATH=/run/current-system/sw/bin:/usr/bin:/bin:/storage/.guest:$PATH
export PATH

MODE="matrix"
if [ "${1:-}" = "live" ]; then
  MODE="live"
  shift
fi

PROFILE="${1:-potato-30}"
DURATION="${2:-120}"
VARIANT="${RUNTIME_AB_VARIANT:-guest-direct-mangohud}"
POWER="${RUNNER_POWER:-max}"
CURRENT_CEMU="${CURRENT_CEMU:-/run/current-system/sw/bin/cemu}"
CANDIDATE_CEMU="${CANDIDATE_CEMU:-}"
CANDIDATE_LABEL="${CANDIDATE_LABEL:-candidate-cemu}"
CANDIDATE_CEMUS="${CANDIDATE_CEMUS:-}"
TS="$(date '+%Y%m%d-%H%M%S')"
PARENT_DIR="${RUNTIME_AB_RUN_DIR:-/storage/.guest/runs/${TS}-cemu-runtime-ab}"
REPORT="$PARENT_DIR/report.md"
SIGNAL_FILE="${LIVE_CHECKPOINT_FILE:-/storage/.guest/live-checkpoint}"

mkdir -p "$PARENT_DIR"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$PARENT_DIR/status.log" >&2; }

guest_pid() {
  main="$(systemctl show -p MainPID --value rocknix-guest-v2.service 2>/dev/null || true)"
  [ -n "$main" ] && [ "$main" != "0" ] || return 1
  pgrep -P "$main" 2>/dev/null | head -1
}

run_guest() {
  gp="$(guest_pid)" || return 1
  nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "$1"
}

sanitize_label() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '-'
}

make_candidate_launcher() {
  label="$1"
  bin="$2"
  safe="$(sanitize_label "$label")"
  wrapper="/storage/.guest/.candidate-cemu-start-${safe}.sh"
  base_start="${RUNTIME_AB_CEMU_BASE_START:-/storage/.guest/start_cemu_guest_candidate.sh}"
  case "$VARIANT" in
    *rocknixmesa*) base_start="${RUNTIME_AB_CEMU_BASE_START:-/storage/.guest/start_cemu_guest_rocknixmesa.sh}" ;;
  esac
  run_guest "cat > '$wrapper' <<'EOF'
#!/run/current-system/sw/bin/bash
set -eu
export CEMU_BIN='$bin'
exec '$base_start' \"\$@\"
EOF
chmod +x '$wrapper'"
  printf '%s' "$wrapper"
}

append_summary() {
  label="$1"
  run_dir="$2"
  status="$3"
  printf '| `%s` | `%s` | `%s` |\n' "$label" "$status" "$run_dir" >> "$REPORT"
}

run_case() {
  label="$1"
  bin="$2"
  duration="$3"
  safe="$(sanitize_label "$label")"
  child_dir="$PARENT_DIR/${safe}-${VARIANT}-${PROFILE}"
  wrapper="$(make_candidate_launcher "$label" "$bin")" || return 1
  log "case start label=$label bin=$bin child=$child_dir"
  out="$(RUNNER_POWER="$POWER" RUNNER_RUN_DIR="$child_dir" RUNNER_CEMU_START="$wrapper" /storage/.guest/remote-cemu-runner.sh "$VARIANT" "$PROFILE" "$duration" 2>&1)"
  rc=$?
  printf '%s\n' "$out" > "$child_dir/runtime-ab-runner-output.log" 2>/dev/null || true
  if [ "$rc" -eq 0 ]; then
    append_summary "$label" "$child_dir" "OK"
  else
    append_summary "$label" "$child_dir" "FAIL rc=$rc"
  fi
  log "case done label=$label rc=$rc"
  return 0
}

write_header() {
  cat > "$REPORT" <<EOF
# Cemu runtime A/B

- Timestamp: $(date -Iseconds)
- Profile: $PROFILE
- Variant: $VARIANT
- Duration: $DURATION seconds
- Power mode: $POWER
- Current Cemu: $CURRENT_CEMU
- Candidate Cemu: ${CANDIDATE_CEMU:-not provided}

## Run summary

| Candidate | Status | Run directory |
|---|---|---|
EOF
}

matrix_mode() {
  write_header
  run_case "promoted-nix-cemu" "$CURRENT_CEMU" "$DURATION"

  if [ -n "$CANDIDATE_CEMUS" ]; then
    printf '%s\n' "$CANDIDATE_CEMUS" | while IFS= read -r spec; do
      [ -n "$spec" ] || continue
      label="${spec%%=*}"
      bin="${spec#*=}"
      [ "$label" != "$bin" ] || label="candidate"
      run_case "$label" "$bin" "$DURATION"
    done
  elif [ -n "$CANDIDATE_CEMU" ]; then
    run_case "$CANDIDATE_LABEL" "$CANDIDATE_CEMU" "$DURATION"
  fi

  cat >> "$REPORT" <<EOF

## Interpretation notes

- Compare runs by live MangoHud/user-visible FPS when available. Loading/title samples are supportive only.
- If the ROCKNIX-style candidate wins, promote it in a follow-up after one more live-in-game checkpoint.
- If it does not win, continue toward shader/cache, storage latency, CPU scheduler/affinity, or Cemu AArch64 backend investigation.
EOF
}

collect_live_snapshot() {
  label="$1"
  child_dir="$2"
  seconds="$3"
  mkdir -p "$child_dir/live-checkpoint"
  {
    echo "=== live checkpoint ==="
    date -Iseconds
    echo "label=$label"
    echo "signal_file=$SIGNAL_FILE"
    [ -f "$SIGNAL_FILE" ] && { echo "--- user signal ---"; cat "$SIGNAL_FILE"; }
    echo "=== host thermals ==="
    for tz in /sys/class/thermal/thermal_zone*; do
      t="$(cat "$tz/type" 2>/dev/null || true)"
      v="$(cat "$tz/temp" 2>/dev/null || true)"
      [ -n "$t" ] && [ -n "$v" ] && echo "$t $((v/1000))C"
    done | sort
  } > "$child_dir/live-checkpoint/host.txt" 2>&1

  gp="$(guest_pid || true)"
  if [ -n "$gp" ]; then
    nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh <<EOF > "$child_dir/live-checkpoint/guest.txt" 2>&1
PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin
PID=\$( (pgrep -x Cemu; pgrep -x cemu) 2>/dev/null | head -1 || true)
echo "CEMU_PID=\${PID:-NONE}"
[ -n "\${PID:-}" ] && ps -o pid,stat,pcpu,pmem,rss,vsz,comm,args -p "\$PID" || true
if [ -n "\${PID:-}" ]; then
  echo '=== hot threads ==='
  ps -T -p "\$PID" -o tid,pcpu,comm | sort -k2 -nr | head -20 || true
  echo '=== maps graphics ==='
  awk '{print \$6}' /proc/\$PID/maps | grep -E 'vulkan|mesa|freedreno|Mango|gamescope|libdrm|wayland|gbm|SDL' | sort -u || true
fi
echo '=== title sample ==='
SOCK=\$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1 || true)
[ -n "\$SOCK" ] && SWAYSOCK=\$SOCK swaymsg -t get_tree 2>/dev/null | grep '"name".*Cemu' | head -1 || true
EOF
    nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "PATH=/run/current-system/sw/bin:/bin:/usr/bin; export XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1; grim -o DSI-2 '$child_dir/live-checkpoint/screenshot-DSI2.png' 2>/dev/null || true" >/dev/null 2>&1 || true
  fi
  sleep "$seconds"
}

live_mode() {
  label="${LIVE_LABEL:-${3:-$CANDIDATE_LABEL}}"
  bin="${LIVE_CEMU_BIN:-${CANDIDATE_CEMU:-}}"
  [ -n "$bin" ] || { echo "live mode requires LIVE_CEMU_BIN or CANDIDATE_CEMU" >&2; exit 2; }
  write_header
  child_dir="$PARENT_DIR/live-$(sanitize_label "$label")-${VARIANT}-${PROFILE}"
  wrapper="$(make_candidate_launcher "$label" "$bin")"
  rm -f "$SIGNAL_FILE"
  log "live start label=$label bin=$bin child=$child_dir signal=$SIGNAL_FILE"
  RUNNER_POWER="$POWER" RUNNER_RUN_DIR="$child_dir" RUNNER_CEMU_START="$wrapper" /storage/.guest/remote-cemu-runner.sh "$VARIANT" "$PROFILE" "$DURATION" > "$PARENT_DIR/live-runner.log" 2>&1 &
  runner_pid=$!

  timeout_at=$(( $(date +%s) + DURATION ))
  checkpoint_status="NO_CHECKPOINT"
  while kill -0 "$runner_pid" 2>/dev/null; do
    if [ -f "$SIGNAL_FILE" ]; then
      checkpoint_status="CHECKPOINT"
      log "checkpoint observed; collecting live snapshot"
      collect_live_snapshot "$label" "$child_dir" "${LIVE_SAMPLE_SECONDS:-30}"
      break
    fi
    [ "$(date +%s)" -ge "$timeout_at" ] && break
    sleep 2
  done

  if [ "${LIVE_KEEP_RUNNING:-0}" != "1" ]; then
    /storage/.guest/remote-cemu-cleanup.sh >> "$PARENT_DIR/live-cleanup.log" 2>&1 || true
  fi
  wait "$runner_pid" 2>/dev/null || true
  append_summary "$label" "$child_dir" "$checkpoint_status"
  cat >> "$REPORT" <<EOF

## Live checkpoint

- Status: $checkpoint_status
- Signal file: $SIGNAL_FILE
- Snapshot directory: $child_dir/live-checkpoint
- Keep running: ${LIVE_KEEP_RUNNING:-0}
EOF
}

log "runtime A/B start mode=$MODE parent=$PARENT_DIR"
case "$MODE" in
  matrix) matrix_mode ;;
  live) live_mode "$@" ;;
esac
log "runtime A/B done: $PARENT_DIR"
printf '%s\n' "$PARENT_DIR"
