---
title: feat: Add ROCKNIX declarative modules in one build
type: feat
status: active
date: 2026-05-07
---

# feat: Add ROCKNIX declarative modules in one build

## Summary

Build one SM8550 image that introduces a NixOS-like module authoring model for both the Layer 10b NixOS guest and the ROCKNIX host's storage-scoped integration surfaces. This is intended as immediate same-day work to batch into the active SM8550 build stream that already carries the Layer 10/12 cgroup, rootfs, and SSH fixes, not as a later roadmap item. The plan uses the upstream Nix module system where possible, emits existing safe activation artifacts instead of mutating host system paths, and keeps validation ordered behind Layer 10b/12 hardware evidence even if the implementation is batched into one build.

---

## Problem Frame

The current layered Nix integration has useful primitives but no declarative composition layer: Layer 6 activates storage-local files, Layer 10 manages a guest rootfs, Layer 11 creates one-shot bridges, and Layer 12 configures guest SSH. Operators still compose those surfaces imperatively with `nixctl` commands and hand-edited files. To make this feel like NixOS without turning ROCKNIX into NixOS, the next layer should let contributors write modules that declare desired storage-owned host behavior and guest NixOS behavior while preserving ROCKNIX as the base OS and recovery plane.

---

## Assumptions

*This plan was authored from the current conversation without a separate requirements document. The items below are agent inferences that should be reviewed before implementation proceeds.*

- "All of this for one build" means the module work should be implemented now and batched into the same same-day SM8550 build stream as the last build triggered for the Layer 10/12 fixes, rather than waiting for a later conceptual Layer 13 image.
- If the currently running build cannot include the new commits, the execution path should cancel/supersede it as early as practical and dispatch a replacement build from the combined head; if cancellation is no longer useful, trigger the combined build immediately alongside today's run rather than waiting for hardware validation to finish.
- The first module layer should prioritize safe composition over full NixOS parity: typed options, imports, examples, activation, status, rollback, and smoke coverage are in scope; arbitrary host service management is not.
- Host-side modules should compile to existing layer artifacts such as Layer 6 activation bundles and Layer 12 metadata, not to ad hoc shell mutations.
- Guest-side modules can use real NixOS modules because the guest is a NixOS container rootfs; rebuilding/importing the guest remains an explicit operator action.

---

## Requirements

- R1. Ship a declarative module authoring model in a single SM8550 image, batched into today's active Layer 10/12 build stream rather than deferred to a later build cycle.
- R2. Preserve ROCKNIX as the host OS: runtime activation must not mutate `/usr`, `/flash`, `/boot`, host `/etc`, host SSH config, firmware, kernel modules, ROMs, saves, Steam/FEX state, or package-managed services.
- R3. Support real NixOS-style modules for the guest rootfs by importing module files into the guest flake and rebuilding/importing the guest explicitly.
- R4. Support a storage-scoped host module system that can declare wrappers, profile snippets, PATH-visible package environments, Layer 11 bridges, and Layer 12 guest SSH metadata through typed options.
- R5. Reuse existing activation and ownership boundaries: Layer 6 for storage files, Layer 11 for one-shot bridge wrappers, Layer 12 for guest SSH metadata, and Layer 10 for guest lifecycle.
- R6. Provide a `nixctl` command surface for module status, preflight/evaluation, apply, deactivate/rollback, and guest module workspace/build/import operations.
- R7. Keep guest autostart disabled and keep guest start/stop manual; modules may configure metadata but must not start the guest during boot.
- R8. Keep Layer 12 SSH key-only, fixed to the validated alternate port `2222` until dynamic guest port generation is separately designed.
- R9. Provide examples that contributors can copy and edit without touching image-owned files.
- R10. Add static and runtime smoke coverage that proves module evaluation, activation, conflict refusal, rollback, guest module import shape, and Layer 12 guardrails.
- R11. Make `nix-doctor` report module state and detect partial or drifted module activation.
- R12. Document the Go/No-Go order: Layer 10b bootable lifecycle, Layer 12 SSH, then module workflows.

---

## Scope Boundaries

