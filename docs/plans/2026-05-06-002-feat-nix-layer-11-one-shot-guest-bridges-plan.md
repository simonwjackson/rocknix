---
title: feat: Add Layer 11 one-shot guest-backed bridges
type: feat
status: completed
date: 2026-05-06
origin: docs/plans/2026-05-06-001-feat-nix-layer-10-managed-guest-operations-plan.md
validated_on: 2026-05-06
validation_scope: one-shot bridge hardware Go; persistent services and guest SSH deferred
---

# feat: Add Layer 11 one-shot guest-backed bridges

## Overview

Layer 11 should formalize the narrow bridge shape that was live-proven on `thor`: a host-owned entrypoint under `/storage` invokes a bounded guest command through Layer 10 proof-mode `nixctl guest run`, returns output to the host caller, and leaves no guest process running afterward.

This is intentionally smaller than the broader Layer 11 idea of guest-backed services. It does not introduce long-running daemons, alternate-port guest SSH, graphics/audio/input passthrough, autostart, or dependency from ROCKNIX UI/SSH services to the guest. Those remain blocked until Layer 10 bootable `start`/`stop` and resource-bound lifecycle are hardware-validated with a real bootable rootfs.

## Implementation Status

Implemented on branch `feat/nix-layer-11-one-shot-guest-bridges` with static, fixture runtime, and SM8550 hardware coverage.

Implemented command surface:

```text
nixctl bridge status
nixctl bridge preflight <name>
nixctl bridge install <name> -- <guest-command...>
nixctl bridge run <name>
nixctl bridge remove <name>
```

Fixture validation covers bridge status/preflight, unsafe names, owned install/reinstall, non-owned target conflict refusal, wrapper execution through fake `systemd-nspawn`, metadata cleanup, doctor reporting, and the opt-in `LAYER11_SMOKE=1` hardware smoke path.

Hardware-Go passed for the one-shot bridge scope on `thor` with build `d5d5aa3b9812562495f2f94ebc88950f9c7d7d40`. Persistent services, guest SSH, autostart, graphics/audio/input, and bootable-guest-dependent bridges remain out of scope.

## Problem Frame

Layer 10 proof mode gives ROCKNIX a safe way to run one-shot commands inside a minimal Nix-backed guest rootfs. The live Layer 11 prototype showed the next useful capability: a normal host command can act as a bridge to that guest capability without requiring operators to remember the `nixctl guest run ...` invocation.

The problem to solve is packaging that pattern so it is repeatable, inspectable, reversible, and governed by the same safety boundary as Layer 10. Bridge installation must never mutate `/usr`, enable system services, replace host SSH, or leave guest processes behind.

## Requirements

- R1. Provide a Layer 11 bridge control surface under `nixctl` for status, preflight, install, remove, and run/test operations.
- R2. Install bridges only into storage-owned user surfaces, initially `/storage/bin` and optionally Layer 6-owned profile snippets later.
- R3. Require each bridge to declare its guest command explicitly; do not accept arbitrary host-provided shell fragments at install time.
- R4. Use Layer 10 proof-mode `nixctl guest run` as the execution path for the first implementation.
- R5. Refuse installation when Layer 10 guest state is unsupported, invalid, running, or not proof-ready/bootable-ready for safe one-shot execution.
- R6. Leave no guest process running after a bridge command returns.
- R7. Make rollback simple: `nixctl bridge remove <name>` deletes only Layer 11-owned files and metadata.
- R8. Track ownership metadata so bridges do not overwrite non-owned `/storage/bin` files.
- R9. Add static and fixture runtime coverage for command surface, ownership refusal, no autostart, and no persistent guest process assumptions.
- R10. Hardware-validate on `thor` with at least one bridge that returns `nix (Nix) 2.34.7` from the guest and then restores `running: no`.

## Non-Goals

- No alternate-port guest SSH.
- No long-running guest services.
- No boot autostart.
- No graphics, audio, input, Wayland, ROM, save, Steam, FEX, or browser-profile passthrough.
- No host SSH takeover or replacement.
- No generated systemd units for Layer 11 bridges in the first increment.
- No arbitrary unreviewed internet flakes or user-provided shell scripts as root.
- No bootable-root-dependent bridges until Layer 10 bootable lifecycle is hardware-Go.

## Key Decisions

