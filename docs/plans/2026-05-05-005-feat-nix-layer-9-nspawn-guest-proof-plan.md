---
title: feat: Add Layer 9 NixOS nspawn guest proof
type: feat
status: active
date: 2026-05-05
origin: docs/plans/2026-05-01-001-explore-nixos-on-rocknix-via-nspawn.md
---

# feat: Add Layer 9 NixOS nspawn guest proof

## Overview

Layer 9 proves whether ROCKNIX can run a storage-backed NixOS-style userspace inside `systemd-nspawn` without giving NixOS control of the host. This is a bounded proof layer: preserve the `systemd-nspawn` binary in the image behind an opt-in build gate, add diagnostics that say whether the device can attempt the proof, document a minimal guest contract, and validate a manually started guest on `thor`.

Layer 9 does **not** add managed guest operations. There is no boot autostart, no `nixctl guest start/stop/shell/update/rollback`, no host app bridges, and no graphical/audio/input passthrough by default. Those belong to Layer 10+ only if this proof earns a Go decision.

## Problem Frame

Layer 8 proved host-side `nix-daemon` can run when the image supplies build identities and daemon units, but it also sharpened the architectural boundary: ROCKNIX remains the host OS, while increasingly NixOS-like behavior may be cleaner in a guest than on the host. The existing Layer 9 exploration argues that `systemd-nspawn` is the lowest-risk way to run a real NixOS userspace while preserving ROCKNIX's kernel, firmware, EmulationStation/Sway startup, Steam/FEX behavior, update model, and SSH recovery path (see origin: `docs/plans/2026-05-01-001-explore-nixos-on-rocknix-via-nspawn.md`).

The immediate question is not “can we manage a guest as a product feature?” It is narrower: can a manually started, storage-backed NixOS container boot on SM8550, run a useful command or daemon-backed Nix proof inside, and be stopped/deleted without affecting the host?

The failure/fallback language for this layer must be precise. Layer 9 failure means the guest cannot be prepared, started, contacted, or stopped cleanly. The required fallback is not “another guest path”; it is that the ROCKNIX host remains normal and Layers 4/8 are still available or recoverable. Any claim beyond that needs hardware evidence, not design intent.

## Requirements Trace

- R1. Preserve ROCKNIX as owner of boot, kernel, firmware, default UI, image updates, Steam/FEX, and recovery.
- R2. Keep Layer 9 opt-in and manual-start only; package inclusion must not start a guest during boot.
- R3. Provide a usable proof outcome: a NixOS-style guest userspace boots under `systemd-nspawn` from `/storage` and can run a trivial command or Nix daemon/client proof inside.
- R4. Keep all mutable Layer 9 guest state under `/storage`; do not write guest configuration or rootfs state into `/etc`, `/usr`, `/flash`, or boot surfaces.
- R5. Add diagnostics before relying on hardware validation: nspawn binary presence, kernel/container prerequisite visibility, storage rootfs presence, and host fallback status.
- R6. Preserve Layers 4/8 as host fallbacks; guest failure must not require reflashing or deleting host `/nix` unless the operator chooses to reset all Nix state.
- R7. Do not share host graphics, audio, input, ROM, save, Steam/FEX, or launcher surfaces with the guest in Layer 9.
- R8. Document exact Go/No-Go criteria and observed failure modes instead of treating a partial boot as success.
- R9. Carry forward the ABL precheck discipline for any SM8550 full-image update used to ship `systemd-nspawn`.
- R10. Explicitly defer managed guest lifecycle, autostart, app bridges, and performance-envelope automation to Layer 10+.

## Scope Boundaries

- This plan does not replace ROCKNIX with NixOS.
- This plan does not make the guest start at boot.
- This plan does not add a persistent `rocknix-guest.service` enabled by default.
- This plan does not add `nixctl guest start/stop/shell/update/rollback`; those are Layer 10 managed guest operations.
- This plan does not pass through `/dev/dri`, PipeWire sockets, `/dev/input`, ROM directories, save directories, Steam/FEX state, or host Sway/Wayland sockets.
- This plan does not require the guest to build packages locally. Cached/substituted trivial proof is sufficient for Layer 9.
- This plan does not claim game-performance safety for a running guest beyond the manual-start/no-autostart boundary. Full performance-envelope validation is deferred to Layer 10.

