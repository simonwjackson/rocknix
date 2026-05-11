# ROCKNIX → Level N: Stages 8–12 Thinking Report

Date: 2026-05-10  
Branch context: `feat/rocknix-layer-14-thin-host`  
Purpose: handoff-oriented thinking report for another LLM to continue reasoning from the current strategic frame.

## Executive Summary

Assume stages 1–7 are validated:

1. Nix guest boots as main product space.
2. Guest owns compositor/session.
3. Guest owns display config.
4. Guest runs a demanding emulator workload.
5. Guest owns emulator launch/runtime contract.
6. Guest owns product UX / launcher loop.
7. Guest owns device-facing policy sufficiently: input, display, audio, power/perf are proven representative capabilities.

Given those assumptions, the next meaningful frontier is no longer “can Nix run apps?” or “can Nix own UX?” It is whether ROCKNIX can be reduced from product OS to bootstrap/recovery substrate, and then whether Nix can become the source of truth for the booted system and eventually the boot artifacts.

The strategic sequence is:

8. **Host product-path amputation** — prove normal user operation no longer depends on ROCKNIX product UX.
9. **Host package/service closure minimization** — remove legacy product packages/services from the thin-host image once amputation is proven.
10. **Nix-built guest/rootfs activation as source of truth** — make the selected guest system a Nix generation with activation/rollback semantics.
11. **Nix-owned boot artifacts** — have Nix build/select early boot artifacts after the vendor boot boundary: initramfs first, then kernel/dtb/modules, then boot images.
12. **Level N** — everything after immutable vendor/bootloader trust boundary is Nix-built, Nix-selected, and Nix-rollbackable; ROCKNIX survives only as reference, fallback, or recovery if desired.

The guiding principle is **capability proof migration**, not coverage migration. Do not port every emulator or every service before moving up the ladder. Prove each architectural layer with one representative path, then proceed.

---

## Mental Models Used

### 1. Via Negativa

At stages 8–10, progress comes less from adding Nix capability and more from removing host responsibilities. Ask: what can be absent from the host while the device still behaves like the product?

### 2. Theory of Constraints

Once stages 1–7 are proven, the bottleneck shifts to hidden host dependency. If the product path still requires ROCKNIX services “just in case,” Nix is not yet the system authority.

### 3. Reversibility Test

Every move after stage 8 risks bricking or degrading recoverability. Each stage should be reversible, preferably first via masking/selection, then via package removal, then via boot artifact replacement.

### 4. Source of Truth

The key stage-10 question: if someone asks “what system is this handheld running?”, the answer should be a Nix generation, not a pile of host scripts, mutable `/storage` files, and hand-copied rootfs state.

---

## Stage 8 — Host Product-Path Amputation

### Definition

Host product-path amputation means ROCKNIX is no longer capable of delivering the normal gaming/product experience in main-space mode. The normal product path must succeed through Nix-owned guest UX and fail if the guest is absent, except when explicit recovery mode is selected.

This is stronger than merely preferring Nix. It means ROCKNIX product UX is not a parallel or fallback participant in normal operation.

### Target Shape

Normal boot path:

```text
boot
  -> host recovery toggle / boot selector
  -> host starts guest supervisor
  -> guest systemd starts compositor/session/launcher
  -> guest launches promoted app/game path
  -> guest owns lifecycle and returns to launcher
```

Host retains:

- bootloader/kernel/initramfs for now
- hardware bring-up
- mounts/storage availability
- nspawn/supervisor
- recovery toggle
- SSH/debug control plane
- tiny privileged helpers where guest cannot safely touch host sysfs/device controls

Host does **not** retain normal product authority:

- no host frontend as default UX
- no host emulator launcher as normal path
- no host game-selection flow
- no host Cemu/RetroArch/etc. used by normal mode
- no host profile selection for product launches
- no host display/audio/input policy decisions except explicit substrate/actuator roles

### Strong Proof

A good stage-8 proof should show:

- Cold boot reaches Nix guest UX.
- User can launch the representative app/game from guest UX.
- App/game exits back to guest UX.
- No host frontend process is active.
- No host emulator process is active.
- No host launch script decides product runtime/env/profile.
- Host Cemu/emulators are not invoked.
- Recovery flag still boots to safe recovery.
- If the guest is intentionally stopped or unavailable, normal product UX is absent by design rather than silently falling back to ROCKNIX product UX.

### First Implementation Style

Prefer reversible amputation first:

- Mask/disable host product services in THIN_HOST/main-space mode.
- Keep packages present initially for debug/recovery.
- Add evidence collection that proves host product processes are absent.
- Only after proof, proceed to stage 9 package/service closure minimization.

### False Wins to Avoid

- Host still runs ES/essway/ROCKNIX frontend but guest window covers it.
- Host launcher starts guest launcher and still owns runtime decisions.
- Guest UX works only because host scripts mutate product config at launch time.
- Host emulator remains used for control/performance fallback in normal mode.
- Recovery path and product path remain entangled.

### Stage-8 Exit Criteria

Stage 8 is done when another LLM/operator can say:

> In normal mode, ROCKNIX is a bootstrap/recovery substrate. The user-facing product path is guest-owned. Host product UX can be disabled without reducing normal functionality.

---

## Stage 9 — Host Package/Service Closure Minimization

### Definition

Host package/service closure minimization removes the packages and services that stage 8 proved are no longer part of the normal product path.

This is not a random “make image smaller” exercise. Packages are removed because their responsibilities moved to the guest.

### Allowlist Thinking

Define the thin host by what it is allowed to do:

1. **Boot/hardware bring-up**
   - bootloader/kernel/initramfs until later stages
   - firmware
   - device tree/kernel patches
   - storage mounts
   - udev/device availability needed to expose hardware to guest

2. **Guest supervision**
   - systemd-nspawn or equivalent guest supervisor
   - `/nix` mount/profile preparation
   - selected guest generation startup
   - health checks and boot diagnostics

3. **Recovery/control**
   - SSH or chosen fallback control surface
   - recovery flag/toggle
   - ability to disable guest and boot safe mode
   - enough logging to debug boot failure

4. **Privileged actuators**
   - minimal helpers for sysfs, brightness, power/perf, thermal, fan, or device-specific controls the guest cannot own directly
   - these helpers should be narrow, audited, and callable by guest policy rather than embedding product policy themselves

Everything outside that allowlist is suspect.

### Likely Removal Candidates

Once stage 8 proves the product path no longer uses them, candidates include:

- EmulationStation / ES-DE normal product path
- host game-selection UI
- host emulator packages
- host Cemu/RetroArch/Dolphin/etc. for normal play
- host emulator launch scripts
- host gamescope wrappers for normal play
- host MangoHud/product telemetry wrappers if guest owns telemetry
- host frontend themes/assets/game databases/artwork paths
- host compositor/session stack if not needed for graphical recovery
- host audio/session policy if guest owns audio policy
- host input mapping policy if guest owns input policy

### Recovery Split

Before removing anything, classify host components into:

- **normal-path required** — should be near-zero after stage 8
- **recovery-only required** — keep if graphical recovery is desired
- **legacy product cruft** — remove
- **hardware substrate** — keep until Nix boot artifacts can own it
- **unknown** — prove before removing

The most important strategic distinction is recovery vs product. Keeping a full graphical recovery mode may be valid, but it should not be confused with normal product dependency.

### Strong Proof

Build or configure a minimal thin-host variant where:

```text
host = boot + hardware + guest supervisor + recovery + narrow actuators
guest = UX + apps + runtime policy
```

Then validate:

- Cold boot reaches guest UX.
- Guest representative workload still runs.
- Guest exits back to launcher.
- No host frontend/emulator service exists or runs.
- Recovery still works.
- SSH/debug still works.
- Device-facing policy still works through guest or narrow host actuators.
- If guest is disabled, host does not accidentally become a product OS again unless explicit recovery mode is selected.

### False Wins to Avoid