- This plan does not convert ROCKNIX into NixOS or replace the ROCKNIX image/update system.
- This plan does not introduce host boot-time module activation or guest autostart.
- This plan does not manage arbitrary host systemd units beyond existing storage-owned integration surfaces.
- This plan does not add graphics, audio, input, Wayland, ROM/save, Steam, FEX, browser-profile, or broad dotfile passthrough.
- This plan does not make the guest a remote builder.
- This plan does not add password authentication, default credentials, shipped authorized keys, or port `22` exposure.
- This plan does not require dynamic Layer 12 SSH ports; the first module layer uses the currently validated fixed port `2222`.
- This plan does not require a new package manager UX for normal Nix profile usage; package-like host module outputs should be built as reversible environments managed by the module layer.

### Deferred to Follow-Up Work

- Dynamic guest SSH port generation: later work can generate guest-side OpenSSH config per selected port instead of enforcing fixed `2222`.
- Rich host service management: storage-local services, timers, and autostart policy need their own safety contract after wrapper/profile/bridge surfaces are boring.
- UI integration for module enable/disable flows.
- Graphics/audio/input passthrough modules.
- A public module registry or remote module distribution mechanism.

---

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl` owns operator-facing commands for Layer 6, Layer 10, Layer 11, and Layer 12. New module commands should extend this front door instead of adding a parallel CLI.
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-layer-activate` provides a narrow, reversible Layer 6 activation engine for `bin` and `profile.d` surfaces with owned-file tracking and rollback.
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor` is the health-reporting surface that must report module state and drift.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix` and `projects/ROCKNIX/packages/tools/nix-integration/guest/rocknix-guest.nix` define the guest rootfs and can become the base for guest modules/profiles.
- `projects/ROCKNIX/packages/tools/nix-integration/package.mk` currently installs scripts and tests; it will need to install module templates/evaluator files under a read-only image path such as `/usr/lib/nix-integration/modules`.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh` already supports layered opt-in smoke modes and fixture-backed regression tests.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` is the right place for static guardrails around forbidden host paths, port `22`, and accidental `--port=tcp` reintroduction.
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer10-guest-lifecycle-contract.md` and `projects/ROCKNIX/packages/tools/nix-integration/docs/layer12-guest-ssh-contract.md` define boundaries the module layer must not weaken.

### Institutional Learnings

- `docs/solutions/developer-experience/nix-layer-6-managed-user-environment-rocknix-2026-05-05.md`: storage activation must be narrow, owned, reversible, conflict-refusing, and inspectable.
- `docs/solutions/best-practices/stage-nspawn-rootfs-from-onboard-nix-closures-rocknix-2026-05-06.md`: guest rootfs work needs explicit `/usr/bin/nix`/shell entry points and must use `--register=no` because machined is absent.
- `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`: durable metadata cannot prove liveness; live process/unit evidence must remain authoritative.
- `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`: PATH/profile changes should be explicit and layered so later snippets do not silently erase Nix paths.

### External References

- Nixpkgs module system documentation: `lib.evalModules` provides option declarations, type checking, imports, and config evaluation outside full NixOS.
- nix.dev module system deep dive: custom module systems can evaluate modules by calling `pkgs.lib.evalModules` with a list of modules and then consuming the resulting `config`.

---

## Key Technical Decisions

- Use `lib.evalModules` rather than inventing a custom DSL: this gives contributors a familiar NixOS-like module shape with typed options, imports, and merge semantics.
- Split the module domains but ship them together: guest modules are real NixOS modules imported into the guest rootfs, while host modules are ROCKNIX-specific modules that compile to safe storage-owned activation artifacts.
- Install an image-owned module authoring kit and copy editable workspaces to `/storage`: `/usr/lib/nix-integration/...` remains read-only reference material; user-modified module configs live under `/storage/.config/nix-integration/modules/...`.
- Compile host modules into existing layer artifacts: wrappers/profile snippets go through Layer 6, bridges go through Layer 11, and guest SSH metadata goes through Layer 12. The module layer orchestrates those subsystems instead of bypassing their safety checks.
- Treat module application as explicit and reversible: no boot-time activation, no guest autostart, and no hidden writes outside owned state roots.
- Keep Layer 12 module options fixed to port `2222` for the first version: Thor validation showed the rootfs now bakes direct guest SSH on `2222`; dynamic ports would require generating guest-side OpenSSH config and should be follow-up work.
- Add examples before broad option coverage: a small, validated set of examples is more valuable than a wide unproven option namespace.

---

## Open Questions

### Resolved During Planning

- Should host modules use the real Nix module system or a shell manifest? Use the real Nix module system for authoring, then emit existing shell-friendly activation manifests for runtime safety.
- Should guest and host modules be the same evaluator? No. They should share documentation and CLI concepts, but guest modules are NixOS modules while host modules target ROCKNIX storage surfaces.
- Should modules start the guest or enable autostart? No. Modules may declare metadata; starting/stopping remains manual through Layer 10.

### Deferred to Implementation

- Exact option names and helper layout: final names may adjust while implementing the evaluator, but the option categories and safety boundaries in this plan should hold.
- Exact Nix invocation performance on Thor: implementation should measure whether rootfs builds need stronger progress output, cache checks, or preflight warnings.
- Exact bundle serialization format for module apply: it should be shell-friendly and testable, but implementation can choose line-oriented manifests or multiple generated manifest files as long as Layer 6/11/12 boundaries are preserved.

---

## Output Structure

Expected new or expanded layout:

```text
projects/ROCKNIX/packages/tools/nix-integration/
  docs/
    layer13-modules-contract.md
  guest/
    flake.nix
    rocknix-guest.nix
    modules/
      base.nix
      ssh.nix
      tools.nix
    profiles/
      minimal.nix
      ssh.nix
  modules/
    README.md
    flake.nix
    lib/
      eval-rocknix.nix
      build-activation.nix
    modules/
      base.nix
      storage-files.nix
      package-env.nix
      guest-ssh.nix
      bridges.nix
    examples/
      host-tools.nix
      guest-ssh.nix
      bridge-nix-version.nix
  scripts/
    nixctl
    nix-doctor
    nix-layer-activate
  tests/
    fixtures/modules/
      host-tools.nix
      guest-ssh.nix
      invalid-host-path.nix
      invalid-port22.nix
    nix-integration-runtime-smoke.sh
    nix-integration-static-checks.sh
