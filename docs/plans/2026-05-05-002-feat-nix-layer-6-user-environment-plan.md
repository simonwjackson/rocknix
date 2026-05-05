---
title: "feat: Nix Layer 6 — managed user environment"
type: feat
status: completed
date: 2026-05-05
origin: docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md
---

# feat: Nix Layer 6 — managed user environment

## Overview

Layer 6 builds on validated Layer 5 persistent profiles to let Nix manage a narrow, reversible user environment under ROCKNIX storage. The goal is not Home Manager for the handheld and not NixOS-style system ownership. The useful outcome is smaller and safer: a Nix-built activation bundle can install selected storage-local files, report what it owns, refuse unsafe overwrites, roll back partial activation, and deactivate cleanly without touching unrelated user data or ROCKNIX-managed runtime paths.

The initial managed surface should be intentionally boring: storage-local wrapper scripts and profile snippets. Systemd user units and autostart hooks are allowed only as explicitly opt-in later surfaces once the ownership/rollback model is proven.

## Problem Frame

Layer 5 makes persistent CLI tools available through `${HOME}/.nix-profile/bin`, but anything beyond package binaries still requires hand-managed files under `/storage`: custom wrappers in `/storage/bin`, profile snippets under `/storage/.config/profile.d`, optional autostart hooks, and device-specific helper scripts. Those files are powerful because ROCKNIX sources them at runtime, but they are also risky: overwriting a user script or a recovery helper can break SSH/admin workflows, and boot-time hooks can affect UI or game startup.

Layer 6 should introduce a storage-file activation layer with explicit ownership metadata before trying to manage apps, dotfiles, services, or UI experiments. This preserves the layered strategy: each layer adds one usable capability while keeping ROCKNIX as the base OS.

## Requirements Trace

- R1. A Nix-built activation bundle can declare a small set of storage-local files and activate them onto allowed `/storage` surfaces.
- R2. Activation refuses to overwrite user-created or externally modified files by default.
- R3. Activation records every managed target with enough metadata to support status, deactivation, and rollback after partial failure.
- R4. Deactivation removes or restores only files owned by Layer 6 and leaves unrelated `/storage` data untouched.
- R5. `nixctl status` and `nix-doctor --offline` report Layer 6 state, including active generation, managed-file count, conflicts, and storage/backup health.
- R6. Runtime smoke validates activate/use/deactivate, conflict refusal, partial-failure rollback, and reboot persistence using a low-risk test bundle.
- R7. The initial layer manages only storage-local user environment surfaces; it does not mutate `/usr`, boot files, firmware, kernel modules, ROCKNIX package-managed services, or default EmulationStation/Sway startup.
- R8. Existing Layer 1/2 portable wrappers, Layer 4 real Nix, Layer 5 profile tools, SSH recovery, game runtime, and current `/storage/bin` scripts remain unchanged unless the user explicitly activates a bundle that owns new, non-conflicting paths.
- R9. Layer 4 uninstall/reset behavior accounts for active Layer 6 state, either by requiring deactivation first or by performing a safe deactivation before removing the store that may back activated wrappers.

## Scope Boundaries

- Layer 6 does not introduce Home Manager as the default user-environment manager.
- Layer 6 does not auto-activate files at boot.
- Layer 6 does not manage package installation; standard `nix profile` remains the interface for persistent CLI packages.
- Layer 6 does not manage broad dotfile trees, emulator configs, Steam/FEX state, ROM directories, save data, or browser profiles.
- Layer 6 does not manage systemd units by default. `/storage/.config/system.d` is deferred until the file ownership model has passed smoke and manual validation.
- Layer 6 does not replace EmulationStation, Sway, ROCKNIX autostart, or the image update mechanism.

### Deferred to Separate Tasks