| Decision | Rationale |
|---|---|
| Start with one-shot bridges only | This matches the live proof and avoids depending on unvalidated bootable guest lifecycle. |
| Reuse Layer 10 proof-mode execution | Keeps Layer 11 small and inherits `--register=no`, rootfs-mode checks, and no-residual-process expectations. |
| Store bridge metadata separately from Layer 6 | Layer 6 owns generic user-env files; Layer 11 needs bridge-specific command provenance and guest execution metadata. |
| Install into `/storage/bin` first | It is already the reversible user command surface used by prior layers and avoids runtime mutation of `/usr`. |
| Treat non-owned file conflicts as hard failures | A bridge installer must not overwrite user scripts or earlier experiment artifacts. |
| Keep guest SSH out of scope | SSH is a persistent service and would require bootable guest lifecycle validation, port allocation, auth policy, and recovery design. |

## Proposed Bridge Model

Layer 11 metadata root:

```text
/storage/.config/nix-integration/layer11
```

Initial installed bridge surface:

```text
/storage/bin/<bridge-name>
```

A bridge record should capture:

```text
name=<bridge-name>
target=/storage/bin/<bridge-name>
guest_root=/storage/machines/rocknix-guest
command=/usr/bin/nix --version
installed_at=<utc timestamp>
```

The generated host wrapper should be boring and auditable:

```text
exec /usr/bin/nixctl guest run <declared guest command>
```

The exact serialization format is an implementation decision, but it must be line-oriented or otherwise easy to inspect on-device with busybox tools.

## Implementation Units

### Unit 1: Define the Layer 11 bridge contract *(complete)*

**Goal:** Make the safety boundary explicit before adding commands.

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer11-bridge-contract.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`

**Approach:**
- Document responsibilities, forbidden surfaces, metadata paths, cleanup boundaries, and Go/No-Go criteria.
- State that Layer 11 starts with one-shot proof-mode bridges only.
- Require host SSH to remain the recovery path.
- Require no autostart and no generated/enabled systemd services.

**Test scenarios:**
- Static checks confirm the contract doc is packaged.
- Static checks reject accidental `systemctl enable`, guest SSH wording that implies support, or missing Layer 10 dependency notes.

### Unit 2: Add read-only bridge status and preflight *(complete)*

**Goal:** Let operators inspect bridge readiness without installing or running anything.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Add `nixctl bridge status` and `nixctl bridge preflight <name>`.
- Report Layer 11 metadata root, installed bridge count, target path, and Layer 10 one-shot readiness.
- Preflight should pass only when Layer 10 is proof-ready or bootable-ready and not currently running.
- `nix-doctor --offline` should report inactive Layer 11 as OK and flag stale/unsafe bridge metadata.

**Test scenarios:**
- No metadata -> status reports inactive/available, doctor passes.
- Layer 10 absent/invalid/running -> bridge preflight refuses with a clear message.
- Stale bridge metadata with missing target -> doctor warns or fails consistently.

### Unit 3: Implement bridge install/remove with ownership metadata *(complete)*

**Goal:** Create and remove host bridge wrappers safely.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Add `nixctl bridge install <name> -- <guest-command...>`.
- Add `nixctl bridge remove <name>`.
- Default target is `/storage/bin/<name>`.
- Refuse names containing path separators, whitespace, shell metacharacters, or dot-dot traversal.
- Refuse to overwrite any existing target unless Layer 11 metadata proves ownership.
- Generated wrappers call `/usr/bin/nixctl guest run` with a fixed argument vector derived from install arguments.
- Removal deletes only the owned wrapper and its metadata.

**Test scenarios:**
- Happy path install creates wrapper and metadata under fixture directories.
- Existing non-owned target refuses install.
- Reinstall of owned bridge updates metadata and wrapper atomically.
- Remove deletes owned wrapper and metadata only.
- Unsafe bridge names are rejected.

### Unit 4: Add bridge run/test and hardware smoke *(complete; hardware validated on `thor`)*

**Goal:** Validate that the installed bridge works as a host command and leaves no guest running.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`

**Approach:**
- Add `nixctl bridge run <name>` as a convenience for invoking an installed bridge.
- Add opt-in `LAYER11_SMOKE=1` runtime smoke that installs a fixture bridge, runs it, verifies guest output, verifies Layer 10 `running: no`, and removes it.
- Hardware smoke on `thor` should use the proof root and a bridge equivalent to `/usr/bin/nix --version`.

**Test scenarios:**
- Bridge run prints guest output.
- Failed guest command propagates non-zero exit and leaves Layer 10 state failed or restored according to Layer 10 semantics.
- Successful run leaves no `systemd-nspawn` process.
- Smoke cleanup removes bridge wrapper and metadata.

