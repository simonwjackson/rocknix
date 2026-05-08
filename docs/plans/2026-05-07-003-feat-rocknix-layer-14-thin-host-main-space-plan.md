---
title: "feat: ROCKNIX Layer 14 — thin host, Nix main-space"
type: feat
status: active
date: 2026-05-07
origin: docs/brainstorms/2026-05-07-002-rocknix-thin-host-nix-main-space.md
verify_command: "bash projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh"
---

# feat: ROCKNIX Layer 14 — thin host, Nix main-space

## Summary

Take the *safest biggest* swing on the main-space architecture: replace the
experimental broad-bind nspawn unit with a clean Layer 14 unit that applies
the full Tier A–E shopping list, add a `THIN_HOST=yes` build flag that
produces a parallel `ROCKNIX-SM8550-NIX` image whose default
`graphical.target` *is* the guest, and ship a single-toggle recovery
override (flag file or kernel cmdline) that boots the legacy ROCKNIX
userland from the same image. Daily-drive on Thor for two weeks before
considering the architecture proven. Same kernel, same DT, same
bootloader, same `/storage` layout — only what runs in userspace changes.

---

## Problem Frame

ROCKNIX layered Nix capability up through Layer 13. The current Layer 10b
broad-bind nspawn unit demonstrably works (Tier A–E spikes all pass) but
is structurally wrong for daily-driver use: it leaks host `/usr` into the
guest, fights `/etc/resolv.conf` under load, pins Mesa to host store
paths, and forces fragile workarounds (`WLR_LIBINPUT_NO_DEVICES=1`,
manual `WorkingDirectory=`, etc.). Every fix added to the broad-bind
unit perpetuates the underlying mistake. The architecture brief
established that the only durable resolution is to make ROCKNIX the
recovery plane and let the Nix space own the userspace; the
de-risking work to support that decision is done. This plan executes
the swing.

See origin: `docs/brainstorms/2026-05-07-002-rocknix-thin-host-nix-main-space.md`

---

## Requirements

- R1. Layer 14 nspawn unit replaces the broad-bind unit, applying the
  full Tier A–E shopping list: clean device binds (`/dev/snd/*`,
  `/dev/rfkill`, `/dev/dri/{card0,renderD128}`, `/dev/uinput` if the
  guest will own InputPlumber, `/dev/console`, `/dev/tty0..N`); RW
  sysfs binds for backlight/leds/devfreq/cpufreq; no host `/usr`,
  `/lib`, `/etc/profile`, `/etc/resolv.conf`, or
  `/etc/ssh/authorized_keys.d` binds; ExecStartPre seeds
  `/run/current-system` and `/run/booted-system` from
  `/nix/var/nix/profiles/system`; `WorkingDirectory=` set; declarative
  `/etc/resolv.conf` ownership inside guest.
- R2. `THIN_HOST=yes` build flag produces a parallel SM8550 image
  variant (`ROCKNIX-SM8550-NIX`) whose default systemd target is
  `rocknix-graphical.target` (which Wants the guest), with the legacy
  userland (`sway`, `essway`, `pipewire`, `wireplumber`, `bluetooth`,
  `connman`, `iwd`, `wpa_supplicant`, host `inputplumber`) installed
  on disk but not started.
- R3. Recovery override: presence of `/flash/rocknix.no-nspawn` OR
  `rocknix.safe=1` on the kernel cmdline causes early-boot to set
  default target to legacy `graphical.target` for that boot only.
- R4. Guest closure provides display (sway + foot + swaybg + Mesa with
  freedreno/turnip), audio (pipewire + wireplumber), bluetooth (bluez
  + dbus), input (consume virtual `event7`/`event8` per E4 Strategy A),
  network (single network manager — NetworkManager or iwd, never both),
  with `time.timeZone` set and `hardware.graphics.enable = true`.
- R5. Tailscale auto-starts on cold boot in both default and
  recovery modes. The setting fix discovered during E3
  (`set_setting tailscale.up 1` against the system config store) is
  encoded as a default in the image build, not relied on as a manual
  one-time intervention.
- R6. A 24-hour standalone soak of the Layer 14 unit on the existing
  (un-flipped) image must pass before the build flag is flipped on a
  flashed image.
- R7. Hardware scope: SM8550 only (Thor + AYN Odin 2 Portal). All other
  ROCKNIX devices continue to build the legacy path with no behavior
  change. The `THIN_HOST` flag MUST be a no-op for non-SM8550 builds.
- R8. Cold boot to a fully-usable Nix space (sway up, network up, ssh
  responsive) ≤ 15s wall on Thor. Tier E3 baseline is host-only at
  11.3s + 2.1s guest-cold-start = 13.4s; the budget allows up to 1.6s
  of regression.
- R9. `/flash/HOW-TO-FALL-BACK.md` ships in both image variants with
  the recovery toggle instructions, readable from a teardown / SD-card
  reader on a separate machine.
- R10. `/storage` layout is untouched. Existing ROMs, saves, scrapes,
  EmulationStation configs, IWD PSKs, and Bluetooth pairings continue
  to work. Guest reaches `/storage` only via explicit, narrow
  bind-mounts.
- R11. Host SSH on `root@thor:22` continues to work in both default and
  recovery modes. Guest SSH (if enabled) lives on a different port per
  Layer 12 contract.
- R12. No kernel, DT, bootloader, or partition-layout changes. The
  swing is entirely in userspace + systemd target wiring + the build
  flag.

**Origin actors:** owner-operator (sole user), Thor (primary device),
AYN Odin 2 Portal (secondary device, Tier 2 validation).

**Origin flows (carried from brainstorm):** main-space cold boot,
suspend/resume, broken-config rollback, guest crash & host reclaim,
recovery override boot, factory-flash recovery.

**Origin acceptance examples:**
- AE1. Cold boot Thor on `THIN_HOST=yes` image; sway from guest paints
  on DSI-1 within 15s, network up, ssh-from-laptop succeeds.
- AE2. With Thor running on the new image, `touch
  /flash/rocknix.no-nspawn`, reboot. Boot reaches legacy ROCKNIX UI
  (essway) and ssh works as before.
- AE3. With Thor running, induce a guest oops (`pkill -9 -f
  systemd-nspawn`). Within 5s the host reclaim contract restarts host
  pipewire + sway + essway and the device is usable again.