```

This tree is directional. Implementation may consolidate files if the evaluator is simpler, but the separation between guest NixOS modules and ROCKNIX host modules should remain visible.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```mermaid
flowchart TD
  A[Operator-authored module config under /storage] --> B[nixctl module preflight]
  B --> C[lib.evalModules ROCKNIX host evaluator]
  C --> D[Generated activation plan]
  D --> E[Layer 6 file bundle]
  D --> F[Layer 11 bridge metadata]
  D --> G[Layer 12 SSH metadata]
  E --> H[nix-layer-activate]
  F --> I[nixctl bridge install/remove]
  G --> J[nixctl guest service enable/disable]
  H --> K[/storage-owned runtime surfaces]
  I --> K
  J --> L[manual nixctl guest start]

  M[Guest module workspace under /storage] --> N[nixctl guest module build]
  N --> O[NixOS module imports]
  O --> P[Layer 10b rootfs tarball]
  P --> Q[nixctl guest import --bootable]
```

The important boundary is that module evaluation decides desired state, but existing layer commands still own the risky host mutations. That keeps guardrails centralized and avoids a second activation engine with different safety behavior.

---

## Implementation Units

### U1. Define the Layer 13 module contract

**Goal:** Establish the safety contract, vocabulary, and Go/No-Go criteria for declarative modules before adding command behavior.

**Requirements:** R1, R2, R5, R7, R8, R12

**Dependencies:** None

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer13-modules-contract.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer10-guest-lifecycle-contract.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer12-guest-ssh-contract.md`
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Define Layer 13 as a declarative composition layer over existing Layer 6/10/11/12 primitives.
- Document two domains: guest NixOS modules and ROCKNIX host modules.
- State that host modules are storage-scoped only and must not write host system paths.
- Preserve manual guest lifecycle and no-autostart semantics.
- Add Go/No-Go criteria that require Layer 10b and Layer 12 validation first, then module validation.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer12-guest-ssh-contract.md`
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer10-guest-lifecycle-contract.md`

**Test scenarios:**
- Static: contract file exists and names the forbidden host path classes.
- Static: contract preserves no-autostart and host SSH recovery language.
- Static: contract mentions both guest NixOS modules and storage-scoped ROCKNIX host modules.

**Verification:**
- Reviewers can answer what modules may manage, what they must not touch, and what validation order is required.

---

### U2. Install the module authoring kit and host evaluator

**Goal:** Ship the Nix files needed to evaluate ROCKNIX host modules and copy/edit examples on device.

**Requirements:** R1, R4, R9