### Unit 5: Update docs and Layer 12 handoff *(complete; one-shot bridge Go)*

**Goal:** Record validation evidence and define the next boundary.

**Files:**
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Modify: `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md`
- Modify: `docs/plans/2026-05-06-002-feat-nix-layer-11-one-shot-guest-bridges-plan.md`
- Create: `docs/solutions/developer-experience/nix-layer-11-one-shot-guest-bridges-rocknix-2026-05-06.md` if hardware validation produces reusable learnings or gotchas.

**Approach:**
- Mark which bridge mode is Go on hardware.
- Keep persistent services, alternate-port SSH, and graphical/audio/input bridges explicitly deferred.
- Hand off Layer 12 as declarative bridge/profile composition only after Layer 11 one-shot bridge ownership and cleanup are proven.

**Test scenarios:**
- Docs include exact run ID/build ID and hardware smoke output.
- Docs distinguish one-shot bridge Go from persistent service No-Go.
- Future agent can decide whether alternate-port SSH is still blocked without rereading implementation diffs.

## Hardware Validation Plan

Hardware validation used a rebuilt image that includes the Layer 11 implementation. Before rebooting into updater on SM8550, the ABL slot precheck was repeated and both slots matched, so the bootloader flash path was skipped.

Minimum proof on `thor`:

```text
nixctl bridge status
nixctl bridge install layer11-nix-version -- /usr/bin/nix --version
/storage/bin/layer11-nix-version
nixctl guest status   # must show running: no
nix-doctor --offline
nixctl bridge remove layer11-nix-version
```

Hardware validation evidence (2026-05-06):

```text
GitHub Actions run: 25447891714
Artifact: ROCKNIX-update-SM8550-20260506
Installed BUILD_ID: d5d5aa3b9812562495f2f94ebc88950f9c7d7d40
Installed BUILD_BRANCH: feat/nix-layer-11-one-shot-guest-bridges
ABL precheck: abl_a MATCH, abl_b MATCH (no bootloader flash)
Default bridge state: bridges: 0, eligible: available: Layer 10 one-shot guest execution ready
Bridge installed: /storage/bin/layer11-nix-version
Bridge output: nix (Nix) 2.34.7
Post-run Layer 10 state: proof-ready, running: no
nix-doctor --offline: passed with expected pre-existing warnings
Bridge cleanup: wrapper and metadata removed; bridges: 0
Packaged smoke script: not installed in image, so manual command sequence is the hardware evidence
```

Go / No-Go decision:

- Go: Layer 11 one-shot guest-backed bridges on SM8550/Odin2 Portal.
- No-Go: persistent services, alternate-port guest SSH, autostart, graphics/audio/input passthrough, and bootable-guest-dependent bridges remain blocked until Layer 10 bootable lifecycle validation passes.

No-Go conditions:

- host SSH drops or becomes dependent on the guest
- bridge install overwrites a non-owned file
- any guest process remains after the bridge exits
- any boot autostart or systemd enablement appears
- bridge cleanup touches host Nix, ROM/save, Steam/FEX, or unrelated `/storage` files

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---:|---:|---|
| Bridge wrappers become arbitrary root shell execution | Medium | High | Store fixed argv, reject shell fragments/metacharacters, generate simple wrappers. |
| Non-owned `/storage/bin` files are overwritten | Medium | High | Ownership metadata and hard conflict refusal. |
| Operators mistake one-shot bridge for service support | Medium | Medium | Naming, docs, and status output explicitly say one-shot/no persistent services. |
| Guest command leaves stale `running` metadata | Low | Medium | Depend on Layer 10 stale-state fix and add Layer 11 smoke assertion for `running: no`. |
| Bridge command becomes noisy or slow during gameplay | Medium | Medium | No autostart, manual invocation only, bounded one-shot commands. |
| Layer 11 grows into SSH/service exposure too early | Medium | High | Non-goals and Go/No-Go gate require bootable Layer 10 validation first. |

## Sources & References

- Layer 10 plan: `docs/plans/2026-05-06-001-feat-nix-layer-10-managed-guest-operations-plan.md`
- Layer 10 contract: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer10-guest-lifecycle-contract.md`
- Stale state learning: `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
- Layer roadmap: `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md`
- Operator docs: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Control surface: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Health checks: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Runtime smoke: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