- AE4. Roll back a broken guest config: from inside the guest,
  `nix-env -p /nix/var/nix/profiles/system --switch-generation N` and
  `switch-to-configuration test`. Guest survives. (Already proven in
  E2; this AE is regression coverage.)

---

## Scope Boundaries

- Hardware: Thor and AYN Odin 2 Portal (both SM8550) **only**. All
  other ROCKNIX devices are out of scope.
- No replacement of, or change to, the ROCKNIX kernel, DT,
  bootloader, or partition layout.
- No replacement of `inputplumber` (Strategy A from E4: keep host
  InputPlumber, guest reads virtual event7/event8).
- No public release of `THIN_HOST=yes` images. Personal daily-driver
  scope only until the 14-day live-in proves the architecture.
- No attempt to share audio between host and guest (E5 confirmed
  ownership swaps cleanly; sharing is a different problem and is
  deferred).
- No attempt at full PipeWire-in-guest A2DP (E5e) or paired-controller
  reconnect-across-suspend (E5d) in this plan; both are deferred.

### Deferred to Follow-Up Work

- **AYN Odin 2 Portal validation pass** (Layer 14b): repeat Tier A1,
  B2, E1, E3, E5a/b on Odin 2 Portal once Thor's 14-day live-in is
  clean. Separate plan, separate flash.
- **Public-release readiness pass** (Layer 15): documentation, user
  toggle UI in EmulationStation, OTA upgrade story, signed image,
  user-facing "switch to Nix mode" workflow. Separate plan.
- **Move InputPlumber into guest** (Layer 14c, optional): bind
  `/dev/uinput`, run InputPlumber from guest closure, reclaim event3
  ownership. Separate plan if Strategy A's limits surface in
  daily-driving.
- **PipeWire A2DP-in-guest** (E5e completion): full BlueZ + PipeWire
  Bluetooth chain inside guest, latency measurement vs host stack.
- **Real PM_SUSPEND** kernel work (separate from this plan):
  `030-suspend_mode` quirk removal + DT review.

---

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/packages/tools/nix-integration/package.mk` — the
  one-and-only place where nix-integration installs into the image.
  Pattern: env-overridable variables (`NIX_INTEGRATION_SUPPORT`,
  `NIX_DAEMON_SUPPORT`) with `:-yes` defaults. Layer 14 adds `THIN_HOST`
  here.
- `projects/ROCKNIX/packages/tools/nix-integration/system.d/` — existing
  systemd unit drop location. Layer 14 adds two units
  (`rocknix-guest@v2.service`, `rocknix-recovery-toggle.service`) and
  one target (`rocknix-graphical.target`).
- `projects/ROCKNIX/packages/tools/nix-integration/guest/` — existing
  guest NixOS module set: `flake.nix`, `rocknix-guest.nix`,
  `modules/{base,ssh,tools}.nix`, `profiles/{minimal,ssh}.nix`. Layer
  14 adds three modules (`display.nix`, `audio.nix`, `network.nix`)
  and a new profile (`profiles/main-space.nix`).
- `projects/ROCKNIX/packages/tools/nix-integration/docs/` — existing
  layer contract docs (one per layer). Layer 14 adds
  `layer14-main-space-contract.md`.
- `projects/ROCKNIX/packages/sysutils/autostart/sources/autostart` and
  `/usr/lib/autostart/common/099-networkservices` — the existing
  daemon gating mechanism (`get_setting tailscale.up`,
  `set_setting tailscale.up 1`). The Tailscale-on-boot fix lives by
  shipping the right default in the system config store, not by
  bypassing the autostart layer.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/{nix-integration-runtime-smoke.sh,nix-integration-static-checks.sh}`
  — existing test harnesses. Layer 14 extends both, no new harnesses.
- `projects/ROCKNIX/options` — distribution-wide build options.
  `THIN_HOST="${THIN_HOST:-no}"` lives here.
- `projects/ROCKNIX/devices/SM8550/options` — per-device options.
  Layer 14 leaves this untouched; the SM8550-only gate is enforced
  in `nix-integration/package.mk` via `[ "${PROJECT}" = "ROCKNIX" -a
  "${DEVICE}" = "SM8550" ]`.

### Institutional Learnings

- `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`
  — `/etc/profile`'s `PATH` reset was the original root cause behind
  the broad-bind unit's `/etc/profile` leak. Confirms why the Layer 14
  unit must NOT bind host `/etc/profile`.
- `docs/solutions/best-practices/stage-nspawn-rootfs-from-onboard-nix-closures-rocknix-2026-05-06.md`
  — proven pattern for staging the guest rootfs from already-resident
  Nix closures, avoids re-downloading on cold boot. Layer 14 reuses
  this exactly; the guest closure is already on-device after Tier B.
