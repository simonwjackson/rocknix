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

kill_exact_name() {
  name="$1"
  pids="$(pgrep -x "$name" 2>/dev/null || true)"
  [ -n "$pids" ] || return 0
  log "killing pids named '$name': $pids"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null || true
  sleep 1
  pids="$(pgrep -x "$name" 2>/dev/null || true)"
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

log "cleanup start"

# Guest processes. Use exact process names only. Do not use broad
# command-line patterns: the host nspawn process contains
# `/storage/.config/Cemu` in its bind list and must never be killed by
# cleanup. UI shells are opt-in: killing fuzzel/foot can terminate an
# unrelated operator menu/terminal during diagnostics.
guest_names="Cemu cemu gamescope gamescope-wl gamescopereaper mangohud"
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

log "cleanup done"