### Deferred to Separate Tasks

- Layer 10: `nixctl guest status/start/stop/shell/update/rollback`, resource controls, freeze/thaw policy, and a persistent but disabled guest unit.
- Layer 11: guest-backed host launchers, Ports entries, services, or graphical/audio/input passthrough.
- Layer 12: declarative host/guest profiles.
- Layer 13: curated capability catalog.
- Full five-condition gameplay performance validation from the exploration document, unless Layer 9 manual proof shows unexpected host impact.

## Context & Research

### Relevant Code and Patterns

- `packages/sysutils/systemd/package.mk` currently builds systemd with `-Dmachined=false` and `-Dportabled=false`, then explicitly removes `systemd-nspawn` and `systemd-nspawn@.service` in `post_makeinstall_target()`.
- `projects/ROCKNIX/packages/tools/nix-integration/package.mk` already uses build-time gates (`NIX_DAEMON_SUPPORT`) to add optional support without enabling risky services by default.
- `projects/ROCKNIX/options` already carries fork-level defaults for `NIX_INTEGRATION_SUPPORT` and `NIX_DAEMON_SUPPORT`; Layer 9 should use the same option style.
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl` is the operator-facing status front door for Layers 4-8.
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor` already reports layered health without mutating state.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` and `tests/nix-integration-runtime-smoke.sh` use fixtureable environment overrides and opt-in hardware smokes.
- `projects/ROCKNIX/packages/sysutils/systemd/patches/systemd-0001-move-etc-systemd-system-to-storage-.config-system.d.patch` means persistent operator units live under `/storage/.config/system.d`, but Layer 9 should not install an enabled unit yet.
- `projects/ROCKNIX/devices/SM8550/linux/linux.aarch64.conf` has namespace/cgroup features called out in the exploration doc: user, PID, network namespaces, cgroups, seccomp, overlay/fuse, and KVM support.

### Institutional Learnings

- `docs/solutions/developer-experience/nix-layer-8-daemon-mode-rocknix-2026-05-05.md`: daemon mode must be opt-in, preflight-gated, and reversible; config/state belong under `/storage` or `/nix`, not `/etc`.
- `docs/solutions/developer-experience/trigger-fork-rocknix-actions-build-from-nixos-2026-05-05.md`: when local `make SM8550` does not work on a NixOS host, use GitHub Actions `workflow_dispatch` to build a fork-specific image with custom flags.
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`: fork images must be deployed manually through `/storage/.update/`, with ABL slot precheck before rebooting into updater.
- `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`: profile integration order matters on ROCKNIX; any Layer 9 shell/profile affordance must not reintroduce earlier PATH reset issues.
- Recent Layer 8 hardware proof showed Layer 8 -> Layer 4 fallback is real and validated; deeper fallback claims must be tested or labeled as unproven.

### External References

- `systemd-nspawn(1)` for standalone container boot with `--boot`, `--directory`, and bind mounts.
- `systemd.resource-control(5)` for later Layer 10 CPU/memory/I/O limits.
- NixOS `boot.isContainer = true` for guest-shaped NixOS systems.
- `nixos-generators` / NixOS system tarball patterns for producing an aarch64 container rootfs off-device.

## Key Technical Decisions

| Decision | Rationale |
|---|---|
| Treat Layer 9 as proof-only | It answers whether the guest can boot and run, without committing to lifecycle management or product UX. |
| Preserve `systemd-nspawn` behind an image build option | ROCKNIX currently removes it intentionally; keeping it should be explicit and reversible by rebuild. |
| Do not enable `systemd-nspawn@.service` or any guest unit by default | Boot/SSH/UI must not depend on guest behavior. Manual start keeps failure isolated. |
| Add status/doctor diagnostics, not lifecycle commands | Diagnostics are needed for safe validation; lifecycle commands are Layer 10 scope. |
| Store guest rootfs under `/storage/machines/rocknix-guest` | Keeps all guest state on the mutable partition and makes rollback a directory removal. |
| Default to no passthrough of GPU/audio/input/game data | Layer 9 is a CLI/headless proof. Passthrough expands blast radius and belongs to later app/service bridge work. |
| Use a separate guest Nix store unless sharing is deliberately tested | Binding host `/storage/.nix-root` into the guest risks host/guest store coupling. For the first proof, guest-local state under the rootfs is safer; host store sharing can be a documented later variant. |
| Define failure/fallback as host invariants plus cleanup, not as “lower layers can do the same job” | Layer 9 failure should leave ROCKNIX and host Nix layers intact; it does not need an equivalent guest replacement. |