- `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
  — stale `/run/current-system` symlinks from previous boots cause
  guest activation to behave unpredictably. Confirms why Layer 14
  must seed `/run/current-system` from
  `/nix/var/nix/profiles/system` on every cold start, not assume
  persistence.

### External References

None. The patterns this plan needs (systemd-nspawn binding, NixOS
module composition, systemd target ordering, ROCKNIX build-flag
gating) are all in-tree with multiple direct examples.

### Origin Document Carry-Forward (Tier A–E findings)

All Tier A–E spikes documented in the brainstorm are constraints on
this plan, not work to redo. Specifically:
- E1 (20×20 fake-suspend): the guest is transparent to host fake-suspend.
  Layer 14 is allowed to depend on this; no separate per-cycle handoff
  is needed for sleep.
- E2 (rollback): proven; plan reuses gen-management as-is.
- E3 (cold boot): 11.3s + 2.1s = 13.4s baseline. Budget 15s.
- E4 (input): Strategy A confirmed — guest reads `event7`/`event8`,
  no `/dev/uinput` binding required for first cut.
- E5 (audio/BT): ownership flips cleanly via systemd socket-activation.
  Reclaim contract is feasible.

---

## Key Technical Decisions

- **Build a parallel image variant, not a fork**: same source tree,
  same kernel, same DT, gated by `THIN_HOST=yes` env var at build
  time. Reuses CI, reuses recovery flash story, two artifacts
  produced from one tree.
- **Recovery toggle via flag file + kernel cmdline (OR semantics)**:
  one mechanism (cmdline) survives a `/flash` filesystem corruption;
  the other (flag file) survives the absence of a serial-console /
  cmdline-edit path. Both should work; either succeeds.
- **`rocknix-recovery-toggle.service` is a oneshot before sysinit.target**:
  it runs `systemctl set-default <target>` based on the toggle state
  for that boot. Set-default is a symlink swap; idempotent and
  per-boot reversible.
- **Legacy userland stays installed, not started**: removing packages
  from the image breaks the recovery story. Disable via systemd
  Wants/After dependencies on the new target, not via
  `disable_service` in the image build.
- **Guest is the network owner; host has zero active network userland
  in `THIN_HOST=yes` mode**: confirmed by Tier C as the right shape.
  Shared netns means `wlan0` lives in the same namespace as the
  guest; the guest's NetworkManager (or iwd) drives it directly.
- **Tailscale fix encoded as a default in the system config store, not
  as a runtime workaround**: ROCKNIX's `099-networkservices` autostart
  layer is the supported channel. The build ships
  `tailscale.up=1` as a default in `system.cfg` so a fresh flash
  doesn't repeat the bug. Running devices already-configured stay
  unchanged.
- **`rocknix-guest@v2.service` (instanced, with `v2` literal name)**:
  versioning the unit name lets the broad-bind unit coexist on disk
  during transition without colliding. The `v2` is permanent — Layer
  15 will introduce v3 if needed; this plan does not delete v1.
- **Time zone is set in the guest config**: stops the recurring
  `tz-data.service` 203/EXEC noise observed during E2.
- **`/etc/resolv.conf` is owned declaratively by the guest's NixOS
  config**: stops the resolvconf clobber observed during E1/E5.
- **D-Bus on in the guest by default**: BlueZ, NetworkManager,
  PipeWire-pulse, and most modern services need it. No reason to
  defer.

---

## Open Questions

### Resolved During Planning

- **Where does the `THIN_HOST` flag live?**: `projects/ROCKNIX/options`
  with a `:-no` default; gated to SM8550-only inside the
  nix-integration `package.mk`.
- **Single network manager — NM or iwd?**: NetworkManager. iwd is what
  ROCKNIX uses today, but NM has saner declarative configuration for
  NixOS and the IWD PSK at `/storage/.cache/iwd/vrackie.psk` can be
  imported by NM via `nmcli connection import` during first boot.
- **InputPlumber: stay on host or move?**: stay on host (Strategy A).
  Defer Strategy B to Layer 14c.
- **How does the recovery override get cleared?**: the `/flash/rocknix.no-nspawn`
  flag file is *sticky* — only an explicit `rm` clears it. The
  `rocknix.safe=1` cmdline is per-boot only. This asymmetry is
  intentional: a stuck "I'm in recovery mode" state should require
  conscious action to exit.
- **What does the unit replacing the broad-bind unit do with `/storage`?**:
  bind only the explicit subdirectories the guest needs (`/storage/roms`
  read-only, `/storage/.cache/iwd` read-only initially, future
  guest-owned area read-write). No blanket `/storage` bind.

### Deferred to Implementation

- **Exact systemd target ordering** between `rocknix-recovery-toggle.service`,
  `rocknix-graphical.target`, `network.target`, and
  `local-fs.target`: needs to be tuned during U4 implementation
  against the actual cold-boot trace. Plan-time best guess is
  `Before=sysinit.target DefaultDependencies=no` for the toggle and
  `After=multi-user.target rocknix-automount.service` for the new
  graphical target.
- **Whether the watchdog reclaim runs from a `Restart=` policy on
  `rocknix-guest@v2.service` or from a separate
  `rocknix-host-reclaim.path` unit**: depends on systemd-nspawn
  exit-code semantics under different failure modes. Decide during
  U7 against real exits.
- **Final list of `/dev/tty*` nodes the guest needs for sway VT seat**:
  pick the smallest set that works; tune during U2 standalone soak.

---

## Output Structure

    projects/ROCKNIX/packages/tools/nix-integration/
    ├── package.mk                                   [modify]
    ├── docs/
    │   └── layer14-main-space-contract.md           [create]
    ├── system.d/
    │   ├── rocknix-guest@v2.service                 [create]
    │   ├── rocknix-recovery-toggle.service          [create]
    │   └── rocknix-graphical.target                 [create]
    ├── scripts/
    │   ├── rocknix-host-reclaim                     [create]
    │   └── rocknix-layer14-soak                     [create]
    ├── guest/
    │   ├── rocknix-guest.nix                        [modify]
    │   ├── modules/
    │   │   ├── display.nix                          [create]
    │   │   ├── audio.nix                            [create]
    │   │   └── network.nix                          [create]
    │   └── profiles/
    │       └── main-space.nix                       [create]
    └── tests/
        ├── nix-integration-static-checks.sh         [modify]
        └── nix-integration-runtime-smoke.sh         [modify]

    projects/ROCKNIX/options                         [modify — adds THIN_HOST]

    config/system.cfg.defaults                       [modify or create]
                                                     [encodes tailscale.up=1]

    Build artifact (no source path; produced by mkimage):
    target/ROCKNIX-SM8550-NIX-*.img.gz               [new build target]

    On-device file shipped in the image:
    /flash/HOW-TO-FALL-BACK.md                       [created during U9]

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance
> for review, not implementation specification. The implementing agent
> should treat it as context, not code to reproduce.*

### Boot decision tree

```mermaid
flowchart TD
    A[Power-on / kernel boot] --> B[sysinit.target]
    B --> C[rocknix-recovery-toggle.service]
    C --> D{flag file OR cmdline?}
    D -- "yes (recovery)" --> E[set-default graphical.target]
    D -- "no (normal)" --> F[set-default rocknix-graphical.target]
    E --> G[multi-user.target]
    F --> G
    G --> H{which default?}
    H -- "graphical.target" --> I[sway.service + essway.service<br/>(legacy ROCKNIX UI)]
    H -- "rocknix-graphical.target" --> J[rocknix-guest@v2.service<br/>(Nix main-space)]
    J --> K[guest sway, audio, network<br/>are the entire UI]
    I --> L[host SSH on :22 works]
    K --> L
```

### Build-flag fan-out

```text
THIN_HOST=no  (default, all devices)
  └── existing graphical.target wires sway+essway
  └── rocknix-guest@v2.service is INSTALLED but NOT enabled
  └── nix-integration package installs everything else as today

