#!/bin/sh
# remote-cemu-single-run-validation.sh -- one-command headless Cemu validation.
#
# Runs on the ROCKNIX host. It orchestrates several remote-cemu-runner.sh
# variants, analyzes MangoHud CSVs, writes a markdown report, and restores a
# safe post-run power/process state. Designed for validation when nobody can
# visually inspect the device.
set -u

PATH=/run/current-system/sw/bin:/usr/bin:/bin:/storage/.guest:$PATH
export PATH

PROFILE="${1:-potato-30}"
DURATION="${VALIDATION_DURATION:-180}"
TS="$(date '+%Y%m%d-%H%M%S')"
PARENT="/storage/.guest/runs/${TS}-single-run-validation"
REPORT="$PARENT/report.md"
SUMMARY="$PARENT/summary.tsv"
MANIFEST="$PARENT/manifest.txt"
TMP="$PARENT/tmp"
RUNNER="/storage/.guest/remote-cemu-runner.sh"
CLEANUP="/storage/.guest/remote-cemu-cleanup.sh"

mkdir -p "$PARENT" "$TMP"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$PARENT/status.log"; }

restore_power_defaults() {
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    max="$(cat "$p/cpuinfo_max_freq" 2>/dev/null || cat "$p/scaling_max_freq" 2>/dev/null || true)"
    min="$(cat "$p/cpuinfo_min_freq" 2>/dev/null || cat "$p/scaling_min_freq" 2>/dev/null || true)"
    echo schedutil > "$p/scaling_governor" 2>/dev/null || true
    [ -n "$min" ] && echo "$min" > "$p/scaling_min_freq" 2>/dev/null || true
    [ -n "$max" ] && echo "$max" > "$p/scaling_max_freq" 2>/dev/null || true
  done
  g=/sys/class/devfreq/3d00000.gpu
  if [ -d "$g" ]; then
    low="$(cat "$g/available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -n | head -1)"
    high="$(cat "$g/available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -n | tail -1)"
    [ -n "$low" ] && echo "$low" > "$g/min_freq" 2>/dev/null || true
    [ -n "$high" ] && echo "$high" > "$g/max_freq" 2>/dev/null || true
    echo simple_ondemand > "$g/governor" 2>/dev/null || true
  fi
}

collect_final_state() {
  {
    echo '=== final timestamp ==='
    date
    echo '=== guest service ==='
    systemctl --no-pager --full status rocknix-guest-v2.service 2>/dev/null | sed -n '1,60p' || true
    echo '=== cemu/gamescope processes ==='
    pgrep -ax Cemu 2>/dev/null || true
    pgrep -ax cemu 2>/dev/null || true
    pgrep -ax gamescope 2>/dev/null || true
    echo '=== cpu governors ==='
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -d "$p" ] || continue
      echo "$(basename "$p") gov=$(cat "$p/scaling_governor" 2>/dev/null) min=$(cat "$p/scaling_min_freq" 2>/dev/null) max=$(cat "$p/scaling_max_freq" 2>/dev/null) cur=$(cat "$p/scaling_cur_freq" 2>/dev/null)"
    done
    echo '=== gpu governor ==='
    g=/sys/class/devfreq/3d00000.gpu
    [ -d "$g" ] && echo "gpu gov=$(cat "$g/governor" 2>/dev/null) min=$(cat "$g/min_freq" 2>/dev/null) max=$(cat "$g/max_freq" 2>/dev/null) cur=$(cat "$g/cur_freq" 2>/dev/null)"
    echo '=== thermals ==='
    for tz in /sys/class/thermal/thermal_zone*; do
      t="$(cat "$tz/type" 2>/dev/null || true)"
      v="$(cat "$tz/temp" 2>/dev/null || true)"
      [ -n "$t" ] && [ -n "$v" ] && echo "$t $((v/1000))C"
    done | sort
  } > "$PARENT/final-state.txt" 2>&1
}

csv_for_run() {
  find "$1" -maxdepth 1 -type f -name '.Cemu-wrapped_*.csv' ! -name '*summary*' 2>/dev/null | head -1
}