- Removing packages before proving stage 8, making failures harder to debug.
- Removing recovery because it looks like product cruft.
- Keeping hidden host product services because “they are harmless.” Hidden services undermine the proof that Nix owns the product path.
- Chasing image-size metrics instead of responsibility boundaries.

### Stage-9 Exit Criteria

Stage 9 is done when the thin-host closure contains no legacy product UX/emulator responsibilities in normal mode, while recovery remains intentional and documented.

---

## Stage 10 — Nix-Built Guest/Rootfs Activation as Source of Truth

### Definition

Stage 10 means the guest system is no longer a host-prepared rootfs plus some Nix packages. The guest system is selected, versioned, activated, rolled back, and explained by Nix.

The key question:

> If I want to know what product OS is running, where do I look?

At stage 10, the answer should be:

> A Nix system generation/profile.

### Current Anti-Pattern to Move Away From

The pre-stage-10 shape is typically:

```text
ROCKNIX image ships guest root pieces
host scripts patch/relink/mutate them
/storage contains extra launchers/configs
Nix profile provides some packages
```

That shape can work, but the source of truth is spread across host image, mutable storage, scripts, and Nix.

### Target Shape

Stage-10 target:

```text
Nix builds complete guest system closure
host selects one guest generation
host starts exactly that generation
selected guest generation activates its own state
rollback = select previous Nix generation
```

Nix owns:

- guest `/etc`
- guest systemd units
- guest Sway/session config
- launcher/menu config
- emulator wrappers
- service dependencies
- package versions
- environment variables
- activation scripts
- runtime directory setup
- declared mount expectations
- optionally generated host metadata consumed by the supervisor

Host still owns:

- kernel/boot artifacts for now
- device bind mounts
- nspawn invocation mechanics
- recovery selection
- “start selected guest generation” supervisor logic

### Strong Proof

A strong proof should demonstrate Nix-native switch and rollback:

1. Build a guest system generation on Fuji or local builder.
2. Copy/import closure into device store with real Nix store tooling.
3. Switch an explicit guest system profile, e.g. conceptually:

   ```text
   /nix/var/nix/profiles/per-user/root/rocknix-guest-system
   ```

4. Host guest service starts from that profile’s `init`/system path, not a hand-managed fixed rootfs.
5. Reboot.
6. Device boots into new guest UX.
7. Roll back to previous guest generation.
8. Reboot.
9. Device boots into previous guest UX.

The proof is not “it boots once.” The proof is:

> Activation and rollback are Nix-native.

### Host Prep Scripts: Do Not Delete Blindly

Use Chesterton’s Fence. Existing host prep may encode real constraints:

- `/init` relink workaround
- udev staging
- cgroup mode
- tty/device binds
- storage mounts
- recovery flag selection
- guest root availability checks

The move is not “delete prep.” The move is:

```text
host says: start selected guest generation
generation says: what the guest is
```

Host prep should become generic and generation-driven rather than product-specific.

### False Wins to Avoid

- Calling the guest “Nix-owned” while launchers/config still live as mutable `/storage` scripts outside the generation.
- Switching packages but not the system generation.
- Rebuilding inside the guest but relying on host relinks that are not tied to generation metadata.
- Having rollback restore packages but not session config/services.

### Stage-10 Exit Criteria

Stage 10 is done when the selected Nix guest generation fully defines the guest system and can be switched/rolled back without product-specific host mutation.

---

## Stage 11 — Nix-Owned Boot Artifacts

### Definition

Nix-owned boot artifacts means Nix stops merely defining the guest/runtime and starts defining the things the device boots, after the immutable/vendor trust boundary.

On SM8550, full ownership of vendor firmware/boot ROM/Qualcomm chain is likely unrealistic or unnecessary. Do not set “Nix builds Qualcomm firmware” as the bar.

A better bar:

> Everything after the vendor/bootloader trust boundary is Nix-built, Nix-selected, and Nix-rollbackable.

### Boot Chain Model

Rough chain:

