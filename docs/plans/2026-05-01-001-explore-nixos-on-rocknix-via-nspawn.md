---
title: explore: NixOS on ROCKNIX via systemd-nspawn (Layer 9 candidate)
type: explore
status: captured
date: 2026-05-01
---

# explore: NixOS on ROCKNIX via systemd-nspawn

This document captures a design conversation about whether and how to run real
NixOS on ROCKNIX without losing the appliance behavior or game performance the
device is built for. It is intended as a forward-looking sibling to the
existing layered-Nix plan, not a commitment to implement. Treat it as Layer 9
candidate analysis.

## Question being explored

Given that the current Nix experiment is intentionally additive (Layers 0-8
keep ROCKNIX as the base OS and layer Nix on top), is it possible -- even at
runtime only -- to get the device to run NixOS itself? The user prompt
explicitly opened the door to runtime-only approaches such as `nixos-anywhere`.

## One-paragraph answer

The kernel side is unexpectedly hospitable. The vendor stack and the appliance
contract are what make full-replacement NixOS expensive and not obviously
worth it. Of the four credible paths, running a real NixOS userspace inside a
`systemd-nspawn` container on ROCKNIX is the one that gives "real NixOS on the
device" without giving back what ROCKNIX is good at. With cgroup limits, CPU
pinning to efficiency cores, and a freeze-during-gameplay hook, the design
target of "no measurable effect on game performance" is achievable and
measurable.

## Kernel evidence (SM8550 / Odin2 Portal)

From `projects/ROCKNIX/devices/SM8550/linux/linux.aarch64.conf`:

```
CONFIG_USER_NS=y      CONFIG_PID_NS=y    CONFIG_NET_NS=y
CONFIG_SECCOMP=y      CONFIG_SECCOMP_FILTER=y
CONFIG_KEXEC=y        CONFIG_KEXEC_FILE=y    # KEXEC_SIG not set
CONFIG_KVM=y          CONFIG_KVM_MMIO=y      CONFIG_KVM_VFIO=y
CONFIG_VIRTIO_*=y     CONFIG_BINFMT_MISC=y
CONFIG_CGROUPS=y      (full set: pids, freezer, devices, cpuacct, bpf, ...)
CONFIG_BPF_SYSCALL=y  CONFIG_OVERLAY_FS,SQUASHFS,FUSE
```

Implications:

- Full namespace + cgroup support means container-style approaches work.
- `KEXEC=y` with no signature gate means `nixos-anywhere`-style kexec is
  technically possible.
- `KVM=y` with `VFIO` means a NixOS VM is possible.
- The `/proc/self/setgroups` failure observed during the nix-portable POC is
  likely a **runtime** restriction (sysctl or unprivileged userns policy),
  not a kernel-config restriction. Worth re-investigating, because if
  unprivileged user namespaces are usable, several doors open and the proot
  performance penalty in Layers 1-2 could be dropped entirely.

## ROCKNIX-side evidence

From `packages/sysutils/systemd/package.mk`:

- `-Dmachined=false -Dportabled=false -Dnetworkd=false -Dimportd=disabled` at
  meson-config time. So machined and friends are not built.
- No `-Dnspawn=false`, so `systemd-nspawn` **is built**.
- `post_install()` then explicitly removes the nspawn binary and unit:

  ```sh
  safe_remove ${INSTALL}/usr/bin/systemd-nspawn
  safe_remove ${INSTALL}/usr/lib/systemd/system/systemd-nspawn@.service
  ```

The cheapest path to having nspawn on the device is to drop those two
`safe_remove` lines on the `custom` branch and rebuild. nspawn does not need
machined to run -- `machinectl` is just the management UI. Standalone
`systemd-nspawn -bD /path/to/rootfs` works without it.

There is also a `packages/addons/service/podman/package.mk` Kodi-addon-style
packaging of Podman + runc + conmon + netavark from LibreELEC days, so
"container runtime on a read-only appliance distro" already has a paved road
in this codebase as a fallback if the systemd patch is rejected upstream.

## The four credible paths

Ranked by realism on this device.

### Path 1 -- NixOS in `systemd-nspawn` on `/storage` (recommended)

Real NixOS userspace, real NixOS systemd as PID 1 inside the guest, real
`nixos-rebuild switch` inside, real `nix-daemon` with sandboxed builds inside.
ROCKNIX kernel + drivers + firmware + Sway/EmulationStation untouched.

Pros:
- Zero boot risk. Reversible by `rm -rf` plus disabling a unit.
- Shares the host kernel, so all SM8550 vendor work just works.
- Two systemds do not collide because each owns its own namespace.
- Composes cleanly with Layer 3: a single `/storage/.nix-root` can be the
  shared `/nix` for both host nix-portable and guest NixOS.