## Open Questions

### Resolved During Planning

- Should Layer 9 pursue full NixOS replacement? No. The exploration document rejects replacement/kexec as too expensive for the device enablement ROCKNIX already provides.
- Should Layer 9 use `systemd-nspawn` rather than QEMU/KVM? Yes. It shares the host kernel, avoids VM overhead, and matches the “ROCKNIX owns hardware” boundary.
- Should Layer 9 add managed guest lifecycle now? No. That is explicitly Layer 10.
- Should Layer 9 autostart the guest? No. Manual start only until boot impact and resource controls are understood.
- Should Layer 9 pass through graphics/audio/input by default? No. Those are app/service bridge surfaces and must stay out of the proof.

### Deferred to Implementation

- Exact build option name: default recommendation is `NIX_NSPAWN_SUPPORT`, but implementation should choose the final name consistent with ROCKNIX option conventions.
- Exact aarch64 NixOS rootfs generation method: choose between NixOS tarball, `nixos-generators`, or another reproducible host-side method during implementation.
- Whether ROCKNIX's systemd build includes all runtime libraries needed by `systemd-nspawn` after preserving the binary: validate in the daemon-enabled/fork image.
- Whether the guest should use a guest-local `/nix` or bind host `/storage/.nix-root` for the first proof: default to guest-local, but implementation may switch if the tarball layout requires it and the coupling is documented.
- Whether `systemd-nspawn --boot` works without machined/logind conveniences in this trimmed systemd: validate on hardware.
- Whether unprivileged user namespaces work on `thor`: useful evidence for id-mapped/private-users variants, but not required for root-started nspawn proof.

## Success Metrics

- A fork image can be built with Layer 9 support and `systemd-nspawn --version` is present on `thor`.
- Default boot behavior is unchanged: no guest process starts automatically, SSH returns normally after update/reboot, and Sway/EmulationStation remain unaffected.
- `nixctl status` and `nix-doctor --offline` report Layer 9 capability and clearly distinguish “unsupported”, “available”, “rootfs missing”, and “proof ready”.
- A pre-staged NixOS-style aarch64 guest rootfs under `/storage/machines/rocknix-guest` can be manually started with `systemd-nspawn`.
- Inside the guest, a trivial proof runs: either systemd reaches a login/booted state, or a Nix client/daemon proof such as `nix --version` / `nix store ping` / `hello` succeeds depending on the chosen rootfs.
- Stopping the manual guest leaves no host service enabled and no persistent state outside `/storage/machines/rocknix-guest` and optional Layer 9 metadata.
- A No-Go result records the exact blocker and leaves Layers 4/8 usable.

## Dependencies / Prerequisites

- Layer 3 `/nix` mount and Layer 4 host Nix remain healthy before attempting Layer 9.
- Layer 8 daemon-enabled image build path is known-good for producing fork images via GitHub Actions.
- SSH recovery is confirmed before any reboot or guest smoke.
- SM8550 ABL slot precheck is completed before applying any full update image.
- A reproducible aarch64 NixOS container/rootfs artifact is available before hardware smoke.
- `/storage` has enough free space for a guest rootfs and any guest-local Nix store growth.

## Alternative Approaches Considered

| Approach | Why not chosen for Layer 9 |
|---|---|
| Full NixOS replacement / kexec | Crosses the ROCKNIX ownership boundary and inherits bootloader, firmware, graphics, input, update, and handheld-specific enablement work. |
| QEMU/KVM NixOS VM | Stronger isolation but higher RAM/CPU overhead and poorer fit for handheld resource constraints. |
| Host daemon only | Layer 8 already proved host daemon feasibility; it does not answer whether a real NixOS-style userspace can run safely beside ROCKNIX. |
| Podman/runc guest | Possible fallback if `systemd-nspawn` is unavailable, but nspawn is already built then removed by the systemd package and is the smallest image change. |
| Add full `nixctl guest` lifecycle immediately | Too much surface before the basic proof is known-good; belongs to Layer 10. |

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