```text
immutable/vendor boot chain
  -> bootloader / ABL / firmware
  -> kernel + dtb/dtbo
  -> initramfs
  -> rootfs / system closure
  -> product session
```

Stage 11 starts owning this chain from the earliest safe point.

### Suggested Sublevels

#### 11a — Nix-Built Initramfs Proof

Existing host/bootloader still loads the existing kernel, but initramfs is Nix-built.

Target:

```text
bootloader -> existing kernel -> Nix-built initramfs -> selected Nix system
```

Purpose:

- Prove Nix can own early userspace.
- Keep kernel risk low.
- Keep rollback simple.

Strong proof:

- Nix builds initramfs derivation.
- Device boots through it.
- Initramfs selects/mounts the Nix system or starts the known handoff.
- Recovery path survives failed initramfs.

#### 11b — Nix-Built Kernel + Modules + DTB/DTBO

Now Nix builds hardware kernel artifacts.

Target:

```text
bootloader -> Nix-built kernel/dtb/initramfs -> selected Nix system
```

Purpose:

- Prove Nix owns the hardware/software boundary after firmware.
- Version kernel patches and module set with the system.

Strong proof:

- Nix builds kernel, modules, dtb/dtbo, initramfs.
- Boot succeeds.
- Display/input/audio/storage/network hardware still function.
- Rollback to previous boot artifact works.

#### 11c — Nix-Built Boot Image / Flashable Artifact

Nix produces the artifact the bootloader consumes.

Conceptual output:

```sh
nix build .#thor-boot-image
```

Possible artifacts:

- `boot.img`
- `dtbo.img`
- kernel image
- initramfs
- update bundle
- full image manifest

Purpose:

- Nix owns artifact construction, not just ingredients.
- Reproducibility becomes inspectable from one derivation.

Strong proof:

- Artifact is built by Nix.
- Artifact boots on target.
- Artifact metadata records exact kernel/initramfs/system generation.
- Recovery/fallback path remains available.

#### 11d — Nix-Managed Boot Selection + Rollback

Device can select generation N or N-1 safely.

Target behavior:

```text
generation 42 boots
generation 43 fails
boot counter / recovery selector rolls back to 42
```

Purpose:

- Boot artifact ownership becomes operationally safe.
- This is where the system starts feeling Nix-native rather than custom-image-native.

Strong proof:

- Boot success/failure is detected.
- Known-good generation is recorded.
- Failed boot reverts automatically or via simple recovery selection.
- Manual recovery remains possible.

### False Wins to Avoid

- Nix builds a kernel, but host image still authors boot composition.
- Nix builds ingredients, but a manual script assembles final images without derivation metadata.
- New boot artifact works once but has no rollback.
- Recovery is sacrificed for purity.
- Firmware/vendor boundary work consumes effort without improving product authority.

### Stage-11 Exit Criteria

Stage 11 is done when a Nix derivation produces the bootable artifact(s), the device boots them, and there is a proven rollback path.

The conceptual checkpoint:

> Can I point at one Nix derivation and say: “this is the thing my handheld boots”?

---

## Stage 12 — Level N

### Definition

Level N is the horizon state:

```text
vendor boot ROM / locked firmware
  -> minimal bootloader boundary
  -> Nix-built boot artifact
  -> Nix-built initramfs
  -> Nix-selected system generation
  -> Nix-owned product UX
```

ROCKNIX is no longer the operating system in the normal path.

It may survive as:

- historical source of hardware patches
- compatibility reference
- recovery image or fallback slot
- upstream source for device enablement
- emergency flashable artifact

But it is no longer the product authority.

### What “Done” Means

Level N should mean:

- product UX is Nix-owned
- app/runtime/device policy is Nix-owned
- guest/rootfs/system activation is Nix-owned
- boot artifacts after vendor boundary are Nix-built
- rollback is Nix-aware
- host/ROCKNIX product path is absent from normal mode
- recovery is intentional, documented, and tested

### What “Done” Should Not Mean

Level N should **not** require:

- rebuilding proprietary Qualcomm firmware
- owning immutable boot ROM behavior
- eliminating all fallback/recovery artifacts
- porting every emulator before moving up the ladder
- deleting all ROCKNIX-derived knowledge or patches

### Permanent Recovery Question

There is a strategic choice for Level N:

1. **ROCKNIX as permanent recovery slot**
   - Pros: safer, faster iteration, known-good escape hatch.
   - Cons: psychologically and operationally keeps ROCKNIX present.

2. **Nix-built recovery too**
   - Pros: cleaner final architecture; Nix owns normal and recovery systems.
   - Cons: higher risk; need robust fallback if Nix recovery breaks.

A sensible path may be:

- keep ROCKNIX recovery through stages 8–11
- once Nix boot artifacts and rollback are boring, build a Nix recovery artifact
- keep an external flash/USB/SD recovery story regardless

### Level-N Exit Criteria

A strong Level-N demonstration:

1. Build boot/system artifact with one Nix command.
2. Install/select artifact on device.
3. Cold boot succeeds.
4. Device reaches Nix-owned UX.
5. Representative workload runs and exits.
6. Device-facing policies work.
7. Failed update rolls back.
8. Explicit recovery path works.
9. No ROCKNIX product UX/emulator path participates in normal operation.

---

## Recommended Sequence From Current Assumptions

Assuming stages 1–7 are truly validated, the next LLM should reason in this order:

1. **Define and test stage-8 amputation.**
   - First disable/mask host product services.
   - Prove guest product path still works.
   - Prove host product path is absent.
   - Prove recovery still works.

2. **Classify host services/packages.**
   - normal-path required
   - recovery-only
   - legacy product cruft
   - hardware substrate
   - unknown

3. **Build minimal thin-host variant.**
   - Remove legacy product cruft from normal image.
   - Keep recovery intentional.
   - Validate cold boot, app path, recovery, and debug.

4. **Make guest generation selection Nix-native.**
   - Profile/generation defines guest system.
   - Host supervisor starts selected generation generically.
   - Switch/rollback proof is required.

5. **Move earliest safe boot artifact into Nix.**
   - Start with initramfs.
   - Then kernel/dtb/modules.
   - Then assembled boot image/update artifact.
   - Do not proceed without rollback/recovery.

6. **Approach Level N.**
   - One Nix derivation builds what boots.
   - Nix generation defines what runs.
   - ROCKNIX is reference/recovery, not product OS.

---

## Key Risks and Stress Tests

### Risk: Hidden Host Dependency

Stress test:

- Stop/mask all host product services.
- Assert guest product path still works.
- Assert no host product process appears.

### Risk: Recovery Erosion

Stress test:

- Intentionally break guest generation.
- Ensure recovery flag/SSH/fallback still works.

### Risk: Mutable Storage Becomes New Source of Truth

Stress test:

- Rebuild/switch guest generation from Nix.
- Confirm launchers/session/config come from generation, not hand-copied `/storage` scripts.

### Risk: Boot Artifact Bricking

Stress test:

- Test earliest safe artifact first.
- Preserve known-good slot.
- Use boot counters or manual recovery.

### Risk: False Thinness

Stress test:

- Measure not only image size, but responsibility boundaries.
- A smaller host that still decides product behavior is not thin in the architectural sense.

---

## Handoff Notes for Next LLM

- Treat stages 1–7 as assumed validated only if the user explicitly maintains that assumption. If evidence is required, inspect Layer 14 docs and Cemu parity artifacts.
- Do not recommend porting more emulators as the next strategic step. That proves breadth, not architectural depth.
- Do not jump directly to Nix-built kernel/boot image before host product-path amputation and Nix-native guest activation/rollback are boring.
- Preserve ROCKNIX recovery until the Nix-owned boot path has its own proven rollback/recovery story.
- Keep the distinction between **normal product path** and **recovery path** crisp. A full recovery UX can be okay if it is explicitly recovery-only.
- The most important next conceptual proof is not “Nix can do more.” It is “ROCKNIX can do less.”