**Dependencies:** U1

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/README.md`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/flake.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/lib/eval-rocknix.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/lib/build-activation.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/modules/base.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/modules/storage-files.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/modules/package-env.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/modules/guest-ssh.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/modules/bridges.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Use `pkgs.lib.evalModules` to evaluate host module configs.
- Define a deliberately small first option namespace for storage files, package environments, guest SSH metadata, and bridge declarations.
- Make evaluator output deterministic activation artifacts that shell tests can inspect.
- Install module sources under `/usr/lib/nix-integration/modules` so the image carries a reference kit; editable configs should be copied under `/storage` by a later command unit.

**Execution note:** Implement evaluator behavior test-first with fixture modules before adding broad examples.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-layer-activate`
- `docs/solutions/developer-experience/nix-layer-6-managed-user-environment-rocknix-2026-05-05.md`

**Test scenarios:**
- Happy path: evaluating a fixture host module with one package environment and one wrapper emits a Layer 6-compatible bundle.
- Happy path: evaluating a fixture host module with guest SSH enabled emits Layer 12 metadata intent for port `2222` and an authorized-keys path.
- Happy path: evaluating a bridge fixture emits a Layer 11 bridge declaration with a safe name and command.
- Error path: a module that declares `/usr/bin/foo` or `/etc/foo` as a target fails evaluation/preflight.
- Error path: a module that declares guest SSH port `22` fails evaluation/preflight.
- Edge case: an empty module config evaluates but produces no activation work and reports a no-op state rather than an active generation.

**Verification:**
- Fixture evaluation produces inspectable artifacts without touching `/storage` during pure evaluation.
- Static checks prove module kit files are installed by `package.mk`.

---

### U3. Add `nixctl module` for host module lifecycle

**Goal:** Provide an operator-facing command group for host module initialization, preflight, apply, status, deactivate, and rollback.

**Requirements:** R4, R5, R6, R10, R11

**Dependencies:** U2

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-layer-activate`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Add a `nixctl module` command group that works over a storage-local module workspace, defaulting to a safe path under `/storage/.config/nix-integration/modules/host`.
- `init` copies example config from the image-owned authoring kit to storage without overwriting user edits.
- `preflight` evaluates modules and runs existing layer-specific preflights without applying changes.
- `apply` evaluates modules, stages generated artifacts, then delegates mutations to Layer 6/11/12 commands.
- `status` reports active generation, owned artifacts, drift, and linked layer state.
- `deactivate` and `rollback` reverse only module-owned artifacts and must not touch non-module Layer 6/11/12 state.

**Execution note:** Characterize current Layer 6/11/12 ownership behavior before routing module apply through it.

**Patterns to follow:**
- `cmd_user_env` in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `cmd_bridge_install` / `cmd_bridge_remove` in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `cmd_guest_service_enable` / `cmd_guest_service_disable` in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`

**Test scenarios:**
- Happy path: `nixctl module init` creates a storage workspace when none exists and refuses to overwrite an existing user config unless explicitly allowed.
- Happy path: `nixctl module preflight` evaluates a valid fixture and reports planned Layer 6/11/12 actions without writing active state.
- Happy path: `nixctl module apply` activates a wrapper/profile snippet through Layer 6 and records module ownership.
- Happy path: `nixctl module deactivate` removes only module-owned artifacts and leaves unrelated Layer 6 files untouched.
- Error path: applying a module with a conflicting non-owned `/storage/bin` target fails and preserves the existing file.
- Error path: applying guest SSH metadata while Layer 10b provenance is missing fails through Layer 12 preflight.
- Error path: stale active metadata with missing owned files is reported as drift by `status` and `nix-doctor`.
- Integration: a module that declares a bridge installs a Layer 11-owned wrapper, runs the bridge, and removes it during deactivate.

**Verification:**
- Module lifecycle commands are visible in `nixctl help`.
- `nix-doctor --offline` reports module state consistently with `nixctl module status`.
- Existing `nixctl user-env`, `guest`, and `bridge` commands continue to work independently.

---

### U4. Refactor the guest flake into reusable NixOS modules and profiles

**Goal:** Make the Layer 10b/12 guest rootfs itself module-authored so contributors can write familiar NixOS modules for guest behavior.

**Requirements:** R3, R7, R8, R9, R12