stats_for_cutoff() {
  csv="$1"
  cutoff="$2"
  out="$3"
  vals="$TMP/vals-$$-$cutoff.txt"
  sorted="$TMP/sorted-$$-$cutoff.txt"
  awk -F, -v c="$cutoff" '
    $1 == "fps" { started=1; next }
    started && NF >= 16 {
      elapsed=$16/1000000000
      if (elapsed >= c && $1 ~ /^[0-9.]+$/) print $1 "," $2
    }
  ' "$csv" > "$vals" 2>/dev/null || true
  n="$(wc -l < "$vals" | tr -d ' ')"
  if [ "${n:-0}" -eq 0 ]; then
    printf 'cutoff=%s\tn=0\tavg=0\tmin=0\tp1=0\tp10=0\tmedian=0\tmax=0\tbelow15=0\tbelow20=0\tft_avg=0\tft_max=0\n' "$cutoff" > "$out"
    rm -f "$vals" "$sorted"
    return 0
  fi
  sort -t, -k1,1n "$vals" > "$sorted"
  awk -F, -v c="$cutoff" -v n="$n" '
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
      printf "cutoff=%s\tn=%d\tavg=%.2f\tmin=%.2f\tp1=%.2f\tp10=%.2f\tmedian=%.2f\tmax=%.2f\tbelow15=%d\tbelow20=%d\tft_avg=%.2f\tft_max=%.2f\n", c, n, s/n, min, p1v, p10v, medv, max, b15+0, b20+0, fts/n, ftmax
    }
  ' "$sorted" > "$out"
  rm -f "$vals" "$sorted"
}

field_from_stats() {
  key="$1"
  file="$2"
  tr '\t' '\n' < "$file" | awk -F= -v k="$key" '$1 == k { print $2; exit }'
}

classify_run() {
  run_dir="$1"
  stats70="$2"
  errors_file="$3"
  title_file="$run_dir/title-samples.log"
  csv="$(csv_for_run "$run_dir")"

  [ -n "$csv" ] || { echo FAIL; return; }
  [ -s "$title_file" ] || { echo FAIL; return; }
  grep -q 'FPS:' "$title_file" 2>/dev/null || { echo FAIL; return; }
  [ ! -s "$errors_file" ] || { echo FAIL; return; }

  n="$(field_from_stats n "$stats70")"
  med="$(field_from_stats median "$stats70")"
  p10="$(field_from_stats p10 "$stats70")"
  p1="$(field_from_stats p1 "$stats70")"
  min="$(field_from_stats min "$stats70")"

  awk -v n="$n" -v med="$med" -v p10="$p10" -v p1="$p1" -v min="$min" 'BEGIN { exit !(n >= 30 && med >= 28 && p10 >= 22 && p1 >= 15 && min >= 10) }'
  if [ $? -eq 0 ]; then
    echo PASS
    return
  fi
  awk -v n="$n" -v med="$med" -v p10="$p10" 'BEGIN { exit !(n >= 30 && med >= 28 && p10 >= 22) }'
  if [ $? -eq 0 ]; then
    echo WARN
  else
    echo FAIL
  fi
}

extract_errors() {
  run_dir="$1"
  out="$2"
  : > "$out"
  for f in "$run_dir/guest-state.txt" "$run_dir/host-state.txt" "$run_dir/status.log" "$run_dir/cleanup.log"; do
    [ -f "$f" ] || continue
    grep -Eih 'Unrecoverable error|failed to submit command buffer|signal 11|signal 6|ERROR_INCOMPATIBLE_DRIVER|vkCreateInstance failed|mixed Vulkan|two-loader|segmentation fault|bus error|Aborted' "$f" >> "$out" 2>/dev/null || true
  done
  sort -u "$out" -o "$out" 2>/dev/null || true
}