- **Systemd/autostart activation:** allow explicitly declared `/storage/.config/system.d` or `/storage/.config/autostart` entries only after the basic activation engine proves rollback safety.
- **Layer 7 Nix-managed apps/UI experiments:** launch user-facing apps after Layer 6 can safely install wrappers/config needed to start them.
- **Home Manager evaluation:** revisit standalone Home Manager only if the narrow activation bundle model proves too limited for real user workflows.

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl` is the existing front door for Layer 4/5 lifecycle and status. Layer 6 should extend it for status/dispatch, not create a second public control plane.
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor` already distinguishes OK/WARN/FAIL checks across Layer 1-5 and has a storage pressure warning model. Layer 6 should add local state checks there.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh` already gates hardware-only validation behind `LAYER4_SMOKE=1` and `LAYER5_SMOKE=1`; Layer 6 should follow the same opt-in pattern.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` is the right place to guard new script presence, syntax, and contract strings.
- `projects/ROCKNIX/packages/tools/nix-integration/profile.d/998-nix-integration.conf` must keep sorting after `098-busybox`; Layer 6 profile snippets should use later storage-side names only when explicitly activated.
- `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md` already names Layer 6 allowed surfaces, forbidden surfaces, and suggested metadata paths.
- `packages/mediacenter/kodi/system.d/kodi-autostart.service` shows ROCKNIX sourcing `/storage/.config/autostart.sh`, but Layer 6 should not touch that path in the first implementation.
- `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/*` write device profile snippets into `/storage/.config/profile.d`; this confirms the storage profile directory is a supported runtime integration surface and also proves it may contain non-Nix-owned files.

### Institutional Learnings

- `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`: profile ordering is behavioral, not cosmetic. Any Layer 6 profile snippet must account for ROCKNIX profile.d lexical ordering and not assume earlier PATH edits survive.
- `docs/solutions/developer-experience/nix-layer-5-persistent-profiles-rocknix-2026-05-05.md`: standard `nix profile` remains the package interface; Layer 6 should manage storage files/config, not hide Nix profile semantics behind a new package manager.
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`: image updates require explicit SM8550 validation; Layer 6 source changes should be included in future image validation checklists, but activation bundles themselves are runtime state under storage.

### External References

- Home Manager provides a mature Nix-based user-environment system, but its broad dotfile/service model is too large for Layer 6's first safe slice on an immutable handheld.
- `numtide/system-manager` and NixOS-style managers demonstrate declarative activation concepts, but they are oriented toward system configuration. Layer 6 should keep to storage-local user files until daemon/system integration is intentionally reopened.
- Dotfile-management discussions around Nix often distinguish package management from file activation. That supports keeping Layer 5 profiles separate from Layer 6 file ownership/rollback.

## Key Technical Decisions

- **Use a narrow activation-bundle contract, not Home Manager initially.** Home Manager is powerful but broad: it can manage many files and services, which is exactly the blast radius Layer 6 is trying to avoid. A small bundle contract lets ROCKNIX prove ownership, conflict detection, and rollback before considering larger managers.
- **Separate package profiles from file activation.** `nix profile install` remains the tool-install interface. Layer 6 activates storage files built by Nix, such as wrappers and profile snippets, rather than reimplementing package install/remove.
- **Make ownership metadata the source of truth.** Layer 6 should not infer ownership from filename conventions alone. Every activated target needs a recorded source, generation, checksum or equivalent content identity, previous-state backup when applicable, and active/inactive state.
- **Refuse conflicts by default.** If a target exists and is not already owned by the current Layer 6 generation, activation should stop before changing it. A future explicit adopt/replace mode can be planned after baseline safety is proven.
- **Stage then swap, never stream changes directly.** Activation should validate every target first, prepare backups/staging, and only then apply changes so partial failure can roll back predictably.
- **Start with wrappers and profile snippets only.** `/storage/bin` and `/storage/.config/profile.d` are useful and low risk compared with boot-time services. Systemd/autostart surfaces remain deferred.
- **Treat runtime paths as policy, not implementation detail.** Allowed and forbidden surfaces should be encoded in the activation script and tested, because a typo in a manifest could otherwise write outside the intended storage boundary.
- **Guard Layer 4 uninstall when Layer 6 is active.** `nixctl uninstall` removes the real Nix store. If Layer 6 files are still active, wrappers or provenance may point at store paths that are about to disappear. The uninstall path should detect this and either require prior deactivation or run the same safe deactivation path before deleting `/nix/store` and `/nix/var`.

## Open Questions

### Resolved During Planning

- **Should Layer 6 use Home Manager immediately?** No. It is a candidate future layer/tool, but the first Layer 6 implementation should be a small, auditable ROCKNIX-specific activation engine.
- **Should Layer 6 install packages?** No. Package installation remains Layer 5's standard `nix profile` responsibility.
- **Should activation happen automatically at boot?** No. Manual activation/deactivation first; boot integration belongs after rollback safety is proven.
- **Should existing user files be adopted automatically?** No. Existing non-owned files are conflicts until the user explicitly chooses a future adopt/replace workflow.

### Deferred to Implementation

- **Exact manifest serialization:** The plan requires a deterministic manifest with target/source/mode/content identity; the exact text format is implementation detail as long as busybox shell can parse it reliably.
- **Exact checksum tool choice:** Prefer existing `sha256sum` when available and fall back consistently if needed; implementation should follow current script helper patterns.
- **Whether rollback stores full copies or metadata-only entries for created files:** Created files can often be removed; replaced files need backups. The exact state format can be finalized while implementing the staging engine.
- **Whether a force/adopt mode is needed:** Do not include it in the first implementation unless hardware validation proves there is a necessary safe use case.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```mermaid
flowchart TB
  Bundle[Nix-built activation bundle in /nix/store]
  Manifest[Manifest: target, source, mode, content identity]
  Activator[nix-layer-activate]
  State[Layer 6 state under /storage/.config/nix-integration]
  Bin[/storage/bin]
  ProfileD[/storage/.config/profile.d]
  Doctor[nix-doctor]
  Status[nixctl status]

  Bundle --> Manifest
  Manifest --> Activator
  Activator -->|preflight allowed surfaces + conflicts| State
  Activator -->|stage + backup + apply| Bin
  Activator -->|stage + backup + apply| ProfileD
  State --> Status
  State --> Doctor