- Demolishes Layers 4 and 8 by reframing them. Standard Nix and `nix-daemon`
  "just work" inside the guest with no porting.

Cons:
- GPU/Wayland passthrough into nspawn is fragile. Fine for headless / CLI /
  service workloads; needs care for graphical apps.
- Audio/PipeWire passthrough is the same shape -- doable but each passthrough
  is one more thing that breaks on host upgrades.
- nspawn binary needs to be added back to the ROCKNIX image.
- machined removal means no `machinectl shell <name>`; use `nsenter` or run
  guests as plain `.service` units.

### Path 2 -- NixOS userspace, ROCKNIX kernel (pivot_root style)

Generate a NixOS system closure on `/storage/nixos-system`, then `pivot_root`
into it post-boot, or bind-mount NixOS-managed paths over a stub `/etc`.

Pros:
- One real NixOS on the device.
- Avoids container ergonomics for graphical apps.

Cons:
- Two systemds collide. Switching to NixOS systemd loses ROCKNIX-patched
  units (the `/storage/.config/system.d` redirect, EmulationStation startup
  chain, fake-suspend, joypad init order, etc.). You would re-implement
  ROCKNIX's UI startup as NixOS modules.
- Stops being additive. Crosses the boundary explicitly drawn in plan
  requirement R6 ("avoid committing to NixOS-like control of the base OS").

### Path 3 -- NixOS in a KVM guest

`KVM=y` + `VFIO` are on. Run aarch64 NixOS as a QEMU/KVM guest.

Pros: strongest isolation; rollback is "delete the disk image."

Cons: RAM cost on a handheld; GPU passthrough on Adreno is not paved; useful
for headless services and build hosts but not gameplay-adjacent workloads.

### Path 4 -- nixos-anywhere / kexec replacement

Mechanically possible: `KEXEC=y`, `KEXEC_FILE=y`, no signature gate, so kexec
into a generic aarch64 NixOS installer kernel works.

Then the wheels come off:
- Bootloader: ROCKNIX uses `BOOTLOADER="qcom-abl"` (Android Bootloader,
  boot.img packaging, A/B slots). NixOS expects systemd-boot / grub / extlinux.
  A custom NixOS module to produce qcom-abl boot.img is doable but bespoke.
- Drivers: SM8550 needs DTBs, firmware blobs, `rocknix-joypad`,
  panel-generic-dsi tweaks, `rocknix-fake-suspend`, GPU display quirks,
  `rocknix-abl` for A/B slot updates. Mainline NixOS will boot with most of
  these in various states of broken. Re-porting them is a project on the
  scale of ROCKNIX itself.

Net: you would get a worse handheld and inherit responsibility for the vendor
work that ROCKNIX exists to provide. The value ROCKNIX gives you *is* that
work.

A non-destructive use of kexec is still interesting: kexec into a vanilla
NixOS-installer kernel from a running ROCKNIX, observe which Odin2 hardware
lights up under mainline drivers, then `reboot` back. Cheap evidence-gathering
before deciding whether Path 4 is worth pursuing. Not a deliverable.

## Why nspawn is the architectural fit

- It is namespaces + cgroups, not virtualization. No vmexit overhead, no
  binary translation, no virtio queues.
- Idle nspawn cost is essentially zero CPU and ~30-80 MB resident.
- Cgroup v2 freeze is essentially free and instant. Resume preserves all
  state including open SSH sessions.
- Each guest has its own systemd; ROCKNIX's trimmed/patched systemd stays in
  charge of the appliance.
- `boot.isContainer = true` in NixOS makes a guest-shaped system that
  expects to be run by nspawn (skips kernel/bootloader/fstab generation).

## Game-performance design rule

> **Default state of the guest: frozen during play, low-priority and
> efficiency-core-only when not. Anything outside that envelope is opt-in,
> manual, and out of the game's path.**

This is the load-bearing constraint. If it holds, "does Nix on ROCKNIX hurt
game performance?" is structurally answerable as "no, and here are the
measurements."

### What actually moves frame rate on SM8550

In rough order of impact:

1. CPU contention on prime/perf cores (emulators want hot threads pinned).
2. eMMC/UFS I/O contention with shader caches and saves on `/storage`.
3. Memory bandwidth + thermal -- SM8550 throttles aggressively, raising
   package temp costs sustained GPU clock.