Layer 9 adds a capability beside the host Nix stack. It does not replace any host layer:

```mermaid
flowchart TB
  Host[ROCKNIX host]
  Storage[/storage]
  HostNix[Layers 3-8 host Nix]
  Nspawn[systemd-nspawn binary]
  Rootfs[Guest rootfs under /storage/machines/rocknix-guest]
  Manual[Manual operator start]
  Guest[NixOS-style guest userspace]
  Stop[Manual stop/delete rootfs]
  NoGo[No-Go: document blocker]

  Host --> Storage
  Host --> HostNix
  Host --> Nspawn
  Storage --> Rootfs
  Nspawn --> Manual
  Rootfs --> Manual
  Manual -->|boots| Guest
  Manual -->|fails| NoGo
  Guest --> Stop
  NoGo --> HostNix
  Stop --> HostNix
```

Layer 9 diagnostic states:

| State | Meaning | Operator action |
|---|---|---|
| `unsupported` | `systemd-nspawn` absent or kernel/container prerequisite missing | Rebuild with Layer 9 support or stop the experiment. |
| `available` | nspawn exists; guest rootfs not yet staged | Stage the rootfs or stop. |
| `proof-ready` | nspawn exists and rootfs path looks valid | Manual smoke may run. |
| `running` | A guest process/machine appears active | Validate guest proof, then stop it. |
| `failed` | Manual boot attempted but failed | Capture logs, stop/delete guest state, keep host layers. |
| `rejected` | Evidence shows nspawn is not worth pursuing | Document stop decision; continue Layers 4/8. |

Failure/fallback matrix:

| Failure point | Expected host impact | Fallback / cleanup claim |
|---|---|---|
| `systemd-nspawn` absent | None | Rebuild with option or stop Layer 9. |
| Rootfs missing/invalid | None | Remove/re-stage `/storage/machines/rocknix-guest`. |
| Guest boot fails | Guest process may remain until killed | Stop nspawn process; host Layers 4/8 remain usable. |
| Guest consumes resources while running | Bounded only by manual operator discipline in Layer 9 | Stop guest immediately; resource controls deferred to Layer 10. |
| ROCKNIX update removes nspawn | Guest cannot start after update | Rebuild fork image with option; stored rootfs remains inert. |
| `/storage` corruption | Affects guest and host Nix storage | This is outside Layer 9 fallback; restore/reflash/storage reset as normal. |

## Implementation Units

- [x] **Unit 1: Gate systemd-nspawn preservation at image build time**

**Goal:** Make `systemd-nspawn` available in fork images only when Layer 9 support is explicitly enabled.

**Requirements:** R1, R2, R4, R9

**Dependencies:** Existing systemd package build remains otherwise unchanged.

**Files:**
- Modify: `packages/sysutils/systemd/package.mk`
- Modify: `projects/ROCKNIX/options`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Add an image-time option following the existing `NIX_DAEMON_SUPPORT` pattern. Default should be conservative for upstream compatibility unless this fork intentionally enables it for validation builds.
- Replace unconditional `safe_remove ${INSTALL}/usr/bin/systemd-nspawn` and `safe_remove ${INSTALL}/usr/lib/systemd/system/systemd-nspawn@.service` with conditional removal when Layer 9 support is disabled.
- Keep `machined=false`, `portabled=false`, and `nss-mymachines=disabled`; the proof should use standalone `systemd-nspawn`, not machinectl.
- Do not enable any nspawn service or guest unit.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/package.mk` for opt-in image support gates.
- `projects/ROCKNIX/options` for fork-level option defaults.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` for static assertions around build options and package contracts.

**Test scenarios:**
- Static: package syntax remains valid after the conditional removal change.
- Static: options file declares the Layer 9 support option.
- Static: systemd package contains a conditional around nspawn removal rather than unconditional removal.
- Static: no `enable_service systemd-nspawn` or guest unit enablement is introduced.