THIN_HOST=yes  (SM8550 only)
  └── rocknix-graphical.target is the systemd default target
  └── rocknix-guest@v2.service IS enabled (Wanted by new target)
  └── sway.service, essway.service, pipewire.service, etc. are
      installed but their [Install] section is masked from the new
      target — recovery target keeps them
  └── HOW-TO-FALL-BACK.md is generated into /flash/
  └── Image artifact name suffixed with `-NIX`
```

### Layer 14 unit shape (rocknix-guest@v2.service, sketch)

```ini
# directional shape only — not the literal unit file
[Unit]
Description=ROCKNIX Layer 14 guest (Nix main-space)
After=local-fs.target nix.mount network-pre.target
Requires=nix.mount
ConditionPathExists=/storage/machines/rocknix-guest

[Service]
Type=notify
NotifyAccess=all
ExecStartPre=/usr/bin/rocknix-layer14-prep   # seeds /run/current-system, etc.
ExecStart=/usr/bin/systemd-nspawn \
  --machine=rocknix-guest \
  --directory=/storage/machines/rocknix-guest \
  --network-veth=no  # share netns; do not isolate
  --bind=/dev/snd \
  --bind=/dev/rfkill \
  --bind=/dev/dri/card0 \
  --bind=/dev/dri/renderD128 \
  --bind=/dev/console \
  --bind-ro=/sys/class/backlight \
  --bind=/sys/class/leds \
  # ... full shopping list ...
  # NO bind of /usr, /lib, /etc/profile, /etc/resolv.conf,
  # /etc/ssh/authorized_keys.d
  --boot
WorkingDirectory=/storage/machines/rocknix-guest
Restart=on-failure
ExecStopPost=/usr/bin/rocknix-host-reclaim
WatchdogSec=30s

[Install]
WantedBy=rocknix-graphical.target
```

(Real unit will diverge during implementation — bind list is
authoritative-by-soak in U2, not authoritative-by-plan.)

---

## Implementation Units

### U1. Encode Tailscale auto-start fix as a build-time default

**Goal:** Ship a fresh-flash default of `tailscale.up=1` so the device
runs Tailscale on first cold boot, not after manual
`set_setting tailscale.up 1`. Same supported channel ROCKNIX already
uses for sshd/smbd/syncthing.

**Requirements:** R5

**Dependencies:** none

**Files:**
- Modify: `config/system.cfg.defaults` (or create if absent — locate
  the canonical defaults file via the existing `get_setting` /
  `set_setting` infrastructure during implementation; the fix lives
  there, not in `099-networkservices`)
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Find the file the image build uses to seed
  `/storage/.config/system/configs/system.cfg` on first boot. Add a
  `tailscale.up=1` line.
- If no such default-seeding mechanism exists today (the value got
  into the user's config some other way), add a oneshot service
  `rocknix-tailscale-default-on.service` that runs once on a fresh
  device (guarded by a flag file under `/storage`) and sets the
  config via the official `set_setting` API.
- Static check: greps the produced image for the default value.

**Patterns to follow:**
- The existing `099-networkservices` autostart and the pattern by
  which `sshd`, `smbd`, `syncthing` arrive at `=1` on a fresh flash.

**Test scenarios:**
- Happy path: fresh-flash simulation produces `system.cfg` containing
  `tailscale.up=1`.
- Edge case: existing user with `tailscale.up=0` is NOT overwritten
  on upgrade. (The default is for *fresh* installs only.)
- Integration: cold boot a fresh image, verify
  `systemctl show tailscaled -p ActiveEnterTimestampMonotonic` is
  non-zero and stays non-zero through the
  `099-networkservices` sweep.

**Verification:**
- Static check passes.
- A flashed-from-fresh device shows `tailscaled` active 30s after
  cold boot without any manual setup.

---

### U2. Layer 14 nspawn unit (`rocknix-guest@v2.service`)

**Goal:** Replace the experimental broad-bind unit with a clean,
shopping-list-applied nspawn unit. The `v2` is part of the unit name
permanently — both units coexist on disk during transition.

**Requirements:** R1, R10, R11

**Dependencies:** none (can land before the build flag)

**Execution note:** Characterization-first. Before changing any binds,
write the static check that asserts the unit's bind list matches the
shopping list verbatim. The unit is then built to satisfy the check.

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest@v2.service`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-layer14-prep`
  (ExecStartPre helper that seeds `/run/current-system`,
  `/run/booted-system`, `/etc/resolv.conf` ownership marker)
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
  (install the new unit + prep script; do NOT enable it yet)
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
  (assert bind list matches the shopping list, assert no host-pollution
  binds present, assert WorkingDirectory set)
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Bind list: `/dev/snd`, `/dev/rfkill`, `/dev/dri/card0`,
  `/dev/dri/renderD128`, `/dev/console`, `/dev/tty0..N` (smallest
  working set; tune in soak), `/sys/class/backlight` (RW),
  `/sys/class/leds` (RW), `/sys/class/devfreq` (RW for governor),
  `/sys/devices/system/cpu/cpufreq` (RW), `/storage/roms` (RO),
  guest-owned area under `/storage` (RW).
- Forbidden binds (asserted by static check): `/usr`, `/lib`,
  `/etc/profile`, `/etc/resolv.conf`, `/etc/ssh/authorized_keys.d`,
  blanket `/storage`.
- Network: `--network-veth=no` (share host netns; Tier C confirmed
  this is the right shape for main-space).
- ExecStartPre runs `rocknix-layer14-prep` which:
  - Seeds `/run/current-system` from
    `/nix/var/nix/profiles/system` if missing (E3 finding).
  - Seeds `/run/booted-system` symlink.
  - Touches an `/etc/resolv.conf.layer14-owned` flag inside the
    rootfs so the resolvconf-clobber detection works in soak.
- `Restart=on-failure`, `WatchdogSec=30s`.

**Patterns to follow:**
- Existing `nix-storage-setup.service` for the prep-script pattern.
- Existing systemd unit headers in `system.d/`.

**Test scenarios:**
- Happy path: `systemctl start rocknix-guest@v2.service` on existing
  device → guest namespace reachable via `nsenter`, `sway` not
  fighting, no DNS bleed under 1 hour load.
- Edge case: ExecStartPre runs on a guest with stale
  `/run/current-system` from a previous boot — symlink is
  re-pointed cleanly without fighting a running process.
- Error path: rootfs missing → `ConditionPathExists=` keeps unit in
  `inactive` state without spamming the journal.
- Integration: kill the guest with SIGKILL → `ExecStopPost=` runs
  `rocknix-host-reclaim` (U7) and host pipewire+sway+essway
  restart within 5s.
- Static check: greps the unit file for forbidden bind paths;
  greps for required bind paths; asserts `WorkingDirectory=` set.

**Verification:**
- Static check passes.
- Standalone start of v2 unit on existing image runs cleanly for ≥1h
  with sway and audio inside the guest, no host pollution observed
  (no `/usr` leaked, no Mesa store-path mismatch, no resolvconf
  clobber).
- Soak harness (U8) accepts the unit.

---

### U3. Guest NixOS module set: display + audio + network

**Goal:** Extend the guest closure to provide the userspace stack the
main-space needs — sway with Mesa freedreno/turnip, pipewire +
wireplumber, NetworkManager, BlueZ + dbus, time zone, declarative
`/etc/resolv.conf`.

**Requirements:** R1, R4

**Dependencies:** U2 (the unit must exist before its closure has a
real consumer)

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/modules/display.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/modules/audio.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/modules/network.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/main-space.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/rocknix-guest.nix`
  (composes the three new modules under the new profile)
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix`
  (expose `nixosConfigurations.rocknix-guest-main-space`)
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- `display.nix`: `services.xserver = {};` (no), instead wayland-only.
  `programs.sway.enable = true;`, `hardware.graphics.enable = true;`,
  `hardware.graphics.extraPackages = [ mesa ]` with freedreno/turnip
  driver path. `environment.systemPackages = [ foot swaybg ]`. Set
  `WLR_LIBINPUT_NO_DEVICES=0` in the new clean unit (the workaround
  was specific to the broad-bind unit's host-libinput conflict).
- `audio.nix`: `services.pipewire.enable = true;
  services.pipewire.alsa.enable = true; services.pipewire.pulse.enable
  = true;`. `services.dbus.enable = true;`.
  `hardware.bluetooth.enable = true;` (BlueZ +
  bluetooth-related D-Bus).
- `network.nix`: `networking.networkmanager.enable = true;`.
  Declarative `networking.networkmanager.connections` seeded from the
  existing IWD PSK at `/storage/.cache/iwd/vrackie.psk` via an
  ExecStartPre that converts on first boot. `networking.resolvconf.enable
  = false; networking.networkmanager.dns = "default";`.
  `networking.firewall.enable = true;` (uses nftables — kernel lacks
  ip_tables.ko per origin constraint).
- `main-space.nix` profile: imports the three modules, sets
  `time.timeZone = "America/New_York";` (or whatever the user's
  current host setting is — read from
  `/storage/.config/system/configs/system.cfg` during build), sets
  hostname to `rocknix-nix`, enables openssh on a non-22 port per
  Layer 12 contract.
- Two paths in `flake.nix`: `rocknix-guest` (legacy minimal, for
  Layer 13) and `rocknix-guest-main-space` (Layer 14).

**Patterns to follow:**
- Existing `guest/profiles/{minimal,ssh}.nix` profile composition.
- Existing `guest/modules/{base,ssh,tools}.nix` module structure.

**Test scenarios:**
- Happy path: `nix flake check` against
  `rocknix-guest-main-space` passes.
- Happy path: `nix build .#nixosConfigurations.rocknix-guest-main-space.config.system.build.toplevel`
  produces a closure under 4GB.