**Dependencies:** U1

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/rocknix-guest.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/modules/base.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/modules/ssh.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/modules/tools.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/minimal.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/ssh.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Split the existing guest config into small NixOS modules: base container behavior, minimal tools, and locked-down SSH-on-2222.
- Keep `boot.isContainer = true`, writable `/etc` rootfs shape, regular `authorized_keys.d/root`, and `/usr/bin/nix` compatibility from the current Layer 12 fixes.
- Keep the default guest profile equivalent to the currently validated behavior: headless, no password login, no default keys, no autostart.
- Make imports obvious so a contributor can add another guest module without editing unrelated host module machinery.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/guest/rocknix-guest.nix`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix`

**Test scenarios:**
- Happy path: the default guest flake still evaluates and exposes the `rootfs` package.
- Happy path: the built rootfs shape still contains writable `/etc`, regular `/etc/ssh/authorized_keys.d/root`, and `/usr/bin/nix`.
- Happy path: guest SSH module config uses port `2222`, disables password and keyboard-interactive auth, and locks root password.
- Error path: static checks fail if a guest module reintroduces port `22`, password auth, shipped authorized keys, or missing `/usr/bin/nix` compatibility.
- Integration: Layer 10 bootable smoke remains able to start/stop a rootfs built from the modular guest config.

**Verification:**
- A reviewer can add a small guest module by importing it into a profile without reverse-engineering the monolithic `rocknix-guest.nix`.

---

### U5. Add `nixctl guest module` workspace/build/import flow

**Goal:** Let operators create an editable guest module workspace on `/storage`, build a rootfs from it, and import it through Layer 10 provenance tracking.

**Requirements:** R3, R6, R7, R9, R10, R12

**Dependencies:** U4

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Add `nixctl guest module init` to copy the image-owned guest flake/modules/profile scaffold to a storage-local workspace.
- Add `nixctl guest module preflight` to check workspace path safety, flake presence, architecture, available Nix, and Layer 10 state constraints.
- Add `nixctl guest module build` to build a rootfs tarball from the storage workspace without importing it automatically.
- Add `nixctl guest module import` or an equivalent explicit handoff that delegates to `nixctl guest import --bootable` so provenance and cleanup semantics stay centralized.
- Keep `build` and `import` separate so a failed build cannot replace a known-good guest rootfs.

**Execution note:** Start with smoke fixtures that use a tiny local workspace and fake build artifact; real Nix rootfs building remains hardware/manual validation.

**Patterns to follow:**
- `cmd_guest_import` in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/README.md`
- `docs/solutions/best-practices/stage-nspawn-rootfs-from-onboard-nix-closures-rocknix-2026-05-06.md`

**Test scenarios:**
- Happy path: `guest module init` creates a storage workspace and records that it was copied from the image-owned scaffold.
- Happy path: `guest module preflight` passes for a valid workspace and reports the selected profile.
- Happy path: `guest module build` produces or locates a rootfs artifact path without modifying the active guest root.
- Happy path: `guest module import` calls the existing Layer 10 import path and records provenance.
- Error path: workspace paths outside `/storage` or `/tmp` fixture roots are refused.
- Error path: build is refused while the guest is running.
- Error path: import is refused if the artifact is missing, unsafe, or not a bootable rootfs.
- Integration: after import, `nixctl guest status` reports bootable-ready and Layer 10b provenance includes the module-built artifact checksum.

**Verification:**
- Guest module workflows are explicit and reversible, and do not weaken Layer 10 cleanup or provenance guarantees.

---

### U6. Add first-class examples for one-build validation

**Goal:** Ship examples that demonstrate the intended module authoring experience without broadening the safety surface.

**Requirements:** R1, R4, R8, R9, R10

**Dependencies:** U2, U3, U4, U5

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/examples/host-tools.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/examples/guest-ssh.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/modules/examples/bridge-nix-version.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/modules/host-tools.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/modules/guest-ssh.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/modules/invalid-host-path.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/modules/invalid-port22.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/modules/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Provide one host-tools example that builds a reversible PATH environment and a wrapper/profile snippet.
- Provide one guest-ssh example that declares the fixed Layer 12 SSH metadata shape without starting the guest.
- Provide one bridge example that wraps `/usr/bin/nix --version` through Layer 11.
- Provide invalid examples specifically for guardrail coverage.

**Patterns to follow:**
- Layer 6 smoke fixtures in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Layer 11 bridge contract in `projects/ROCKNIX/packages/tools/nix-integration/docs/layer11-bridge-contract.md`

**Test scenarios:**
- Happy path: each example evaluates successfully and describes its planned actions.
- Happy path: host-tools example applies and deactivates cleanly using storage-owned files only.
- Happy path: bridge example installs and removes a Layer 11 bridge through module apply/deactivate.
- Error path: invalid-host-path example fails before any write.
- Error path: invalid-port22 example fails before any metadata is written.
- Edge case: examples copied to `/storage` can be edited without changing `/usr/lib` reference files.

**Verification:**
- A contributor can start from an example and understand which options map to which existing layer.

---

### U7. Expand smoke and static validation for module workflows

**Goal:** Ensure the single build has enough evidence to validate module behavior without a second image.

**Requirements:** R10, R11, R12

**Dependencies:** U2, U3, U4, U5, U6

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`

