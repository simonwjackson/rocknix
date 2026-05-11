# Layer 14 — Nix main-space contract

## Goal

Replace the Tier A–E experimental broad-bind nspawn unit with a clean
unit that applies the full validated shopping list, ship it as a
parallel image variant gated by `THIN_HOST=yes`, and keep the legacy
ROCKNIX userland installed-but-not-running as the single-toggle
recovery path. Daily-driver scope on Thor (and AYN Odin 2 Portal).

## Scope

In:

- New systemd-nspawn unit `rocknix-guest-v2.service` with the full
  shopping list applied (no host `/usr`/`/lib`/`/etc/profile`/
  `/etc/resolv.conf` leak, narrow device binds, RW sysfs binds,
  `WorkingDirectory=`, `Restart=on-failure`, `WatchdogSec=30s`,
  `ExecStartPre` seeds `/run/current-system`, `ExecStopPost` reclaims
  host fallback on crash).
- Build flag `THIN_HOST` (default `no`). When `yes` AND
  `DEVICE=SM8550`, the produced image's default systemd target is
  `rocknix-graphical.target` (Wants `rocknix-guest-v2.service`),
  with the legacy host UI (`sway`, `essway`, `pipewire`,
  `wireplumber`, `bluetooth`, `inputplumber`) installed but not
  Wanted.
- Recovery override `rocknix-recovery-toggle.service` (oneshot before
  sysinit) inspects `/flash/rocknix.no-nspawn` and the kernel cmdline
  for `rocknix.safe=1`; either present routes to legacy
  `graphical.target` for that boot.
- Reclaim contract `rocknix-host-reclaim` (ExecStopPost helper) brings
  up the host fallback userland when the guest exits unexpectedly.
- Guest NixOS modules: `display.nix` (sway + Mesa freedreno/turnip),
  `audio.nix` (pipewire + wireplumber + bluez + dbus),
  `network.nix` (NetworkManager + nftables, no resolvconf).
- Cemu compatibility state remains narrow and explicit while the package
  runtime is peeled back: `/storage/.config/Cemu`, `/storage/.local`,
  `/storage/.config/MangoHud`, and writable `/storage/roms/bios` are
  bound for guest-owned adapters; the generic Cemu package wrapper must
  not hardcode these ROCKNIX paths.
- 24-hour standalone soak harness `rocknix-layer14-soak` is the gate
  before flipping the build flag on a flashed image.
- HOW-TO-FALL-BACK.md ships to `/flash/` on `THIN_HOST=yes` builds.

Out:

- AYN Odin 2 Portal validation pass — separate Layer 14b plan.
- Public release readiness — separate Layer 15 plan.
- InputPlumber-in-guest — separate Layer 14c (deferred; Strategy A is
  the default: keep host InputPlumber, guest reads virtual `event7`/
  `event8`).
- Full PipeWire-in-guest A2DP latency parity — separate scope.
- Real PM_SUSPEND kernel work — separate scope; `030-suspend_mode`
  quirk and DT review live elsewhere.
- All non-SM8550 devices — `THIN_HOST=yes` hard-fails outside SM8550.

## Build flag

`projects/ROCKNIX/options` carries
`THIN_HOST="${THIN_HOST:-no}"`.
`projects/ROCKNIX/packages/tools/nix-integration/package.mk`:

- Hard-fails if `THIN_HOST=yes` AND `DEVICE!=SM8550`.
- Always installs the v2 unit, prep helper, reclaim helper, recovery
  toggle script, and recovery toggle service.
- Always enables `rocknix-recovery-toggle.service` (it is harmless
  under `THIN_HOST=no` because `rocknix-graphical.target` is absent
  and the script falls back to `graphical.target`).
- Under `THIN_HOST=yes`: additionally installs and enables
  `rocknix-graphical.target` and `rocknix-guest-v2.service`, and ships
  `/flash/HOW-TO-FALL-BACK.md`.

## Boot decision tree

```text
power-on -> kernel boot -> sysinit.target
   |
   v
rocknix-recovery-toggle.service runs
   |
   |- if /flash/rocknix.no-nspawn exists:
   |    set-default graphical.target  (LEGACY)
   |- else if rocknix.safe=1 in /proc/cmdline:
   |    set-default graphical.target  (LEGACY)
   |- else:
   |    set-default rocknix-graphical.target  (NIX MAIN-SPACE)
   |    (falls back to graphical.target if rocknix-graphical.target absent)
   v
default.target activates
   |
   |- graphical.target -> sway.service + essway.service (legacy host UI)
   |- rocknix-graphical.target -> rocknix-guest-v2.service (Layer 14 guest)
```

## Recovery contract

Two override mechanisms (OR semantics):

1. **Sticky flag file:** `/flash/rocknix.no-nspawn`. Persists until
   removed. Clearable from a card reader on another machine. Use this
   when SSH is dead.