- Edge case: `time.timeZone` left unset → build fails with a
  `assertion failed` instead of producing an image that spits 203/EXEC
  at runtime. (Catch the E2 issue at build time.)
- Edge case: `networking.firewall` configured with iptables rules →
  build fails (iptables not available; nftables only).
- Integration: closure built from this profile, dropped into
  `/storage/machines/rocknix-guest`, started by U2's unit, runs
  sway from guest closure, network up, audio up, BT up.

**Verification:**
- `nix flake check` clean.
- Closure builds successfully.
- Guest started against this closure passes the same Tier B / Tier E5
  spike checks (sway DRM master, pipewire pcmC0D0p, hci0 UP).

---

### U4. Recovery toggle service (`rocknix-recovery-toggle.service`)

**Goal:** Per-boot recovery override. A oneshot that runs
before-sysinit, inspects the toggle state, and calls `systemctl
set-default` accordingly.

**Requirements:** R3, R9

**Dependencies:** none

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-recovery-toggle.service`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
  (install + enable the unit unconditionally — it's a no-op when
  THIN_HOST=no since `rocknix-graphical.target` won't exist then)
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Type=oneshot, `Before=sysinit.target`,
  `DefaultDependencies=no`, `ConditionPathExists=|/flash/rocknix.no-nspawn`
  + cmdline check (use `/usr/bin/grep` against `/proc/cmdline` since
  ConditionKernelCommandLine doesn't support arbitrary key=value).
- Shell logic:
  ```text
  if [ -f /flash/rocknix.no-nspawn ] || grep -q -E '(^| )rocknix\.safe=1( |$)' /proc/cmdline; then
    systemctl set-default graphical.target
  else
    systemctl set-default rocknix-graphical.target
  fi
  ```
- Idempotent: setting the default twice is a symlink swap; safe.

**Patterns to follow:**
- Existing oneshot units in `system.d/` like `nix-storage-setup.service`.
- Boot-time flag-file pattern at `/flash/` (used by ROCKNIX for
  several existing recovery-style markers).

**Test scenarios:**
- Happy path (no toggles): unit sets default to
  `rocknix-graphical.target`. Booted in normal mode.
- Happy path (flag file present): unit sets default to
  `graphical.target`. Booted in recovery mode.
- Happy path (cmdline `rocknix.safe=1`): unit sets default to
  `graphical.target`.
- Edge case: both toggles present → recovery (OR semantics).
- Edge case: flag file is a directory, not a regular file →
  `[ -f ]` returns false, normal mode (intentional — only regular
  files trigger).
- Edge case: legacy image where `rocknix-graphical.target` doesn't
  exist (THIN_HOST=no) → toggle still runs without erroring,
  set-default to `graphical.target` is a no-op-ish.
- Static check: unit exists at expected path, has correct ordering.

**Verification:**
- Static check passes.
- On Thor (after U2 + U3 + U6 land but before flipping
  THIN_HOST=yes), can `touch /flash/rocknix.no-nspawn`, reboot,
  observe the toggle log line, observe legacy boot. Then `rm` the
  flag, reboot, observe normal boot.

---

### U5. New systemd target (`rocknix-graphical.target`)

**Goal:** A target that *is* the Nix main-space. Wants the guest unit;
nothing else.

**Requirements:** R1, R2

**Dependencies:** U2

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-graphical.target`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
  (install the target unconditionally, but only enabled by U6's
  build-flag path)
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- `[Unit] Description=ROCKNIX Nix main-space (Layer 14)
   Requires=multi-user.target rocknix-automount.service
   After=multi-user.target rocknix-automount.service network-online.target
   Wants=rocknix-guest@v2.service
   AllowIsolate=yes`