**Approach:**
- Add a `LAYER13_SMOKE=host-modules` mode for storage-scoped host modules.
- Add a `LAYER13_SMOKE=guest-modules` mode for guest workspace/build/import preflight using fixtures and, on hardware, real rootfs build/import when explicitly requested.
- Keep pure fixture tests fast and CI-safe; real rootfs build remains hardware-only/opt-in because native aarch64 builds are expensive.
- Extend static checks for forbidden host paths, port `22`, missing module kit install, missing regular guest SSH files, and accidental reintroduction of nspawn NAT.

**Patterns to follow:**
- U2/U3/U4 smoke correctness changes already in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Existing `LAYER10_SMOKE=bootable` and `LAYER12_SMOKE=ssh` hardware modes

**Test scenarios:**
- Happy path: default runtime smoke still passes without running hardware module workflows.
- Happy path: `LAYER13_SMOKE=host-modules` evaluates, applies, verifies, and deactivates a host module fixture.
- Happy path: `LAYER13_SMOKE=guest-modules` initializes a workspace and verifies the guest flake/profile structure.
- Error path: static checks fail if module kit files are not installed into the image.
- Error path: smoke detects drift when a module-owned file is edited or removed externally.
- Error path: hardware-only module smoke skips CI fixtures and reaches module-specific preflight, mirroring U4 behavior.
- Integration: module-applied guest SSH metadata followed by Layer 12 smoke reaches the same key-only `ssh -p 2222` path as the imperative flow.

**Verification:**
- One SM8550 image can be flashed and validated with ordered smokes: Layer 10b, Layer 12, host modules, guest modules.

---

### U8. Update operational documentation and hardware validation ledger

**Goal:** Make the one-build rollout understandable and keep hardware evidence from being misread out of order.

**Requirements:** R9, R12

**Dependencies:** U1, U3, U5, U7