2. **Per-boot kernel cmdline:** `rocknix.safe=1`. Cleared on next
   reboot. Use this when the bootloader can edit cmdline (button
   hold) but `/flash` is awkward to reach.

Either toggle present → legacy UI. Both absent → main-space.

## Reclaim contract

When `rocknix-guest-v2.service` exits, `ExecStopPost` runs
`/usr/bin/rocknix-host-reclaim`. The script:

- Reads `$SERVICE_RESULT`, `$EXIT_CODE`, `$EXIT_STATUS` (set by
  systemd in ExecStopPost).
- Distinguishes graceful stops (success, admin TERM/HUP/INT/QUIT) from
  crash exits (exit-code non-zero, killed by SIGKILL/SIGABRT/SIGSEGV,
  watchdog/timeout/core-dump).
- On crash: starts `sway essway pipewire.socket pipewire-pulse.socket
  wireplumber bluetooth inputplumber` so the device falls back to
  legacy UI without a reboot.
- On graceful stop: skips reclaim.
- Logs every decision to `/var/log/rocknix-host-reclaim.log`.

## Soak gate

`rocknix-layer14-soak` runs the new unit alongside the legacy UI on a
`THIN_HOST=no` image and samples 8 invariants every hour:

1. `/etc/resolv.conf.layer14-owned` marker present in guest rootfs
2. Guest `/etc/resolv.conf` not clobbered by host resolvconf
3. Guest `/run/current-system` symlink resolves
4. Guest PATH does not contain raw host `/usr/bin`/`/usr/sbin`
5. Guest sway alive
6. Guest pipewire alive
7. Host `essway.service` still alive (legacy UI is the soak fallback)
8. Host SSH on `:22` responsive to a BatchMode probe, MemAvailable
   not dropping > 200 MB from baseline

24 hourly samples with zero alarms = pass = ready to flip
`THIN_HOST=yes`. Any alarm fails the run; logs at
`/var/log/layer14-soak.log` and `/var/log/layer14-soak-summary.log`.

## Hardware scope

SM8550 only:

- AYN Thor (primary daily-driver target)
- AYN Odin 2 Portal (Tier 2; separate Layer 14b validation plan)

The build flag hard-fails on any other device. Other ROCKNIX devices
continue to build the legacy path with no behavior change.

## Cemu compatibility state

Layer 14 does not broad-bind `/storage`. Cemu-specific state is exposed
through narrow compatibility binds and normalized inside the guest by
`/storage/.guest/cemu-storage-adapter.sh` (installed from the guest
launcher directory):

- `/storage/.config/Cemu` — existing settings and package-seeded default
  settings destination.
- `/storage/.local` — preserves the historical `~/.local/share/Cemu`
  symlink/state visible to Cemu when `HOME=/storage`.
- `/storage/roms/bios` — writable compatibility root for `online`,
  `mlc01`, and `keys`; this overrides the read-only `/storage/roms`
  bind for that sub-tree only.
- `/storage/.config/MangoHud` — validation overlay config; run-local
  MangoHud configs should still point CSV output at their run directory.

This is a temporary guest adapter contract, not a Cemu package contract.
The package-owned `bin/cemu` entry point owns package-relative runtime
setup such as Vulkan loader visibility and remains free of `/storage`,
BOTW, and SM8550 policy.

## Cemu SM8550 performance policy

Cemu performance controls live in the guest/session layer, not in the
generic package wrapper. `cemu-sm8550-performance.sh` owns the measured
SM8550 profile table for CPU caps, best-effort GPU devfreq, and thread
affinity. The guest Sway session exports `CEMU_AFFINITY_MASK=0xF8` as
the default big-core mask; validation harnesses may set
`CEMU_AFFINITY_MASK=none` for paired scheduler tests.

`host-tune.sh` remains a temporary host adapter for privileged sysfs
controls the guest cannot safely own yet, especially GPU devfreq writes.
It must stay explicit and validation-scoped; the Cemu package entry point
must never learn about SM8550 sysfs paths.

## Sibling profiles

- `dev-env` — interactive sway session for on-device development
  (Korri-adjacent dev environment). Same nspawn substrate, different
  guest profile. See `layer14-dev-env-profile.md` for the contract
  and the live-swap procedure.

## Origin and references

- Brief: `docs/brainstorms/2026-05-07-002-rocknix-thin-host-nix-main-space.md`
- Plan: `docs/plans/2026-05-07-003-feat-rocknix-layer-14-thin-host-main-space-plan.md`
- Sibling: `docs/plans/2026-05-08-001-feat-rocknix-interactive-dev-env-profile-plan.md`
- Predecessor contracts:
  - `layer10-guest-lifecycle-contract.md` — guest lifecycle
  - `layer12-guest-ssh-contract.md` — opt-in SSH on port 2222
  - `layer13-modules-contract.md` — declarative module evaluator