**Verification:**
- A Layer 9-enabled image should include `/usr/bin/systemd-nspawn`.
- A Layer 9-disabled image should preserve current behavior and remove nspawn.

- [x] **Unit 2: Define Layer 9 guest rootfs contract and safety boundaries**

**Goal:** Document the expected guest layout, allowed bind mounts, prohibited host surfaces, and cleanup boundaries before any hardware run.

**Requirements:** R3, R4, R6, R7, R8, R10

**Dependencies:** Unit 1 option shape is known.

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer9-nspawn-guest-contract.md`
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Define the default guest root at `/storage/machines/rocknix-guest`.
- Define allowed Layer 9 default binds as minimal and read-only where possible, such as resolver configuration if needed.
- Explicitly prohibit `/dev/dri`, PipeWire sockets, `/dev/input`, ROM/save directories, Steam/FEX state, and host Wayland/Sway sockets for Layer 9.
- Define cleanup as removing the guest rootfs and optional Layer 9 metadata only; do not touch host `/nix`, profiles, Layer 6 ownership, or Layer 8 daemon config.
- Include a small “what fallback means” section: host unchanged and cleanup possible, not feature equivalence.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer6-activation-contract.md`
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer7-app-experiment-contract.md`

**Test scenarios:**
- Static: contract doc exists and mentions `/storage/machines/rocknix-guest`.
- Static: contract doc explicitly forbids GPU/audio/input passthrough for Layer 9.
- Static: contract doc names the cleanup boundary and host Nix fallback boundary.

**Verification:**
- A reviewer can tell exactly what host surfaces Layer 9 is allowed to touch before reading implementation code.

- [x] **Unit 3: Add read-only Layer 9 diagnostics to nixctl and nix-doctor**

**Goal:** Report whether a device is ready for the manual nspawn proof without starting or mutating guest state.

**Requirements:** R2, R5, R6, R8

**Dependencies:** Unit 2 contract paths are defined.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Extend `nixctl status` with a Layer 9 section; do not add lifecycle subcommands yet.
- Add `nix-doctor` checks for nspawn binary presence, guest root path status, and host fallback health.
- Make paths fixtureable for tests, following Layer 8's `NIX_LAYER8_*` override style. Candidate overrides: `NIX_LAYER9_NSPAWN_BIN`, `NIX_LAYER9_GUEST_ROOT`, `NIX_LAYER9_STATE_DIR`.
- Diagnostics should distinguish unsupported, available, proof-ready, and running based on read-only observations.
- Running detection can be best-effort and should not require machined. Use process/unit/socket evidence available on ROCKNIX rather than `machinectl`.

**Patterns to follow:**
- Layer 8 `print_layer8_status` and `check_layer8` state reporting.
- Existing fixtureable environment override style in `nixctl`, `nix-doctor`, and runtime smoke tests.

**Test scenarios:**
- Happy path: fake nspawn binary + fake guest root -> status reports proof-ready.
- Edge case: nspawn missing -> status/doctor report unsupported without failing unrelated layers.
- Edge case: nspawn present but rootfs missing -> status reports available/rootfs missing.
- Error path: active/running marker without valid prerequisites -> doctor warns or fails with a specific Layer 9 message, depending on severity.
- Integration: existing Layer 4-8 status sections remain present and unchanged.

**Verification:**
- `nixctl status` and `nix-doctor --offline` can evaluate Layer 9 readiness without starting a guest.

- [x] **Unit 4: Add opt-in Layer 9 hardware smoke path**

**Goal:** Provide a repeatable manual hardware validation path that starts a pre-staged guest, proves it works, stops it, and records logs.

**Requirements:** R2, R3, R4, R6, R8, R10

**Dependencies:** Units 1-3 complete; a Layer 9-enabled image is installed; guest rootfs artifact exists.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`

**Approach:**
- Add `LAYER9_SMOKE=1` as an opt-in hardware path; default CI and default runtime smoke should skip it.
- Require explicit rootfs path and nspawn binary readiness. Do not download or generate the guest rootfs in the smoke script.
- Start the guest manually for a bounded proof and write logs to `/tmp/nix-integration-layer9-smoke.log`.
- Stop/kill the guest after proof and verify no enabled guest unit exists.
- Keep this smoke independent of Layer 10 lifecycle commands.

