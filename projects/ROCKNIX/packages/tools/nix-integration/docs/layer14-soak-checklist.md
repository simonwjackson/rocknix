# Layer 14 soak checklist

The 24-hour standalone soak is the gate before flipping
`THIN_HOST=yes` on a flashed image. This checklist is the human
sign-off form — read alongside the harness output at
`/var/log/layer14-soak.log` and the one-line outcome at
`/var/log/layer14-soak-summary.log`.

## Pre-soak setup

- [ ] Image built with `THIN_HOST=no` (legacy ROCKNIX UI is
      the soak fallback).
- [ ] Device flashed and booted normally.
- [ ] Host SSH on `root@thor:22` responsive.
- [ ] Guest rootfs present at `/storage/machines/rocknix-guest/`.
- [ ] Guest closure has a current `nix` binary; verify with
      `ls /storage/machines/rocknix-guest/nix/var/nix/profiles/system/sw/bin/nix`.
- [ ] `/storage/.guest/` exists and is writable (the soak helper
      creates it on first run; verify here so the harness doesn't
      fail mid-run).
- [ ] Tailscale up (`tailscale status` shows connected).
- [ ] Wi-Fi associated (`iwctl station wlan0 show` reports
      Connected to vrackie).

## Start the run

```text
systemctl start rocknix-guest-v2.service
sleep 5
rocknix-layer14-soak --hours 24 \
  > /var/log/layer14-soak-stdout.log 2>&1 &
disown
```

Or, for a faster smoke run while iterating:

```text
rocknix-layer14-soak --hours 4 --interval-seconds 600
```

## During the run

- [ ] First sample line in `/var/log/layer14-soak.log` shows
      `guest outer=N inner=M` with both values non-zero.
- [ ] First sample logs no `ALARM:` lines.
- [ ] Sway is visible on the device's display
      (DSI-1 1080x1240 lit, foot or swaybg painting).
- [ ] Audio plays from the guest (`paplay <file>` inside the guest
      via `nsenter -t $INNER -m -u -i -n -p ...` or via the device's
      speakers).

## Pass criteria (24 of 24 samples)

- [ ] Sample 1 (h0): zero alarms.
- [ ] Sample 12 (h11): zero alarms.
- [ ] Sample 24 (h23): zero alarms.
- [ ] Final summary line in `/var/log/layer14-soak-summary.log`:
      `soak PASS after 24/24 samples; alarms=0`.

## Common alarms and their meaning

| Alarm | What it tells you |
|------|------------------|
| `resolv.conf ownership marker missing` | The prep helper didn't run, or someone deleted the marker file in the guest rootfs. The guest config is wrong. |
| `guest /etc/resolv.conf clobbered by host resolvconf` | The Layer 14 unit accidentally bound `/etc/resolv.conf`, OR the guest config doesn't disable resolvconf inside the guest. Re-check the unit's bind list and `network.nix`. |
| `guest /run/current-system not seeded` | `rocknix-layer14-prep` didn't write the symlink, or the prep ran in the wrong rootfs. Inspect the prep log line at start. |
| `guest PATH contains raw /usr/bin or /usr/sbin` | The guest is leaking the host's `/usr` into PATH. The unit's bind list still has `/usr` somewhere. |
| `no sway process anywhere on system` | Guest sway crashed or never started. Check journal for the guest. |
| `no pipewire process` | Guest pipewire didn't start. Check `services.pipewire.enable` in the guest config. |
| `host essway.service not active` | Soak fallback assumption broken. Without the legacy UI present, a guest crash leaves the device with no UI. Restart `essway.service`. |
| `host SSH on :22 not responsive to BatchMode probe` | Either the host SSH config dropped or the guest is fighting for port 22. Check Layer 12 — guest SSH should be on 2222, never 22. |
| `MemAvailable dropped by N kB > 200MB` | Memory leak (probably in guest closure). Capture `/proc/meminfo` and `ps auxf` snapshots; let the run finish to see if it stabilises. |

## Post-soak

- [ ] Archive `/var/log/layer14-soak*.log` to
      `/storage/layer14-soak-runs/YYYY-MM-DD-NNN/`.
- [ ] Note the result in the daily journal: `PASS — Nday soak, 0
      alarms`, or `FAIL — alarm Z at sample H`.
- [ ] Stop the guest before flipping `THIN_HOST=yes`:
      `systemctl stop rocknix-guest-v2.service`.

## Sign-off

```text
Soak completed: ____-__-__   Hours run: ____   Alarms: ____
Operator (initials): ____   Outcome (PASS/FAIL): ____
```

A signed PASS earns the right to flip `THIN_HOST=yes` on a flashed
image.