analyze_run() {
  power="$1"
  variant="$2"
  run_dir="$3"
  idx="$4"
  analysis_dir="$PARENT/analysis-$idx-$variant-$power"
  mkdir -p "$analysis_dir"

  csv="$(csv_for_run "$run_dir")"
  errors="$analysis_dir/errors.txt"
  extract_errors "$run_dir" "$errors"

  for cutoff in 0 40 70 100; do
    if [ -n "$csv" ]; then
      stats_for_cutoff "$csv" "$cutoff" "$analysis_dir/stats-${cutoff}.tsv"
    else
      printf 'cutoff=%s\tn=0\tavg=0\tmin=0\tp1=0\tp10=0\tmedian=0\tmax=0\tbelow15=0\tbelow20=0\tft_avg=0\tft_max=0\n' "$cutoff" > "$analysis_dir/stats-${cutoff}.tsv"
    fi
  done

  title_file="$run_dir/title-samples.log"
  first_line="$(awk '/FPS:/ { print NR; exit }' "$title_file" 2>/dev/null || true)"
  [ -n "$first_line" ] && first_fps_seconds=$(( (first_line - 1) * 2 )) || first_fps_seconds="NA"
  final_title="$(grep 'FPS:' "$title_file" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')"
  [ -n "$final_title" ] || final_title="NA"
  driver="$(grep -E 'Driver version:' "$run_dir/guest-state.txt" 2>/dev/null | tail -1 | sed 's/.*Driver version:[[:space:]]*//')"
  [ -n "$driver" ] || driver="NA"
  gpu="$(grep -E 'Using GPU:' "$run_dir/guest-state.txt" 2>/dev/null | tail -1 | sed 's/.*Using GPU:[[:space:]]*//')"
  [ -n "$gpu" ] || gpu="NA"
  screenshot="$run_dir/screenshot-DSI2.png"
  if [ -s "$screenshot" ]; then
    screenshot_bytes="$(wc -c < "$screenshot" | tr -d ' ')"
  else
    screenshot_bytes=0
  fi

  class="$(classify_run "$run_dir" "$analysis_dir/stats-70.tsv" "$errors")"
  s70="$analysis_dir/stats-70.tsv"
  med="$(field_from_stats median "$s70")"
  p10="$(field_from_stats p10 "$s70")"
  p1="$(field_from_stats p1 "$s70")"
  min="$(field_from_stats min "$s70")"
  avg="$(field_from_stats avg "$s70")"
  n="$(field_from_stats n "$s70")"
  below15="$(field_from_stats below15 "$s70")"
  ftmax="$(field_from_stats ft_max "$s70")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$idx" "$class" "$power" "$variant" "$run_dir" "$driver" "$first_fps_seconds" "$n" "$avg" "$min" "$p1" "$p10" "$med" "$below15" "$ftmax" >> "$SUMMARY"

  {
    echo "variant=$variant"
    echo "power=$power"
    echo "run_dir=$run_dir"
    echo "class=$class"
    echo "gpu=$gpu"
    echo "driver=$driver"
    echo "first_fps_seconds=$first_fps_seconds"
    echo "final_title=$final_title"
    echo "screenshot_bytes=$screenshot_bytes"
    echo "csv=$csv"
  } > "$analysis_dir/metadata.txt"
}