4. Memory pressure -- once the game's page cache evicts, hitches.
5. Scheduler jitter from RT or high-priority background work.
6. IRQ/kernel hot paths (seccomp, BPF). nspawn's syscall filter applies to
   the *guest's* syscalls, not the host's. Game pays nothing for it.

VMs add vmexit overhead. nspawn doesn't.

### Mitigation knobs (priority order)

**1. cgroup caps on the unit.** This does almost all the work.

```ini
[Service]
# CPU: lowest weight. Under contention, host gets cycles first.
CPUWeight=1
# Pin to efficiency cluster only on SM8550 (verify per-device cluster layout).
AllowedCPUs=0-2

# Memory: hard ceiling, soft target. Cannot evict game caches.
MemoryHigh=512M
MemoryMax=1G
MemorySwapMax=0

# I/O: idle priority. Writes only when nobody else wants the disk.
IOWeight=1
IOSchedulingClass=idle

# Pathology guard.
TasksMax=512
```

`AllowedCPUs=0-2` is the single biggest knob. It guarantees the game's hot
threads on the prime/perf cores never see the guest as competition. The
guest can spike to 100% on three efficiency cores and the game's 60 FPS
budget is unaffected.

**2. Freeze during gameplay.** Cgroup v2 freeze parks every guest process in
`D` state -- no scheduling cost, no wakeups, instant resume.

```sh
# /storage/.config/profile.d/090-nix-guest-hooks.sh
nix_guest_freeze() {
  systemctl is-active rocknix-guest.service >/dev/null \
    && systemctl freeze rocknix-guest.service
}
nix_guest_thaw() {
  systemctl is-active rocknix-guest.service >/dev/null \
    && systemctl thaw   rocknix-guest.service
}
```

Hook into ROCKNIX's existing game launch chain (`autostart`,
`Start Steam.sh`, RetroArch wrappers): `nix_guest_freeze` before `exec`,
`nix_guest_thaw` after the emulator exits. While playing, the guest is
literally not running. On exit, it resumes in microseconds with all daemons
and sessions intact.

**3. Don't bind what the game owns.** Default invocation passes through
*nothing* the game cares about:

```sh
systemd-nspawn --boot \
  --directory=/storage/machines/rocknix-guest \
  --bind=/storage/.nix-root:/nix \
  --bind-ro=/etc/resolv.conf
  # NO /dev/dri      (no GPU contention possible)
  # NO PipeWire socket (no audio contention)
  # NO /dev/input/*  (no input handler conflict)
```

Graphical guest apps are an opt-in second profile, not the default.

**4. Forbid the truly expensive operations during play.** Two things will
hitch even with all the above:

- `nix-daemon` builds. Hard policy: builds happen on a remote builder
  (`nix.buildMachines = [...]` in NixOS), the device only fetches binaries.
  No local builds during gameplay.
- Nix garbage collection. `nix.gc.automatic = false` in the guest. Manual
  GC from SSH only.

Substituter downloads are mostly fine because of `IOSchedulingClass=idle` and
`IOWeight=1`. A `--max-jobs=1 --cores=2` default keeps even those modest.

### Steady-state expectations

| State | CPU | RAM | I/O | Frame impact |
|---|---|---|---|---|
| Game running, guest frozen | 0 | ~50 MB held | 0 | None (identical to no-guest) |
| At rest, guest idle | <0.3% | 30-80 MB | bursts of journald flush | Below noise floor of existing daemons |
| At rest, guest doing work | bounded by cgroups | ≤1 GB | idle-class | Bounded; big cores still fully available |
| Guest pathological build *without* freeze hook | high on cores 0-2 only | ≤1 GB | idle-class | Quantifies why the freeze policy exists |

## Verification plan

Don't ship on intuition. Before declaring Layer 9 acceptable:

**Reference workloads:**
- Ryujinx Mario Odyssey 1080p/60 (existing calibration point in
  `docs/solutions/performance-issues/ryujinx-smo-1080p60-rocknix-2026-04-28.md`).
- `glmark2` for headless GPU baseline.
- `stress-ng --matrix 4 --timeout 60s` or similar for CPU baseline.

**Capture for a fixed 5 minutes per condition:**
- Frame time histogram from emulator (1% low, 0.1% low, max stutter, std dev).
- `perf stat` cycles, instructions, context-switches, migrations.
- `/proc/pressure/{cpu,memory,io}` PSI samples every second.
- Package temp from thermal zone.
- Power draw from battery gauge.

**Five conditions:**

| ID | Condition | Expected outcome |
|---|---|---|
| A | Stock ROCKNIX, no nix-integration package | Baseline |
| B | Package installed, guest never started | Statistically identical to A |
| C | Guest running, idle (just systemd + journald) | <=0.5% fps delta, no PSI events |
| D | Guest frozen via freeze hook | Identical to B |
| E | Guest doing heavy nix build *without* freeze hook | Quantifies worst case the policy prevents |