**Patterns to follow:**
- `LAYER8_SMOKE=1` in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`.
- Layer 8 prepare/verify style only if implementation needs reboot validation; otherwise keep Layer 9 as a single manual proof.

**Test scenarios:**
- Happy path: preflight sees nspawn + rootfs, smoke starts guest, observes proof output, stops guest, and reports pass.
- Error path: rootfs missing -> smoke fails before starting anything and points to staging docs.
- Error path: nspawn missing -> smoke fails with Layer 9 unsupported message.
- Cleanup: after a failed or successful smoke, no guest unit is enabled and no guest process remains.
- Integration: Layer 9 smoke does not uninstall, disable, or mutate Layers 4-8.

**Verification:**
- Hardware smoke can be repeated on `thor` without reflashing or deleting host Nix state.

- [x] **Unit 5: Build and deploy a Layer 9-enabled SM8550 image**

**Goal:** Produce the image that preserves `systemd-nspawn` and validate that default boot remains unchanged.

**Requirements:** R1, R2, R5, R9

**Dependencies:** Units 1-4 merged locally; fork build path remains available.

**Files:**
- Modify: `docs/solutions/developer-experience/trigger-fork-rocknix-actions-build-from-nixos-2026-05-05.md` only if the workflow needs new Layer 9-specific notes.
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`

**Approach:**
- Use the existing GitHub Actions dispatch workflow for SM8550 rather than local `make` on NixOS.
- Perform the established ABL precheck before applying a full update.
- After update, confirm `/usr/bin/systemd-nspawn` exists, no guest unit is enabled, SSH returns normally, and Layer 4/8 diagnostics remain healthy.
- Treat any boot, SSH, Sway, EmulationStation, or host Nix regression as Layer 9 No-Go before attempting a guest.

**Patterns to follow:**
- `docs/solutions/developer-experience/trigger-fork-rocknix-actions-build-from-nixos-2026-05-05.md`
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
- Layer 8 post-update validation notes in `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`.

**Test scenarios:**
- Integration: Layer 9-enabled image boots with no guest autostart.
- Integration: `nixctl status` reports Layer 9 available/proof-ready according to rootfs state.
- Integration: Layer 8 daemon can remain disabled or enabled according to operator choice; Layer 9 does not depend on daemon state.
- Error path: if nspawn is absent after update, diagnostics clearly report unsupported and host remains normal.

**Verification:**
- Device is ready for guest smoke with no host regression.

- [x] **Unit 6: Run manual NixOS guest proof and document Go/No-Go**

**Goal:** Validate the actual Layer 9 outcome on `thor` and record whether to proceed to Layer 10.

**Requirements:** R3, R4, R6, R7, R8, R10

**Dependencies:** Unit 5 complete; rootfs artifact staged under the contract path.

**Files:**
- Modify: `docs/solutions/developer-experience/nix-layer-9-nspawn-guest-proof-rocknix-2026-05-05.md` if creating the solution doc during execution.
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Modify: `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md`

**Approach:**
- Stage a minimal aarch64 NixOS/container rootfs under `/storage/machines/rocknix-guest`.
- Run the opt-in Layer 9 smoke, capturing guest boot proof and host state before/after.
- Prove cleanup: guest stopped, no enabled guest unit, rootfs remains inert or is removable, Layers 4/8 still pass diagnostics.
- If proof fails, capture the blocker precisely: missing nspawn dependencies, namespace/cgroup issue, rootfs format issue, guest systemd issue, network/DNS issue, or host impact.
- Make a Go/No-Go decision for Layer 10. Go requires manual guest boot proof plus clean stop and no host regression. No-Go requires a documented blocker and recommended fallback.

**Patterns to follow:**
- Layer 8 solution doc structure: `docs/solutions/developer-experience/nix-layer-8-daemon-mode-rocknix-2026-05-05.md`.
- SM8550 operator evidence style in `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`.