**Files:**
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/modules/README.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/README.md`
- Create: `docs/solutions/developer-experience/rocknix-declarative-modules-2026-05-07.md`

**Approach:**
- Document the operator flow for host modules and guest modules separately.
- Record the one-build validation order so a successful image build is not confused with module Go.
- Capture known limitations: fixed Layer 12 port, no autostart, no host system paths, no arbitrary services.
- Add a post-validation solution note only after hardware evidence exists; during implementation, create the file as a draft or leave it until validation if the project convention prefers only validated learnings.

**Patterns to follow:**
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- `docs/solutions/developer-experience/nix-layer-6-managed-user-environment-rocknix-2026-05-05.md`
- `docs/solutions/best-practices/stage-nspawn-rootfs-from-onboard-nix-closures-rocknix-2026-05-06.md`

**Test scenarios:**
- Test expectation: none for prose-only docs; static checks should verify referenced command names exist if command names are added to docs.

**Verification:**
- A future operator can validate the image in order without re-deriving command flows from implementation details.

---

## System-Wide Impact

- **Interaction graph:** `nixctl module` becomes an orchestration layer over `nix-layer-activate`, `nixctl bridge`, `nixctl guest service`, and `nixctl guest import`; it must not bypass those commands' safety checks.
- **Error propagation:** evaluator failures should stop before writes; activation failures should preserve existing rollback behavior; guest build/import failures must not replace a known-good rootfs.
- **State lifecycle risks:** module state can drift from Layer 6/11/12 state if users manually edit generated files; `nix-doctor` and `nixctl module status` must surface drift rather than silently re-owning files.
- **API surface parity:** `nixctl status`, `nix-doctor`, runtime smoke, static checks, README examples, and SM8550 documentation all need the same module state vocabulary.
- **Integration coverage:** applying a module must be tested end-to-end through generated artifacts and existing layer commands, not only by asserting evaluator output.
- **Unchanged invariants:** host SSH on port `22`, no guest autostart, storage-only runtime mutation, Layer 10 cleanup boundaries, and Layer 12 key-only auth remain unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Single-build scope becomes too large and hides root-cause failures | Keep units atomic and validation ordered; image may contain all units, but Go evidence remains Layer 10b -> Layer 12 -> Layer 13. |
| Host module evaluator bypasses existing guardrails | Generate artifacts consumed by Layer 6/11/12 instead of writing host files directly. |
| Nix module option surface accidentally implies full NixOS parity | Name the domain ROCKNIX host modules, document storage-only semantics, and defer arbitrary services/autostart. |
| Guest module builds are slow on Thor | Keep build/import explicit, add preflight, and separate fixture smoke from hardware rootfs build validation. |
| Module-managed files conflict with user files | Reuse Layer 6 ownership/conflict refusal and add module state drift checks. |
| Layer 12 fixed port surprises users who expect arbitrary ports | Document fixed `2222` as an intentional first-version constraint and reject unsupported ports clearly. |
| Existing Layer 6/11/12 commands regress while adding orchestration | Add module tests plus unchanged smoke coverage for existing layer commands. |

---

## Documentation / Operational Notes

- The next SM8550 image can include this whole module layer, but the validation log must not mark Layer 13 Go until Layer 10b and Layer 12 pass on the same image family.
- Operator docs should distinguish image-owned templates under `/usr/lib/nix-integration` from editable workspaces under `/storage/.config/nix-integration`.
- The first public examples should be conservative and boring: host tools, guest SSH metadata, and one nix-version bridge.
- If hardware validation finds another Layer 10/12 blocker, module code can still ship in the image but should remain No-Go until the dependency is resolved.

---

## Alternative Approaches Considered

- **Guest modules only:** lower risk, but it would not solve the host-side declarative composition problem that motivated NixOS-like modules for ROCKNIX surfaces.
- **Full host NixOS conversion:** rejected because ROCKNIX must remain the base OS and recovery plane.
- **Custom shell manifest as the module language:** rejected because contributors specifically want NixOS-like modules; shell manifests remain an implementation artifact, not the authoring interface.
- **One generic service manager module:** rejected for the first version because it would reopen autostart, host systemd, and network exposure questions that existing layers intentionally deferred.

---

## Success Metrics

- A contributor can write or edit a Nix module under `/storage/.config/nix-integration/modules` and apply it without touching image-owned files.
- Host module apply/deactivate leaves only module-owned files and metadata under `/storage` and can roll back cleanly.
- Guest module workspace can build/import a bootable rootfs through existing Layer 10 provenance tracking.
- Layer 12 module example reaches the same key-only `ssh -p 2222 root@thor /usr/bin/nix --version` validation path as imperative Layer 12.
- `nix-doctor --offline` reports module state and drift clearly.
- Reboot after module validation does not autostart the guest or guest SSH.

---

## Phased Delivery

### Phase 1: Same-day implementation and build batching

- Land U1 through U7 on `feat/nix-layer-12-opt-in-guest-ssh` immediately, on top of the current Layer 10/12 fixes.
- Treat the active SM8550 run `25497332382` as supersedable build traffic: if module commits land before it is worth preserving, cancel and dispatch a replacement from the combined head; otherwise dispatch a second same-day SM8550 build without waiting for the first artifact.
- CI/static checks prove the authoring kit is packaged and guardrails are present.
- Fixture runtime smoke proves evaluator/apply/deactivate behavior without real hardware rootfs rebuilds.

### Phase 2: Hardware validation on Thor

- Flash the image.
- Validate Layer 10b bootable start/stop.
- Validate Layer 12 SSH.
- Validate host module apply/deactivate.
- Validate guest module workspace/build/import if native build time is acceptable; otherwise record it as pending native-build evidence while still validating preflight and scaffold correctness.

---

## Sources & References

- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-layer-activate`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/guest/rocknix-guest.nix`
- Related contract: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer10-guest-lifecycle-contract.md`
- Related contract: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer12-guest-ssh-contract.md`
- Related learning: `docs/solutions/developer-experience/nix-layer-6-managed-user-environment-rocknix-2026-05-05.md`
- Related learning: `docs/solutions/best-practices/stage-nspawn-rootfs-from-onboard-nix-closures-rocknix-2026-05-06.md`
- Related learning: `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
- External docs: Nixpkgs module system documentation for `lib.evalModules`
- External docs: nix.dev module system deep dive