**Pass criteria (sharpen with real data):**
- C vs A: 1% low FPS within 1% of baseline; no new PSI-memory events; package
  temp delta <=1 °C.
- D vs A: indistinguishable.
- E vs A: only used to *justify* the freeze policy. If E is bad enough that
  accidentally triggering it ruins a session, freeze-on-game-launch is
  non-optional. If E is mild, freeze is just hygiene.

Write up results in `docs/solutions/performance-issues/` following the
existing convention.

## Concrete walkthrough (smoke pass)

Once `systemd-nspawn` exists on the device:

**1. Build a NixOS rootfs on a build host (any aarch64 NixOS or `nix` on
aarch64-Linux):**

```nix
# rocknix-guest.nix
{ pkgs, ... }: {
  imports = [ <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix> ];
  boot.isContainer = true;
  networking.hostName = "rocknix-guest";
  services.openssh.enable = true;
  users.users.root.password = "rocknix";
  environment.systemPackages = with pkgs; [ vim ripgrep htop ];
  system.stateVersion = "25.05";
}
```

```sh
nix build .#nixosConfigurations.rocknix-guest.config.system.build.tarball
```

**2. Copy and unpack on the device:**

```sh
mkdir -p /storage/machines/rocknix-guest
tar -xpf nixos-system-aarch64.tar.xz -C /storage/machines/rocknix-guest
```

**3. Boot it:**

```sh
systemd-nspawn \
  --boot \
  --directory=/storage/machines/rocknix-guest \
  --machine=rocknix-guest \
  --bind=/storage/.nix-root:/nix \
  --bind-ro=/etc/resolv.conf
```

A NixOS login prompt should appear on stdin. Inside:

```sh
nixos-rebuild switch --flake /etc/nixos
nix profile install nixpkgs#cowsay
```

These are real, daemon-mode, sandboxed Nix builds with no proot anywhere
*inside* the guest. Host's storage-only Layer 1/2 wrappers continue to work
unchanged.

**4. Promote to a unit at `/storage/.config/system.d/rocknix-guest.service`:**

```ini
[Unit]
Description=NixOS guest (rocknix-guest)
After=storage.mount network-online.target nix.mount
Wants=network-online.target

[Service]
ExecStart=/usr/bin/systemd-nspawn \
  --boot \
  --directory=/storage/machines/rocknix-guest \
  --machine=rocknix-guest \
  --bind=/storage/.nix-root:/nix
KillMode=mixed
Type=notify
Delegate=yes
TasksMax=infinity

# Performance envelope (see Game-performance design rule)
CPUWeight=1
AllowedCPUs=0-2
MemoryHigh=512M
MemoryMax=1G
MemorySwapMax=0
IOWeight=1
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
```

Drops into the existing `/storage/.config/system.d` convention.
`Delegate=yes` and `KillMode=mixed` are the polite-citizen settings for
nested systemd. Note: do **not** wire `WantedBy=multi-user.target` if boot
time matters; prefer manual-start or hook to first SSH login so the guest
is not in EmulationStation's critical path.

## How this maps onto the existing layered plan

This is a parallel track to Layers 4-8, not a replacement.

| Plan layer | Storage-only track (current) | nspawn track (new) |
|---|---|---|
| Layer 3 -- real `/nix` | bind `/storage/.nix-root` -> `/nix` for host nix-portable | same mount, also bound into guest |
| Layer 4 -- standard Nix | install Nix on host kernel directly, fight ROCKNIX userspace | install NixOS in a guest, **trivially solved by definition** |
| Layer 5 -- profiles | host profiles via `/storage/bin` | guest profiles via guest `/etc/profiles/per-user` |
| Layer 7 -- apps | manually launched Nix apps under host Sway | guest serves apps; passthrough Wayland socket only for ones that need a screen |
| Layer 8 -- daemon | wedge `nix-daemon` into ROCKNIX systemd | already running inside the guest, problem reframed |

What you give up vs the host track: tools installed in the guest are visible
inside the guest's shell, not from the host's SSH session, unless you take the
extra step of bind-mounting a profile path back out to `/storage/bin`.

## Cheap probes to run before committing

1. **User-namespace probe.** Re-test on the device:

   ```sh
   cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null
   sysctl kernel.unprivileged_userns_clone 2>/dev/null
   unshare -U -r whoami
   ```

   If unprivileged user namespaces work, drop `NP_RUNTIME=proot` from
   `/storage/bin/*` wrappers (large perf win on Layer 1/2). nspawn user
   id-mapping (`--private-users`) becomes available.