- Listed in `[Install] Alias=default.target` ONLY when `THIN_HOST=yes`
  build (handled by U6).

**Patterns to follow:**
- Standard `systemd.target` semantics (graphical.target is the model).

**Test scenarios:**
- Happy path: `systemctl isolate rocknix-graphical.target` on a
  THIN_HOST=yes image starts the guest unit and reaches the target.
- Edge case: target installed on a THIN_HOST=no image — exists on
  disk but is not Wanted; does nothing on boot.
- Static check: target file syntactically valid, has expected Wants.

**Verification:**
- `systemd-analyze verify` clean.
- Static check passes.

---

### U6. `THIN_HOST` build flag

**Goal:** One-knob control for the parallel image variant. Default off;
on requires `DEVICE=SM8550`.

**Requirements:** R2, R7

**Dependencies:** U2, U3, U4, U5

**Files:**
- Modify: `projects/ROCKNIX/options` (add
  `THIN_HOST="${THIN_HOST:-no}"` near `NIX_INTEGRATION_SUPPORT`)
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
  (when `THIN_HOST=yes` AND `DEVICE=SM8550`: enable
  `rocknix-guest@v2.service`, install `rocknix-graphical.target`'s
  Alias=default.target dropin, mask sway/essway/pipewire/wireplumber/
  bluetooth/connman/iwd/wpa_supplicant in the new target's chain
  via `[Install] WantedBy=` removal — they remain installed)
- Modify: `projects/ROCKNIX/packages/virtual/image/package.mk` (if
  the artifact name needs an `-NIX` suffix when THIN_HOST=yes — only
  if there's a clean place to thread the variable through; otherwise
  use the existing image-naming convention and document)
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Hard guard inside `package.mk`: `if [ "${THIN_HOST}" = "yes" ] &&
  [ "${DEVICE}" != "SM8550" ]; then echo "THIN_HOST=yes is SM8550-only";
  exit 1; fi`
- Two image artifacts produced from one tree: the build invocations
  differ only in the env var.
- Default-target swap: with `THIN_HOST=yes`, the recovery-toggle
  service (U4) routes to `rocknix-graphical.target`; without it, the
  toggle still runs but `rocknix-graphical.target` isn't enabled and
  the toggle's set-default to it would fail — so the toggle's "normal
  mode" branch is a no-op when the target doesn't exist. This means
  `rocknix-graphical.target` MUST exist on disk only when
  `THIN_HOST=yes`.

**Patterns to follow:**
- `NIX_INTEGRATION_SUPPORT` and `NIX_DAEMON_SUPPORT` patterns in
  `projects/ROCKNIX/options` and `package.mk`.

**Test scenarios:**
- Happy path (`THIN_HOST=no`, any device): build produces the same
  artifact today's build produces. No new files in the rootfs except
  inert ones (the new unit, prep script, recovery-toggle service —
  all installed but not enabled in a way that changes default boot).
- Happy path (`THIN_HOST=yes`, `DEVICE=SM8550`): build produces the
  parallel artifact. `rocknix-guest@v2.service` is enabled.
  `rocknix-graphical.target` is installed and is the default target.
- Error path (`THIN_HOST=yes`, `DEVICE=anything-else`): build fails
  with a clear "SM8550-only" error.
- Edge case: rebuilding `THIN_HOST=yes` then `THIN_HOST=no` produces
  identical output to a fresh `THIN_HOST=no` build (no leftover
  artifacts).
- Static check: `THIN_HOST=no` rootfs grep returns no
  `rocknix-graphical.target` in `default.target`.

**Verification:**
- Two artifacts build cleanly.
- Static check passes for both.
- A `THIN_HOST=yes` artifact, when fastboot'd to a test slot on Thor,
  boots into the guest UI within 15s.

---

### U7. Host reclaim contract (`rocknix-host-reclaim`)

**Goal:** When the guest exits unexpectedly under `THIN_HOST=yes`,
fall back to the host's installed-but-not-running userland so the
device stays usable until the next boot.

**Requirements:** R1 (reclaim contract), AE3

**Dependencies:** U2

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-host-reclaim`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
  (install + chmod 0755)
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest@v2.service`
  (`ExecStopPost=/usr/bin/rocknix-host-reclaim` already wired in U2;
  the script lands here)
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
  (extend with reclaim-path coverage when running on THIN_HOST=yes
  hardware; gated by `[ "${RECLAIM_TEST}" = "yes" ]` env var so it's
  opt-in)

**Approach:**
- Pure shell, no Nix dependencies (must run when guest is ungone).
- Logic:
  ```text
  if [ "${EXIT_CODE}" = "0" ] || [ "${EXIT_STATUS}" = "killed" ]; then
    # graceful stop or admin kill — do not auto-reclaim
    log "guest stopped cleanly; reclaim skipped"; exit 0
  fi
  log "guest exited unexpectedly; starting host fallback"
  systemctl start sway essway pipewire.socket pipewire-pulse.socket \
                  wireplumber bluetooth inputplumber
  ```
- Use systemd's `ExecStopPost` env vars (`$EXIT_CODE`, `$EXIT_STATUS`)
  to distinguish graceful vs crash exits.
- Log to `/var/log/rocknix-host-reclaim.log` with timestamps.

**Patterns to follow:**
- Existing fallback/recovery shell-script pattern under
  `projects/ROCKNIX/packages/rocknix/sources/scripts/`.

**Test scenarios:**
- Happy path: guest crashes (`pkill -9 systemd-nspawn`), reclaim runs,
  host services come up within 5s.
- Edge case: graceful stop (`systemctl stop rocknix-guest@v2.service`)
  → reclaim does NOT run.
- Edge case: reclaim invoked with no host services installed (should
  not happen in THIN_HOST=yes since host services are still on disk,
  but defensive) — fails open with a clear log line.