write_report() {
  best_line="$(awk -F '\t' 'NR>1 && ($2=="PASS" || $2=="WARN") { score=($13*1000000)+($12*1000)+$11; if(score>best){best=score; line=$0} } END{print line}' "$SUMMARY")"
  if [ -n "$best_line" ]; then
    best_variant="$(printf '%s\n' "$best_line" | awk -F '\t' '{print $4}')"
    best_power="$(printf '%s\n' "$best_line" | awk -F '\t' '{print $3}')"
    best_class="$(printf '%s\n' "$best_line" | awk -F '\t' '{print $2}')"
  else
    best_variant="none"
    best_power="none"
    best_class="FAIL"
  fi

  {
    echo "# Layer 14 Cemu single-run validation"
    echo
    echo "- Timestamp: $TS"
    echo "- Profile: $PROFILE"
    echo "- Duration per child: ${DURATION}s"
    echo "- Parent run: $PARENT"
    echo "- Recommended candidate: **$best_class $best_power $best_variant**"
    echo
    echo "## Summary"
    echo
    echo "| Class | Power | Variant | Driver | first FPS approx s | post70 n | avg | min | p1 | p10 | median | <15fps samples | max frametime ms |"
    echo "|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
    awk -F '\t' 'NR>1 { printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $2,$3,$4,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15 }' "$SUMMARY"
    echo
    echo "## Classification gates"
    echo
    echo "PASS requires post70 median >= 28, p10 >= 22, p1 >= 15, min >= 10, title FPS observed, no known crash signatures, and at least 30 post70 samples. WARN means median/p10 are acceptable but lows or outliers still fail."
    echo
    echo "## Child runs"
    echo
    awk -F '\t' 'NR>1 { printf "- `%s` `%s` `%s`: %s\n", $3,$4,$2,$5 }' "$SUMMARY"
    echo
    echo "## Errors"
    echo
    found=0
    for e in "$PARENT"/analysis-*/errors.txt; do
      [ -f "$e" ] || continue
      if [ -s "$e" ]; then
        found=1
        echo "### $(basename "$(dirname "$e")")"
        sed 's/^/- /' "$e"
      fi
    done
    [ "$found" -eq 0 ] && echo "No known fatal signatures detected in analyzed run logs."
    echo
    echo "## Final state"
    echo
    echo '```'
    sed -n '1,120p' "$PARENT/final-state.txt" 2>/dev/null || true
    echo '```'
  } > "$REPORT"
}

printf 'idx\tclass\tpower\tvariant\trun_dir\tdriver\tfirst_fps_seconds\tn_post70\tavg_post70\tmin_post70\tp1_post70\tp10_post70\tmedian_post70\tbelow15_post70\tftmax_post70\n' > "$SUMMARY"
: > "$MANIFEST"

log "single-run validation start profile=$PROFILE duration=$DURATION parent=$PARENT"
[ -x "$RUNNER" ] || { log "missing runner: $RUNNER"; exit 2; }
[ -x "$CLEANUP" ] || { log "missing cleanup: $CLEANUP"; exit 2; }

# Product validation defaults to the promoted Nix Cemu + Nix Mesa path. Include
# the diagnostic ROCKNIX Mesa shim only when explicitly requested.
MATRIX="profile guest-gamescope-mangohud
profile guest-direct-mangohud
max guest-gamescope-mangohud"
if [ "${VALIDATION_INCLUDE_ROCKNIXMESA:-0}" = "1" ] && [ -x /storage/.guest/start_cemu_guest_rocknixmesa.sh ]; then
  MATRIX="$MATRIX
profile guest-gamescope-rocknixmesa-mangohud"
fi

idx=0
printf '%s\n' "$MATRIX" | while read power variant; do
  [ -n "${power:-}" ] || continue
  idx=$((idx + 1))
  child_log="$PARENT/child-$idx-$power-$variant.log"
  log "child $idx start power=$power variant=$variant"
  RUNNER_POWER="$power" "$RUNNER" "$variant" "$PROFILE" "$DURATION" > "$child_log" 2>&1
  rc=$?
  run_dir="$(grep -E '^/storage/.guest/runs/' "$child_log" | tail -1 || true)"
  if [ -z "$run_dir" ]; then
    run_dir="$PARENT/failed-child-$idx-$power-$variant"
    mkdir -p "$run_dir"
    cp "$child_log" "$run_dir/status.log" 2>/dev/null || true
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$idx" "$power" "$variant" "$rc" "$run_dir" >> "$MANIFEST"
  analyze_run "$power" "$variant" "$run_dir" "$idx"
  "$CLEANUP" >> "$PARENT/cleanup-between-children.log" 2>&1 || true
  log "child $idx done rc=$rc run=$run_dir"
done

"$CLEANUP" >> "$PARENT/final-cleanup.log" 2>&1 || true
restore_power_defaults
collect_final_state
write_report
log "single-run validation done: $PARENT"
printf '%s\n' "$PARENT"