2. **`systemd-nspawn` smoke.** After patching the systemd package to keep the
   binary, drop a minimal NixOS tarball on the device and:

   ```sh
   systemd-nspawn -bD /storage/nixos-rootfs
   ```

   If a NixOS userspace boots, "running NixOS on this thing" stops being a
   research question and becomes a packaging question.

3. **Optional: kexec smoke.** From a serial-attached session, `kexec -l
   <some-aarch64-kernel> --append="..." && kexec -e`. Same maneuver
   nixos-anywhere uses, but with a kernel of your choosing. Useful only as
   evidence-gathering for Path 4; not a deliverable.

## Honest risks

- **eMMC wear and contention.** Even with `IOWeight=1`, large `nix copy`
  operations write hundreds of MB. Don't do them during play. Budget the Nix
  store explicitly (`/storage/.nix-root` quota) so it can't silently grow into
  the territory shader caches and saves need.
- **THP and memory bandwidth.** The recent THP commit gives ROCKNIX a memory
  throughput boost. A guest doing heavy allocation can fragment THP
  availability host-wide. Mitigation is the `MemoryMax=1G` cap plus avoiding
  builds during play; existing `rocknix-memory-manager` handles the rest.
- **Boot-time impact.** Don't `WantedBy=multi-user.target` by default. ROCKNIX
  boots straight to EmulationStation; the guest must not be in that critical
  path.
- **Userspace surprise.** The nix-portable `setgroups` failure is unexplained.
  nspawn running as root doesn't need unprivileged userns, so it doesn't
  block this design -- but `--private-users` (id-mapped guest) is off the
  table until the runtime restriction is identified.
- **ROCKNIX update interaction.** A ROCKNIX nightly update reverts the
  systemd package patch (the kept nspawn binary). Either upstream the patch,
  carry it on the `custom` branch persistently, or ship nspawn from Nix into
  `/storage/bin` instead of relying on the image binary.
- **Standalone bootstrap drift** (already flagged in the existing handoff
  doc): `nix-on-rocknix-bootstrap.sh` duplicates package-script logic.
  Adding nspawn workflow makes that drift worse. Resolve before promoting
  Layer 9 to anything user-facing.

## Recommended next actions

In order, smallest first:

1. Run the user-namespace probe. Report whether unprivileged user namespaces
   work and capture the failure mode if not. (Independent of Layer 9 -- this
   answers a question that affects Layers 1-2 immediately.)
2. On the `custom` branch, drop the two `safe_remove` lines for nspawn in
   `packages/sysutils/systemd/package.mk`. Rebuild SM8550 image. Confirm
   `systemd-nspawn --version` works on device.
3. Build a minimal aarch64 NixOS container tarball off-device, copy in,
   boot manually with `systemd-nspawn -bD`. Confirm a NixOS userspace boots
   and `nix-daemon` works inside.
4. Add the performance-envelope unit file and freeze hooks. Run the
   five-condition verification plan against a known game (Ryujinx SMO).
   Write up in `docs/solutions/performance-issues/`.
5. Only after 1-4 pass: promote this document into a real plan
   (`docs/plans/<date>-NNN-feat-nspawn-layer-9.md`) and add Unit 11 to the
   layered-Nix plan referencing the new track.

## Hard constraints carried forward from existing plan

Same as the existing layered-Nix plan:

- ROCKNIX continues to own boot, kernel, firmware, hardware quirks, and
  default UI startup.
- No NixOS-style control of the base OS (R6).
- `/usr` and `/` are immutable at runtime.
- EmulationStation/Sway is the default UI; nothing in the nspawn track may
  preempt it.
- SSH must remain the recovery path.
- Game performance is a hard constraint, verified by measurement, not
  asserted.

## Sources & references

- Existing plan: `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md`
- Existing handoff: `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md`
- Operator doc: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- ROCKNIX systemd build: `packages/sysutils/systemd/package.mk`
- SM8550 kernel config: `projects/ROCKNIX/devices/SM8550/linux/linux.aarch64.conf`
- Existing container precedent: `packages/addons/service/podman/package.mk`
- Performance baseline: `docs/solutions/performance-issues/ryujinx-smo-1080p60-rocknix-2026-04-28.md`
- External: `systemd-nspawn(1)`, `systemd.resource-control(5)` (cgroup v2 caps)
- External: `nixos-anywhere` (https://github.com/nix-community/nixos-anywhere)
- External: NixOS `boot.isContainer` option
