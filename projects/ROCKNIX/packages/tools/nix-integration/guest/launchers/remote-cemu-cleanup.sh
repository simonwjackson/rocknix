#!/bin/sh
# remote-cemu-cleanup.sh -- host-side cleanup for unattended Cemu experiments.
#
# Runs on the ROCKNIX host. It deliberately avoids broad process
# patterns that match this script's own shell. It is safe to run when
# Cemu/gamescope are not active.
set -u

PATH=/run/current-system/sw/bin:/usr/bin:/bin:/storage/.guest:$PATH
export PATH

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

pids_by_exact_comm() {
  name="$1"
  # Prefer pgrep -x, but also fall back to ps' comm field. Busybox/procps
  # behavior has differed on Thor for host /usr/bin/cemu, and missing that
  # lowercase process contaminated host-control benchmarks.
  {
    pgrep -x "$name" 2>/dev/null || true
    ps -eo pid=,comm= 2>/dev/null | awk -v n="$name" '$2 == n { print $1 }'
  } | sort -n -u
}

kill_exact_name() {
  name="$1"
  pids="$(pids_by_exact_comm "$name")"
  [ -n "$pids" ] || return 0
  log "killing pids named '$name': $pids"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null || true
  sleep 1
  pids="$(pids_by_exact_comm "$name")"
  [ -n "$pids" ] || return 0
  # shellcheck disable=SC2086
  kill -KILL $pids 2>/dev/null || true
}

guest_pid() {
  main="$(systemctl show -p MainPID --value rocknix-guest-v2.service 2>/dev/null || true)"
  [ -n "$main" ] && [ "$main" != "0" ] || return 1
  pgrep -P "$main" 2>/dev/null | head -1
}

run_guest() {
  gp="$(guest_pid || true)"
  [ -n "$gp" ] || return 0
  timeout 10 nsenter -t "$gp" -m -u -i -n -p -r -w /bin/sh -c "$1" 2>/dev/null || true
}

EMULATOR_NAMES="Cemu cemu gamescope gamescope-wl gamescopereaper mangohud"

report_remaining_processes() {
  rc=0
  for name in $EMULATOR_NAMES; do
    pids="$(pids_by_exact_comm "$name")"
    if [ -n "$pids" ]; then
      log "STALE host pids named '$name': $pids"
      rc=1
    fi
  done

  guest_remaining="$(run_guest "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; for name in $EMULATOR_NAMES; do pids=\$(pgrep -x \"\$name\" 2>/dev/null || true); [ -n \"\$pids\" ] && printf '%s %s\\n' \"\$name\" \"\$pids\"; done" || true)"
  if [ -n "$guest_remaining" ]; then
    printf '%s\n' "$guest_remaining" | while IFS= read -r line; do
      log "STALE guest pids: $line"
    done
    rc=1
  fi

  guest_windows="$(run_guest "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; sock=\$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1 || true); [ -n \"\$sock\" ] || exit 0; SWAYSOCK=\$sock swaymsg -t get_tree 2>/dev/null | grep -i 'info.cemu.Cemu\|Cemu .*Breath of the Wild' | head -20" || true)"
  if [ -n "$guest_windows" ]; then
    printf '%s\n' "$guest_windows" | while IFS= read -r line; do
      log "STALE guest window: $line"
    done
    rc=1
  fi

  return "$rc"
}

close_guest_cemu_windows() {
  run_guest "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; sock=\$(ls /run/user/0/sway-ipc.0.*.sock 2>/dev/null | head -1 || true); [ -n \"\$sock\" ] || exit 0; export SWAYSOCK=\$sock; swaymsg '[app_id=\"info.cemu.Cemu\"] kill' >/dev/null 2>&1 || true; swaymsg '[title=\".*Cemu.*\"] kill' >/dev/null 2>&1 || true; swaymsg '[title=\".*Breath of the Wild.*\"] kill' >/dev/null 2>&1 || true"
}

log "cleanup start"

# First close stale Cemu compositor windows. Some host-control failures leave
# pidless Wayland windows in guest sway even after the emulator process exits,
# and those invalidate live FPS observations.
close_guest_cemu_windows

# Guest processes. Use exact process names only. Do not use broad
# command-line patterns: the host nspawn process contains
# `/storage/.config/Cemu` in its bind list and must never be killed by
# cleanup. UI shells are opt-in: killing fuzzel/foot can terminate an
# unrelated operator menu/terminal during diagnostics.
guest_names="$EMULATOR_NAMES"
if [ "${CLEANUP_KILL_UI:-0}" = "1" ]; then
  guest_names="$guest_names fuzzel foot"
fi
run_guest "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin; for name in $guest_names; do pids=\$(pgrep -x \"\$name\" 2>/dev/null || true); [ -n \"\$pids\" ] && kill -TERM \$pids 2>/dev/null || true; done; sleep 1; for name in $guest_names; do pids=\$(pgrep -x \"\$name\" 2>/dev/null || true); [ -n \"\$pids\" ] && kill -KILL \$pids 2>/dev/null || true; done"

# Host-side controls/old experiments. Exact names only, for the same
# reason as above.
kill_exact_name Cemu
kill_exact_name cemu
kill_exact_name gamescope
kill_exact_name gamescope-wl
kill_exact_name gamescopereaper
kill_exact_name mangohud

# Confirm broad cache bind is not active. Do not mutate service files here;
# runner diagnostics should report if this becomes unsafe again.
if mount | grep -q ' on /storage/machines/rocknix-guest/storage/.cache '; then
  log "WARN: guest root .cache appears to be a mountpoint"
fi
if systemctl is-active --quiet rocknix-guest-v2.service; then
  log "guest service active"
else
  log "guest service not active; starting"
  systemctl start rocknix-guest-v2.service 2>/dev/null || true
fi

if report_remaining_processes; then
  log "cleanup done"
else
  log "cleanup incomplete: emulator processes remain"
  [ "${CLEANUP_ALLOW_STALE:-0}" = "1" ] || exit 1
  log "CLEANUP_ALLOW_STALE=1 set; continuing despite stale processes"
fi