- Integration: reclaim runs, SSH to thor:22 still works, EmulationStation
  reachable on display.

**Verification:**
- Runtime smoke harness exercises the reclaim path on real hardware.
- Manual: induce a crash; observe within 5s the device shows the
  legacy ROCKNIX UI without rebooting.

---

### U8. Standalone soak harness (`rocknix-layer14-soak`)

**Goal:** A 24-hour automated soak of `rocknix-guest@v2.service`
running alongside the legacy host UI on the existing image, BEFORE
flipping `THIN_HOST=yes`. Catches regressions cheaply, gates the
swing.

**Requirements:** R6

**Dependencies:** U2, U3 (enough to start the guest, not yet tied
to the build flag)

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-layer14-soak`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-soak-checklist.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
  (install + chmod 0755)
- Test: the soak harness IS the test; runs against real hardware.

**Approach:**
- Hourly checks, logged to `/var/log/layer14-soak.log`:
  - `/etc/resolv.conf` inside guest is unchanged (no DNS bleed).
  - `/run/current-system` inside guest still resolves.
  - No host `/usr` paths in guest's `PATH` or
    `LD_LIBRARY_PATH`.
  - Guest sway is alive (poll `pgrep -f` inside namespace).
  - Guest pipewire is alive.
  - Host `essway` still alive.
  - Host SSH on :22 responsive (`ssh -o BatchMode=yes
    root@localhost true`).
  - Memory not monotonically growing (sample
    `/proc/meminfo` MemAvailable; alarm if it drops > 200MB
    over the run).
- 24h runtime (configurable via `--hours N`).
- Pass criteria: zero alarms across 24 hourly checks.
- Fail criteria: any alarm; harness exits 1 with the failing check
  named.
- Checklist doc names the 8 pass criteria explicitly so a reviewer
  can sign off without reading the script.

**Patterns to follow:**
- Existing `e1-suspend-cycle.sh` pattern from Tier E1
  (per-cycle log, summary log).
- Existing test-runner shape in `tests/`.

**Test scenarios:**
- Happy path: harness runs for 24h on an existing
  (THIN_HOST=no, but with U2 unit started by hand) device → exits 0.
- Error path: harness detects DNS bleed on hour 4 → exits 1, log
  names "resolv.conf clobbered at $TIMESTAMP, was $WAS, now $NOW".
- Error path: harness detects host SSH unreachable → exits 1.
- Edge case: harness Ctrl-C'd partway → leaves a partial log marked
  "INTERRUPTED at hour N".

**Verification:**
- Harness exists and passes static checks.
- One full 24h soak on Thor passes before U6 is flipped.
- Soak log archived in `/storage/layer14-soak-runs/` with
  date-stamped filename.

---

### U9. Recovery documentation (`/flash/HOW-TO-FALL-BACK.md`)

**Goal:** A README in `/flash/` explaining the recovery toggle, readable
from a card reader / teardown without booting the device. Required so
future-you (or future-someone) can fall back even with no SSH.

**Requirements:** R9

**Dependencies:** U4 (toggle exists)

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/docs/HOW-TO-FALL-BACK.md`
- Modify: `projects/ROCKNIX/packages/virtual/image/package.mk` (or
  the appropriate image-construction step) to copy the doc into
  `/flash/HOW-TO-FALL-BACK.md` of both image variants

**Approach:**
- Plain markdown, no fluff. Sections:
  1. What this image is (`THIN_HOST=yes` vs `=no`, how to tell).
  2. Symptoms of guest failure (black screen for >30s, no
     SSH, no display).
  3. How to recover (mount `/flash` from a card reader; `touch
     rocknix.no-nspawn`; eject; reboot device).
  4. Alternative recovery via U-Boot edit cmdline
     (`rocknix.safe=1`) — instructions per device.
  5. How to confirm you're in recovery mode (sway = old, no nspawn
     in `ps`).
  6. How to exit recovery mode (`rm /flash/rocknix.no-nspawn`,
     reboot).
  7. Where to find logs after a failure (`/var/log/`,
     `journalctl -b -1`).
- Keep it ≤ 2 printed pages.

**Patterns to follow:**
- Existing `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
  voice and structure.

**Test scenarios:**
- Test expectation: documentation only — no automated test, but
  static check verifies the doc exists at the expected path in both
  image variants.

**Verification:**
- File present in `/flash/` of a test-built image.
- A real human reading it for the first time can describe the
  recovery procedure back without re-reading.

---

### U10. Layer 14 contract doc

**Goal:** Capture the Layer 14 contract in the existing layer-contract
series, parallel to `layer13-modules-contract.md`. Documents the
interface, not the implementation.

**Requirements:** R1–R11 (all)

**Dependencies:** U2–U9 (the contract describes what they do)

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md`

**Approach:**
- Same shape as the existing layer NN contract docs.
- Sections: Goal, Scope, Build flag, Boot decision tree, Recovery
  contract, Reclaim contract, Soak gate, Hardware scope, Out of
  scope.
- Cross-link the brainstorm doc and this plan as origins.

**Patterns to follow:**
- `layer13-modules-contract.md`,
  `layer12-guest-ssh-contract.md`,
  `layer10-guest-lifecycle-contract.md`.

**Test scenarios:**
- Test expectation: documentation only.

**Verification:**
- Doc exists, links resolve.

---

## System-Wide Impact

- **Interaction graph:** the new units sit at the systemd target
  layer (`rocknix-graphical.target` is a peer of `graphical.target`).
  The recovery-toggle service runs once per boot before sysinit and
  flips a symlink. The reclaim script runs as
  `ExecStopPost=` of the guest unit. Existing services (sway, essway,
  pipewire, etc.) are *not modified*; they're just not Wanted by the
  new target.
- **Error propagation:** guest crash → `ExecStopPost=` reclaim →
  legacy userland comes up. If reclaim itself fails, the device
  stays bricked-in-userspace until next reboot, where the recovery
  toggle (manually invoked via flag file or cmdline) resolves it.
  No fully-bricked state without physical access to the SD card.
- **State lifecycle risks:** `/run/current-system` not seeded on
  cold boot is now caught by `rocknix-layer14-prep` (E3 finding
  internalized). Stale generations can accumulate; encode a
  monthly GC suggestion in HOW-TO-FALL-BACK.md but don't auto-GC.
- **API surface parity:** `nixctl` and `nix-doctor` (existing scripts)
  must continue to work in both modes. They already read
  `/run/current-system`; nothing breaks.