```

Suggested activation states:

| State | Meaning | Allowed next action |
|---|---|---|
| `absent` | No Layer 6 state exists | activate |
| `active` | One generation owns files and metadata is consistent | status, deactivate, activate replacement |
| `conflict` | Requested targets collide with non-owned files | inspect, manually resolve, future adopt mode |
| `partial` | Activation failed after staging/apply began | rollback, doctor failure |
| `inactive` | State exists but no owned files are active | activate, status |

Suggested initial managed surfaces:

| Surface | Initial support | Rationale |
|---|---:|---|
| `/storage/bin/<name>` | yes | Low-risk wrappers; immediately useful; PATH already established. |
| `/storage/.config/profile.d/<name>` | yes | Shell environment integration; known ROCKNIX pattern. |
| `/storage/.config/autostart` or `/storage/.config/autostart.sh` | no | Can affect UI startup; defer until rollback is proven. |
| `/storage/.config/system.d/<unit>` | no | Service ordering/failure risk; require separate opt-in unit. |
| `/usr`, `/flash`, `/boot` | never | ROCKNIX-owned immutable/system surfaces. |

## Implementation Units

- [x] **Unit 1: Define the Layer 6 activation contract and state layout**

**Goal:** Establish the allowed surfaces, manifest expectations, state directory, and safety invariants before writing activation behavior.

**Requirements:** R1, R2, R3, R7, R8

**Dependencies:** Completed Layer 5 profile contract and current `nixctl`/`nix-doctor` paths.

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer6-activation-contract.md`
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Define a minimal activation bundle as a directory containing a manifest and file payloads, preferably produced by Nix into the store but testable from a fixture directory.
- Document required manifest fields: target runtime path, source path inside the bundle, file type, mode, and content identity.
- Define state under `/storage/.config/nix-integration/` with subdirectories for current state, backups, and activation logs.
- Encode allowed surfaces and forbidden surfaces in the contract so implementation has a fixed policy.
- State explicitly that first-pass activation refuses all non-owned conflicts; adopt/force is out of scope.

**Patterns to follow:**
- Layer 5 plan style in `docs/plans/2026-05-05-001-feat-nix-layer-5-persistent-profiles-plan.md`.
- Storage surface list in `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md`.
- Profile ordering learning in `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`.

**Test scenarios:**
- Test expectation: none for runtime behavior — this unit is contract/documentation plus static guard only.
- Static: the contract doc names allowed surfaces, forbidden surfaces, conflict policy, and state directory.
- Static: Layer 6 is mentioned in SM8550 operator docs as planned/experimental, not as automatically active.

**Verification:**
- An implementer can build the activation script against a stable contract without inventing target paths, state paths, or conflict semantics.

---

- [x] **Unit 2: Implement `nix-layer-activate` with preflight, activation, deactivation, rollback, and status**

**Goal:** Add the low-level activation engine that safely applies and removes a Nix-built user-environment bundle under allowed storage surfaces.

**Requirements:** R1, R2, R3, R4, R7, R8