**Test scenarios:**
- Happy path: guest boots and runs trivial proof; host remains healthy after stop.
- Error path: guest fails to boot; smoke captures logs and host diagnostics still pass.
- Error path: guest starts but cannot run Nix proof; decision distinguishes “nspawn works” from “NixOS guest not ready”.
- Cleanup: remove or leave inert guest rootfs without affecting host `/nix`, Layer 6 files, Layer 7 launcher, or Layer 8 daemon config.
- Integration: SSH remains usable before, during, and after guest proof.

**Verification:**
- A written Go/No-Go statement exists with hardware evidence, not assumptions.

## System-Wide Impact

- **Interaction graph:** Layer 9 touches image composition (`packages/sysutils/systemd/package.mk`), layered diagnostics (`nixctl`, `nix-doctor`), and operator-controlled storage under `/storage/machines/rocknix-guest`. It should not affect boot targets, Sway/EmulationStation, Steam/FEX, Layer 6 activation, or Layer 7 launchers.
- **Error propagation:** Guest preparation/start failures should surface through Layer 9 diagnostics and smoke logs only. They must not fail boot or disable host Nix layers.
- **State lifecycle risks:** Guest rootfs and optional metadata can grow under `/storage`. Layer 9 must document removal boundaries and avoid touching host `/nix` unless explicitly chosen as a later variant.
- **API surface parity:** `nixctl status` and `nix-doctor` should both report Layer 9 readiness. No new lifecycle API is introduced in this layer.
- **Integration coverage:** Static checks prove option/package shape; runtime fixtures prove diagnostics; hardware smoke proves nspawn/rootfs behavior on SM8550.
- **Unchanged invariants:** ROCKNIX owns boot/kernel/firmware/UI/update; `/usr` and `/` remain immutable at runtime; daemon mode stays optional; Layer 4 single-user/root Nix remains the host fallback.

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|---|---:|---:|---|
| `systemd-nspawn` binary was removed because ROCKNIX does not want the surface | Medium | Medium | Preserve behind explicit option; no default enablement. |
| nspawn requires runtime support missing from trimmed systemd build | Medium | High | First proof is binary/version + manual smoke; No-Go is acceptable. |
| Guest boot consumes CPU/RAM/I/O and affects games | Medium | High | Layer 9 is manual-start only; no autostart; resource controls deferred but documented as required for Layer 10. |
| Guest rootfs grows into storage needed for saves/shader caches | Medium | Medium | Keep under a known path and document cleanup; defer quotas/catalog to later layer. |
| Host and guest share `/nix` unsafely | Low if default guest-local | High | Default to guest-local rootfs/store; document host-store sharing as non-default. |
| Build/update path regresses host features | Low | High | Follow fork Actions build + ABL precheck + post-update host diagnostics before guest smoke. |
| Failure/fallback claims become vague again | Medium | Medium | Require explicit failure matrix and hardware-backed Go/No-Go in Unit 6. |

## Documentation / Operational Notes

- Update `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md` with Layer 9 prerequisites, smoke command shape, observed evidence, and Go/No-Go decision.
- Create a developer-experience solution doc after execution if the guest proof succeeds or fails in a non-obvious way.
- Keep the existing Layer 9 exploration document as background; this plan becomes the implementation source of truth.
- If Layer 9 succeeds, create a separate Layer 10 plan before adding lifecycle commands or resource-managed service units.

## Sources & References

- **Origin document:** `docs/plans/2026-05-01-001-explore-nixos-on-rocknix-via-nspawn.md`
- Related plan: `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md`
- Related plan: `docs/plans/2026-05-05-004-feat-nix-layer-8-daemon-mode-plan.md`
- Related docs: `docs/solutions/developer-experience/nix-layer-8-daemon-mode-rocknix-2026-05-05.md`
- Related docs: `docs/solutions/developer-experience/trigger-fork-rocknix-actions-build-from-nixos-2026-05-05.md`
- Related docs: `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
- Operator doc: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Related code: `packages/sysutils/systemd/package.mk`
- Related code: `projects/ROCKNIX/options`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Related tests: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Related tests: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Kernel evidence: `projects/ROCKNIX/devices/SM8550/linux/linux.aarch64.conf`