- **Integration coverage:** the soak harness (U8) is the integration
  surface that the unit + module set + reclaim contract are all
  proven against together before flipping the build flag.
- **Unchanged invariants:**
  - Host SSH on `root@thor:22` (R11).
  - Kernel, DT, bootloader (R12).
  - `/storage` layout and on-disk content (R10).
  - `/usr` content of the host image (legacy userland still installed,
    just not always started).
  - Behavior on non-SM8550 devices (R7).

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Layer 14 unit has a subtle bind-list bug that doesn't surface in soak but does in 24/7 daily-driving | The 14-day live-in is the explicit gate; recovery toggle is the safety net during it. Daily journal note captures what surfaces. |
| Recovery toggle itself has a bug that prevents fallback | U4 verification step exercises the toggle on Thor (touch flag, reboot, observe legacy boot, `rm` flag, reboot) BEFORE flipping `THIN_HOST=yes`. |
| `THIN_HOST=yes` build accidentally breaks `THIN_HOST=no` build for other devices | U6 hard guard plus static check that asserts `THIN_HOST=no` rootfs is byte-equivalent to today's rootfs (modulo the new but-disabled units). Run the existing CI for non-SM8550 devices. |
| Tailscale fix encoded as a default doesn't take on existing flashed devices | The fix is documented as one-time-per-device on already-deployed units (`set_setting tailscale.up 1`). Build-time default only matters for fresh flashes. |
| Guest closure rebuild breaks the Mesa/Vulkan stack (regression on Tier B) | U3 includes a runtime smoke that attempts a Vulkan device init from inside the guest (vulkaninfo). |
| Suspend regression — Tier E1 was 20×20 on the broad-bind unit; the new unit may behave differently | Re-run a 20×20 fake-suspend cycle on the new unit during the U8 soak (it's one of the 8 hourly checks: confirm DPMS off→on transition cleared between samples). |
| `ExecStopPost=` reclaim doesn't fire on certain failure modes (e.g. systemd-nspawn segfault) | U7 tests both graceful-stop and SIGKILL paths. If a third mode shows up in soak, add coverage. |
| `/dev/dri/card0` ownership conflict between host and guest after reclaim | Reclaim explicitly stops the guest's nspawn before starting host sway. The DRM master is released on guest exit (proven in Tier B teardown). |
| Cold-boot regression > 15s budget | U6's verification step measures cold boot. If over budget, profile `rocknix-autostart.service` (5.2s of today's userspace) — most of what it does becomes unnecessary in THIN_HOST=yes. |
| Loss of TS during recovery mode (recovery uses legacy userland which had this bug) | U1 fix applies to both modes — defaults are at the system.cfg layer, not gated by THIN_HOST. |

---

## Phased Delivery

### Phase 1: Build & install (U1, U2, U3, U4, U5, U7, U9, U10)

Land the artifacts. Nothing is wired to default boot yet.
`THIN_HOST=no` builds are byte-equivalent to today's (modulo new
inert files).

### Phase 2: Standalone soak (U8)

Run the 24h soak on Thor with the new v2 unit started manually.
Existing image, no flag flip. Pass = green-light Phase 3.

### Phase 3: Build flag (U6)

Add the `THIN_HOST` flag. Build both artifacts. Static checks +
build-time tests pass.

### Phase 4: Recovery rehearsal (verification of U4 on real Thor)

Before any `THIN_HOST=yes` flash: on the existing
(`THIN_HOST=no`) image with U4 installed, exercise the toggle
manually. `touch /flash/rocknix.no-nspawn`; reboot; observe legacy
boot (it'll be the same legacy boot since THIN_HOST=no, but the
`set-default` log line confirms toggle ran). `rm` the flag; reboot;
normal boot.

### Phase 5: Flash & live-in (operational, not implementation)

Flash `THIN_HOST=yes` to Thor. Daily-drive 14 days. Daily one-line
journal entry: what worked, what broke, did recovery activate. After
14 days clean, the architecture is proven.

### Phase 6: Odin 2 Portal (deferred to Layer 14b plan)

Repeat the validation pass on Odin 2 Portal.

---

## Documentation Plan

- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md` (U10)
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-soak-checklist.md` (U8)
- `projects/ROCKNIX/packages/tools/nix-integration/docs/HOW-TO-FALL-BACK.md` (U9, also shipped to `/flash/`)
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
  — append a Layer 14 section linking to the contract.
- `docs/solutions/best-practices/` — capture the
  `THIN_HOST=yes` build-flag pattern as a reusable best-practice
  doc after Phase 5 succeeds.

---

## Operational / Rollout Notes

- **Backup before flashing:** snapshot `/storage` (or at least
  `/storage/.cache`, `/storage/roms`, `/storage/.config`) to a
  laptop before the first `THIN_HOST=yes` flash. Restore is `rsync`
  back; the new image leaves `/storage` alone but a backup is cheap
  insurance.
- **Disk budget:** Tier E2 measured the guest closure at 1.28 GB
  reachable. Plan ~2GB headroom per retained generation. Layer 14
  ships with a single generation; users grow generations as they
  rebuild.
- **Watch the daily journal:** the 14-day live-in is explicit; capture
  one line per day even if "everything fine". The journal is the
  artifact that proves daily-driver readiness.
- **Don't release publicly until Phase 6 is also clean.** Public
  release is Layer 15 work.

---

## Sources & References

- **Origin document:** `docs/brainstorms/2026-05-07-002-rocknix-thin-host-nix-main-space.md`
  (Tier A–E findings, shopping list, recovery contract, feasibility
  odds)
- Related plans:
  - `docs/plans/2026-05-07-002-feat-rocknix-declarative-modules-plan.md` (Layer 13, predecessor)
  - `docs/plans/2026-05-06-003-feat-nix-layer-10b-bootable-rootfs-plan.md` (rootfs staging)
  - `docs/plans/2026-05-06-004-feat-nix-layer-12-opt-in-guest-ssh-plan.md` (guest SSH contract)
- Related solutions:
  - `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`
  - `docs/solutions/best-practices/stage-nspawn-rootfs-from-onboard-nix-closures-rocknix-2026-05-06.md`
  - `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
- Conversation branch (Tailscale autostart fix):
  conversation summary; resolution via
  `set_setting tailscale.up 1` against
  `/storage/.config/system/configs/system.cfg`. Encoded into U1.