**Dependencies:** Unit 1 contract.

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-layer-activate`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/layer6-user-env/manifest`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/layer6-user-env/files/bin/rocknix-layer6-smoke`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/layer6-user-env/files/profile.d/999-rocknix-layer6-smoke`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Implement `status`, `plan`/`preflight`, `activate`, `deactivate`, and `rollback` modes in one script.
- Validate the manifest completely before touching targets: bundle structure, target path policy, source existence, executable bit/mode, duplicate targets, and conflicts with non-owned files.
- Stage changes and backups under the Layer 6 state directory before replacing any target.
- Record ownership for every target so deactivation can distinguish Layer 6 files from user files.
- Roll back automatically on activation failure when possible and leave a clear `partial` state if manual recovery is required.
- Keep the script POSIX/busybox-shell friendly to match existing nix-integration scripts.

**Execution note:** Start with characterization fixtures that cover conflicts and rollback before applying changes to real `/storage` surfaces.

**Patterns to follow:**
- Helper style and safety gates in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`.
- OK/WARN/FAIL separation from `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`.
- Static script checks in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`.

**Test scenarios:**
- Happy path: activating a fixture bundle creates one wrapper under the configured storage bin directory and one profile snippet under the configured storage profile.d directory, records both as owned, and reports active status.
- Happy path: deactivating the fixture removes only the owned files and records an inactive/clean state.
- Happy path: re-activating the same generation is idempotent and does not duplicate metadata or backups.
- Edge case: a manifest with duplicate targets fails preflight before any target is changed.
- Edge case: a target outside allowed surfaces is rejected before any target is changed.
- Edge case: an existing non-owned file at a target path causes a conflict and is left byte-for-byte unchanged.
- Error path: if activation fails after staging one target, rollback restores previous files and doctor/status can report whether cleanup succeeded.
- Integration: activating and deactivating the fixture does not alter existing `/storage/bin/nix`, `/storage/bin/nix-portable`, or `${HOME}/.nix-profile/bin` state.

**Verification:**
- The activation engine can safely manage a tiny storage environment with observable owned-file state, conflict refusal, clean deactivation, and recoverable partial failures.

---

- [x] **Unit 3: Add `nixctl` Layer 6 front-door reporting and dispatch**

**Goal:** Make Layer 6 discoverable from the existing `nixctl` front door without turning `nixctl` into a package manager.

**Requirements:** R3, R4, R5, R8, R9

**Dependencies:** Unit 2 activation script.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Add a Layer 6 block to `nixctl status` that reports active generation, managed-file count, state directory, and any conflict/partial state reported by `nix-layer-activate status`.
- Add narrowly scoped dispatch for Layer 6 activation operations, such as a `user-env` or `env` subcommand group, while keeping package installation/removal as standard `nix profile` operations.
- Keep status read-only and useful when no Layer 6 state exists.
- Ensure help text distinguishes Layer 5 profile packages from Layer 6 storage-file activation.
- Update `nixctl uninstall` to detect active Layer 6 state before removing real Nix. The first implementation should prefer a conservative refusal with a clear deactivation instruction unless a non-interactive safe-deactivation path is already proven by Unit 2.

**Patterns to follow:**
- Existing Layer 5 status block in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`.
- Existing `doctor` delegation behavior in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`.

**Test scenarios:**
- Happy path: with no Layer 6 state, `nixctl status` reports Layer 6 inactive/unconfigured without error.
- Happy path: after activating the smoke bundle, `nixctl status` reports Layer 6 active with the expected managed-file count.
- Edge case: if `nix-layer-activate` is missing or not executable, `nixctl status` reports Layer 6 unavailable rather than crashing.
- Error path: if Layer 6 state is partial, `nixctl status` surfaces the partial state and points to rollback/deactivation guidance.
- Error path: `nixctl uninstall --yes` with active Layer 6 state refuses or safely deactivates according to the chosen policy before removing `/nix/store`.
- Integration: existing `status`, `install`, `upgrade`, `uninstall`, and `doctor` subcommands retain their Layer 4/5 behavior when Layer 6 is inactive.

**Verification:**
- Operators can discover whether a managed user environment is active and which command to use next from `nixctl status`/help output.

---

- [x] **Unit 4: Extend `nix-doctor` with Layer 6 ownership and conflict checks**

**Goal:** Make user-environment state diagnosable before it can surprise the user during SSH or UI startup.

**Requirements:** R2, R3, R4, R5, R8

**Dependencies:** Units 2 and 3.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Check whether Layer 6 state exists; absence is OK.
- Validate that every owned target exists when active, matches recorded metadata, and remains inside allowed surfaces.
- Warn if owned profile snippets sort before known reset points or if they shadow existing commands unexpectedly.
- Fail on partial state, missing backups for replaced files, dangling source references, owned wrappers that reference missing store paths, or owned files that were modified externally after activation.
- Preserve `--offline`: Layer 6 checks are local and should still run when network checks are skipped.

**Patterns to follow:**
- `check_layer5` in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor` for optional-layer checks.
- `check_profile_command_conflicts` warning behavior for non-fatal shadowing.

**Test scenarios:**
- Happy path: no Layer 6 state produces an OK or neutral diagnostic and no failure.
- Happy path: an active smoke bundle produces OK lines for state directory, generation, owned targets, and backups.
- Edge case: an owned profile snippet with unsafe ordering emits a warning that names the snippet and ordering concern.
- Error path: deleting an owned target after activation causes doctor to fail with the missing target path.
- Error path: externally modifying an owned target causes doctor to fail or warn according to the recorded metadata policy.
- Error path: partial activation state causes doctor to fail and recommend rollback.
- Error path: after a simulated missing-store-source condition, doctor reports active Layer 6 files that now reference unavailable Nix store paths.
- Integration: `nix-doctor --offline` still validates Layer 1-5 local state and adds Layer 6 checks without attempting network access.

**Verification:**
- `nix-doctor` clearly distinguishes inactive, healthy active, warning-only shadowing, and broken/partial Layer 6 states.

---

- [x] **Unit 5: Add opt-in Layer 6 runtime smoke and reboot persistence coverage**

**Goal:** Prove the user-environment activation model on hardware without making default CI write to real storage surfaces or require network/reboot.

**Requirements:** R1, R2, R3, R4, R5, R6, R8

**Dependencies:** Units 2-4.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Add `LAYER6_SMOKE=1`, independent of `LAYER4_SMOKE=1` and `LAYER5_SMOKE=1`, with explicit prerequisites: Layer 4 real Nix installed, Layer 5 profile shell contract healthy, and writable storage.
- Build or use a deterministic smoke activation bundle that creates a uniquely named wrapper and profile snippet, avoiding command names likely to conflict with ROCKNIX tools.
- Validate direct-path use, fresh profile-sourced shell behavior, `nixctl status`, and `nix-doctor --offline`.
- Test conflict refusal by creating a temporary non-owned file at a unique target and confirming activation refuses without modifying it.
- Test deactivation cleanup and optional reboot persistence using a `prepare|verify` mode like Layer 5.
- Never delete pre-existing user files unless they are recorded as owned by the smoke generation.

**Patterns to follow:**
- Layer 5 smoke structure and reboot verification mode in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`.
- Log naming and opt-in wording from the Layer 4/5 smoke sections.

**Test scenarios:**
- Happy path: `LAYER6_SMOKE=1` activates the smoke bundle, runs the managed wrapper, sources the managed profile snippet in a fresh shell, and deactivates cleanly.
- Happy path: `LAYER6_SMOKE=1 LAYER6_REBOOT_VERIFY=prepare` leaves the smoke environment active for manual reboot verification.
- Happy path: after reboot, `LAYER6_SMOKE=1 LAYER6_REBOOT_VERIFY=verify` confirms owned files persist and the wrapper still runs, then leaves cleanup instructions.
- Edge case: a smoke target already exists and is not owned; activation refuses and leaves the file unchanged.
- Edge case: smoke state from a previous interrupted run is detected and either rolled back safely or reported with clear recovery instructions.
- Error path: Layer 4 or Layer 5 prerequisites are absent; smoke exits with a clear prerequisite failure and does not create state.
- Integration: after smoke cleanup, `/storage/bin/nix`, `/storage/.nix-profile/bin/nix`, existing custom scripts, and profile PATH ordering still behave as before.

**Verification:**
- Hardware smoke demonstrates activate/use/status/doctor/deactivate and optional reboot persistence without destabilizing default CI or user storage.

---

- [x] **Unit 6: Update operator docs and capture the Layer 6 learning**

**Goal:** Make the new activation layer understandable, reversible, and discoverable before using it for Layer 7 apps/UI experiments.

**Requirements:** R4, R5, R6, R7, R8

**Dependencies:** Units 1-5 implemented and hardware-validated.

**Files:**
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Modify: `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md`
- Modify: `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md`
- Create: `docs/solutions/developer-experience/nix-layer-6-managed-user-environment-rocknix-2026-05-05.md`

**Approach:**
- Document Layer 6 only after hardware validation identifies the exact command shapes and output states.
- Include examples for status, activation, deactivation, rollback, conflict handling, and full Layer 4 reset implications.
- Record the validated device/image/Nix version and the managed surfaces used in smoke.
- Update the older layered roadmap/handoff to mark Layer 6 implemented and note any intentional deviations from the original sketch.
- Cross-link Layer 5 and profile.d ordering learnings so future app/UI layers do not bypass activation safety.

**Patterns to follow:**
- Layer 5 documentation in `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`.
- Compound doc shape in `docs/solutions/developer-experience/nix-layer-5-persistent-profiles-rocknix-2026-05-05.md`.

**Test scenarios:**
- Test expectation: none — documentation-only after implementation is validated.
- Editorial: docs clearly separate standard `nix profile` package operations from Layer 6 storage-file activation.
- Editorial: docs include stopping rules and recovery steps for partial activation or bad managed files.

**Verification:**
- A future operator can identify active Layer 6 state, activate a known-good bundle, deactivate it, recover from conflicts/partial activation, and decide whether Layer 7 is safe to start.

## System-Wide Impact

- **Interaction graph:** Layer 6 touches storage-local shell wrappers, storage profile snippets, `nixctl`, `nix-doctor`, and optional future autostart/systemd surfaces. It must not change ROCKNIX UI startup unless a later opt-in unit explicitly does so.
- **Error propagation:** Activation failures should fail closed before target changes when possible; if changes already began, rollback should restore prior state or leave a clear partial state that doctor fails.
- **State lifecycle risks:** Backups and activation generations can accumulate under `/storage/.config/nix-integration`; docs and doctor should make cleanup visible without deleting user data automatically.
- **API surface parity:** `nix-layer-activate` is the lower-level engine; `nixctl status`/help and `nix-doctor` must expose the same active/inactive/partial state so operators do not need to inspect metadata manually.
- **Integration coverage:** Unit tests/fixtures can prove policy decisions, but hardware smoke is required for real `/storage` behavior, profile.d sourcing, and reboot persistence.
- **Unchanged invariants:** ROCKNIX owns boot, kernel, firmware, image updates, package-managed system services, EmulationStation/Sway default startup, and game/runtime paths. Layer 6 owns only explicitly activated storage-local files recorded in its metadata.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Activation overwrites a user-created script | Refuse non-owned target conflicts by default; require explicit future adopt/replace planning before changing this. |
| Partial activation leaves broken PATH/profile state | Stage all changes, record backups first, roll back on failure, and make partial state a doctor failure. |
| Managed snippets run in the wrong profile order | Encode profile ordering guidance in docs/tests and warn in doctor for suspicious names. |
| Layer 6 becomes a hidden package manager | Keep `nix profile` as package install/remove; Layer 6 only activates storage files from a bundle. |
| Backups/generations consume storage | Report backup/state size in status/doctor and document manual cleanup after deactivation. |
| Future autostart/systemd support affects UI startup | Defer those surfaces until wrapper/profile activation is boring; require separate opt-in implementation. |
| The activation bundle format becomes too custom | Keep the manifest minimal and Nix-store friendly; revisit Home Manager only if real workflows outgrow the narrow contract. |
| Layer 4 uninstall strands active Layer 6 files | Teach `nixctl uninstall` to detect active Layer 6 state and require or perform safe deactivation before deleting real Nix store state. |

## Documentation / Operational Notes

- Add Layer 6 to `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md` only as experimental until hardware smoke passes.
- Document runtime paths as ROCKNIX device paths, but keep repository references repo-relative.
- Include rollback commands near activation examples, not only in a troubleshooting section.
- Make it explicit that Layer 6 should be deactivated before `nixctl uninstall --yes`, and that the uninstall command should guard against active Layer 6 state because removing `/nix/store` can break activated wrappers whose sources or embedded paths live in the store.
- Future Layer 7 app launchers should use Layer 6 activation rather than hand-copying wrappers into `/storage/bin`.

## Sources & References

- **Origin plan:** [docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md](docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md)
- Prior handoff: [docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md](docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md)
- Layer 5 plan: [docs/plans/2026-05-05-001-feat-nix-layer-5-persistent-profiles-plan.md](docs/plans/2026-05-05-001-feat-nix-layer-5-persistent-profiles-plan.md)
- SM8550 docs: [documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md](documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md)
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Related learning: [docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md](docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md)
- Related learning: [docs/solutions/developer-experience/nix-layer-5-persistent-profiles-rocknix-2026-05-05.md](docs/solutions/developer-experience/nix-layer-5-persistent-profiles-rocknix-2026-05-05.md)
- External reference: `https://github.com/nix-community/home-manager`
- External reference: `https://github.com/numtide/system-manager`
