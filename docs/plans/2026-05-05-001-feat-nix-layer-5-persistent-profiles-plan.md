---
title: "feat: Nix Layer 5 — persistent profiles for CLI tools"
type: feat
status: completed
date: 2026-05-05
---

# feat: Nix Layer 5 — persistent profiles for CLI tools

## Overview

Layer 4 proved that standard single-user Nix 2.34.7 works on ROCKNIX's storage-backed `/nix` mount: real Nix installs cleanly, `sandbox = true` works on SM8550, `nix run nixpkgs#hello` succeeds, and the real-Nix binary is available through `${HOME}/.nix-profile/bin` after the profile.d ordering fix.

Layer 5 turns that substrate into a day-to-day toolbox. The intended outcome is simple: the device owner can install CLI tools once with standard `nix profile` commands, open a fresh SSH session or reboot, and keep using those tools from normal shells. This layer should add only the small amount of glue needed for ROCKNIX safety: a pinned shell/profile contract so `nix profile install` mutates the same profile path exposed on `$PATH`, profile visibility in `nixctl status`, profile health/conflict checks in `nix-doctor`, opt-in hardware smoke coverage, and operator documentation for install/remove/upgrade/garbage-collection workflows.

## Problem Frame

Layer 4 makes real Nix usable per command, but recurring SSH/admin workflows still require either ephemeral `nix shell` invocations or manual absolute paths. Persistent profiles are the next useful layer because they make tools such as `rg`, `fd`, `bat`, and `jq` feel native without changing the ROCKNIX base OS.

The main technical risk is not whether Nix profiles work — Layer 4 already created `${HOME}/.nix-profile` and put its `bin` directory first on `$PATH`. The risk is operational: profile-installed tools can shadow ROCKNIX or storage-provided commands, profile generations can consume disk over time, and `nixctl uninstall` currently removes the profile as part of Layer 4 cleanup. Layer 5 should make those behaviors explicit and diagnosable rather than inventing a new package manager wrapper.

## Requirements Trace

- R1. A CLI tool installed through `nix profile install nixpkgs#<package>` mutates the same root profile exposed through `${HOME}/.nix-profile/bin` and is available by command name in a fresh SSH/login shell.
- R2. Profile-installed tools persist across reboot because profile state lives under the storage-backed `/nix` hierarchy and root's storage home.
- R3. Standard Nix remains the user-facing interface for profile operations; Layer 5 must not introduce a parallel install/remove syntax that hides Nix semantics.
- R4. `nixctl status` reports Layer 5 profile state clearly: profile link, profile `bin` path, installed entries when available, and PATH resolution/conflicts.
- R5. `nix-doctor` warns about command shadowing and broken profile state without failing healthy systems that intentionally prefer a Nix-profile tool.
- R6. Runtime smoke coverage can validate install/use/remove for one low-risk profile package and optionally validate persistence after a manual reboot.
- R7. Documentation covers install, list, upgrade, remove, rollback/delete-generation, garbage collection, disk usage, command conflicts, and Layer 4 uninstall implications.
- R8. Existing ROCKNIX boot, UI, game runtime, `/storage/bin` scripts, and explicit nix-portable fallback remain unchanged.

## Scope Boundaries

- Layer 5 does not install any default packages into the image or auto-populate a profile during boot.
- Layer 5 does not create a custom `nixctl profile install` wrapper; standard `nix profile` is the interface.
- Layer 5 does not manage dotfiles, autostart entries, systemd user units, or broader user environments. That belongs to Layer 6.
- Layer 5 does not change the Layer 4 single-user/root model or add `nix-daemon`/multi-user Nix.
- Layer 5 does not promise conflict-free command precedence. It documents the precedence and reports conflicts so the device owner can decide.

### Deferred to Separate Tasks

- **Layer 6 user environment management:** Nix-managed files under selected `/storage` surfaces, if still desired after profiles are stable.
- **Layer 9 NixOS-in-nspawn:** Guest/system management remains a separate strategic path and does not block persistent host profiles.

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/packages/tools/nix-integration/profile.d/998-nix-integration.conf` already establishes Layer 5 precedence by prepending `${HOME}/.nix-profile/bin` before `/nix/var/nix/profiles/default/bin`, `/storage/bin`, and ROCKNIX system paths.
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl` already reports Layer 4 status and shell PATH resolution. Layer 5 should extend this read-only reporting instead of adding a second front door.
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor` already validates Layer 3 and Layer 4 state, including `${HOME}/.nix-profile` symlink health and real-Nix PATH resolution. Layer 5 should add profile-entry and command-conflict checks there.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh` already has an opt-in hardware path for Layer 4. Layer 5 should follow the same opt-in pattern because it needs network, real `/nix`, and storage writes.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` already protects the profile.d ordering bug found during Layer 4 validation.
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md` is the operator-facing layer document and already names Layer 5 as the next layer.

### Institutional Learnings

- `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md` captured the key Layer 5 prerequisite: profile.d ordering is part of the contract. Presence checks are not enough; the Nix profile snippet must sort after ROCKNIX's `098-busybox` PATH reset.
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` defines the SM8550 image update validation flow. Layer 5 source changes require an image rebuild only for the improved scripts/docs; profile installs themselves are runtime-only.
- `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md` flagged command conflicts as the Layer 5 design issue, especially tools such as `jq`, `python`, `git`, and `grep` that may already exist in ROCKNIX.
- `docs/plans/2026-05-04-001-feat-nix-layer-4-real-store-plan.md` deliberately positioned Layer 5 as a small follow-up once `${HOME}/.nix-profile/bin` is already on `$PATH`.

### External References

- Nix 2.34 manual, `nix profile` command reference: standard operations are `install`, `list`, `remove`, and `upgrade`; Layer 5 must ensure their default target is the profile exposed by ROCKNIX's shell environment.
- Nix 2.34 manual, profiles: users normally put `${HOME}/.nix-profile/bin` on `$PATH`, while profile roots may live under Nix-managed profile directories; the implementation must ensure the command target and PATH-exposed link agree.
- Nix 2.34 manual, `nix profile` command reference: profile subcommands support an explicit profile path, and current defaults should not be assumed blindly on ROCKNIX without validation.
- Nix 2.34 manual, garbage collection: `nix-collect-garbage -d` deletes old generations before collecting unreachable store paths.

## Key Technical Decisions

- **Pin the profile target exposed by the shell.** Nix profile defaults have varied across Nix versions and install modes. Layer 5 should make `${HOME}/.nix-profile` the explicit profile contract for root shells, using profile.d environment only if needed, so plain `nix profile install ...` updates the same `bin` directory that ROCKNIX puts first on `$PATH`.
- **Use standard `nix profile`, not a ROCKNIX wrapper.** The whole point of Layer 4 was to make normal Nix work. Wrapping profile install/remove would create a parallel package-manager contract and increase maintenance without improving reversibility.
- **Keep Nix-profile binaries first on `$PATH`.** Layer 4 already shipped this ordering. It gives the user an intentional override mechanism for SSH tooling. The safety mechanism is conflict visibility in status/doctor, not silently demoting the profile behind `/storage/bin` or `/usr/bin`.
- **Treat command conflicts as warnings, not failures.** A profile-installed `jq` shadowing ROCKNIX `jq` may be exactly what the device owner wants. Doctor should fail only on broken profile state, not on intentional precedence.
- **Validate with low-conflict packages first.** Runtime smoke should prefer packages whose command names are unlikely to be ROCKNIX-critical, such as `ripgrep` (`rg`) or another small CLI fixture. Packages like `python`, `git`, `grep`, and `sh` are documentation examples for conflict detection, not starter smoke packages.
- **Garbage collection remains explicit/manual.** Automatic GC risks surprising the user by deleting generations they intended to keep. Layer 5 documents cleanup and reports disk pressure; it does not run GC automatically.

## Open Questions

### Resolved During Planning

- **Should Layer 5 add install/remove subcommands to `nixctl`?** No. `nixctl` reports and diagnoses; `nix profile` remains the package operation interface.
- **Should Layer 5 rely on Nix's implicit profile default?** No. The shell contract should explicitly align Nix's profile target with `${HOME}/.nix-profile` if current Nix behavior on ROCKNIX does not already do so.
- **Should Nix-profile binaries come before `/storage/bin`?** Yes. That is already shipped by `998-nix-integration.conf` and makes profile installs immediately useful. Conflicts are reported rather than prevented.
- **Should command conflicts fail `nix-doctor`?** No. They are warnings unless they reveal broken state such as a dangling profile link or missing profile directory.

### Deferred to Implementation

- **Exact profile environment variables needed:** The plan requires plain `nix profile install ...` to update `${HOME}/.nix-profile`; the implementer should confirm whether Nix 2.34.7 on ROCKNIX needs `NIX_PROFILE`, `NIX_PROFILES`, or no additional env beyond the existing symlink. The contract is fixed; the exact env plumbing is implementation detail.
- **Exact conflict-detection formatting:** The implementing agent should choose the clearest status/doctor output shape after inspecting current script style.
- **Exact smoke package:** Prefer `nixpkgs#ripgrep` unless hardware validation shows it is too large/slow or conflicts unexpectedly; choose another small CLI package only if needed.
- **Whether to include an automated reboot check:** The smoke script should support a manual/post-reboot validation mode, but whether to automate rebooting the test device is an execution-time decision and should be conservative.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
Fresh SSH/login shell
  └─ /etc/profile sources profile.d in lexical order
       └─ 998-nix-integration.conf repairs PATH after 098-busybox
            PATH precedence:
              1. ${HOME}/.nix-profile/bin          Layer 5 profile tools
              2. /nix/var/nix/profiles/default/bin Layer 4 real nix
              3. /storage/bin                      Layer 1/2 wrappers + user scripts
              4. /usr/bin:/usr/sbin                ROCKNIX base tools

Layer 5 operations
  user command: nix profile install nixpkgs#ripgrep
       └─ Nix updates the Layer 5 profile exposed by ${HOME}/.nix-profile
            └─ ${HOME}/.nix-profile/bin/rg appears on PATH

Diagnostics
  nixctl status  → summarize profile link, installed entries, PATH winner, conflicts
  nix-doctor     → OK for healthy profile, WARN for command shadowing, FAIL for broken profile state
```

## Implementation Units

- [x] **Unit 1: Pin the Layer 5 shell/profile contract**

**Goal:** Ensure standard `nix profile` commands mutate the same profile link that ROCKNIX exposes on `$PATH`: `${HOME}/.nix-profile`.

**Requirements:** R1, R2, R3, R8

**Dependencies:** Validated Layer 4 install and the existing `998-nix-integration.conf` profile ordering fix.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/profile.d/998-nix-integration.conf`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Treat `${HOME}/.nix-profile` as the Layer 5 contract because that is the path already exposed first on `$PATH`.
- Add only the minimum shell environment needed for Nix 2.34.7 to make plain `nix profile install ...` operate on that profile link. If current Nix already honors the existing symlink by default, keep the profile.d change minimal and encode the behavior in smoke coverage instead.
- Preserve the existing lexical ordering guarantee: the snippet must still sort after `098-busybox` and remain idempotent when sourced multiple times.
- Avoid sourcing upstream `nix.sh` wholesale unless implementation proves a specific missing variable is required; explicit ROCKNIX-owned environment is easier to audit.

**Patterns to follow:**
- Existing idempotent PATH guards in `projects/ROCKNIX/packages/tools/nix-integration/profile.d/998-nix-integration.conf`.
- Static ordering guard in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`.

**Test scenarios:**
- Happy path: after sourcing the full ROCKNIX profile stack, the shell exposes `${HOME}/.nix-profile/bin` first and the profile target environment, if added, points at `${HOME}/.nix-profile`.
- Happy path: sourcing the snippet twice does not duplicate PATH entries or profile environment values.
- Edge case: when `HOME` is unset, the snippet does not add a malformed profile path.
- Edge case: when a caller intentionally sets a profile environment variable before sourcing profile.d, the snippet does not clobber it unless implementation explicitly documents that override as required.
- Integration: `nix profile install` in the Layer 5 hardware smoke creates a binary under the PATH-exposed profile, not an unexposed XDG-state profile.

**Verification:**
- Plain `nix profile install nixpkgs#<smoke-package>` creates a command visible through `${HOME}/.nix-profile/bin` in a freshly profile-sourced shell.

---

- [x] **Unit 2: Document the Layer 5 operating model**

**Goal:** Make persistent profiles understandable before adding more script behavior. The docs should describe the exact standard Nix workflows the layer supports and the precedence/conflict model users should expect.

**Requirements:** R1, R2, R3, R7, R8

**Dependencies:** Layer 4 must remain validated on the target image.

**Files:**
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Modify: `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md` *(optional historical note only if implementation wants to mark the old filename/path assumption superseded)*

**Approach:**
- Add a Layer 5 section after the existing Layer 4 section.
- Describe standard profile operations: install, list, remove, upgrade, rollback/delete generations, and garbage collection.
- Explain PATH precedence and the implications of `${HOME}/.nix-profile/bin` shadowing lower-priority commands.
- Recommend low-risk starter packages and call out conflict-prone packages.
- Clarify that `nixctl uninstall` for Layer 4 removes the profile, so a full Layer 4 uninstall also removes Layer 5 tools.
- Keep recovery guidance aligned with the existing `rm -rf /storage/.nix-root && reboot` fallback.

**Patterns to follow:**
- Layer 4 documentation structure in `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`.
- Recovery/validation language from `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`.

**Test scenarios:**
- Test expectation: none — this unit is documentation-only. Verification is editorial and traceability-based.

**Verification:**
- A reader can install, verify, remove, and clean up a profile-installed CLI tool without guessing command precedence or recovery behavior.

---

- [x] **Unit 3: Extend `nixctl status` with Layer 5 profile reporting**

**Goal:** Make `nixctl status` answer the practical Layer 5 questions: is the root profile present, what is installed, which `bin` path wins, and what lower-priority commands are being shadowed?

**Requirements:** R4, R5, R8

**Dependencies:** Units 1 and 2 for the profile contract and agreed terminology; existing Layer 4 `nixctl status` behavior.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Add a distinct "Layer 5 (persistent profile)" status section after Layer 4.
- Report `${HOME}/.nix-profile` existence, symlink target, and whether `${HOME}/.nix-profile/bin` exists.
- When real Nix is installed, invoke the standard profile-list operation in a read-only way and show installed entries or "empty profile".
- Detect profile `bin` command names that also exist in lower-precedence locations such as `/storage/bin`, `/nix/var/nix/profiles/default/bin`, `/usr/bin`, or `/usr/sbin`.
- Keep all conflict reports informational in `status`; reserve failure semantics for `nix-doctor`.
- Ensure status still works on devices with no Layer 4 install, no profile, or an empty profile.

**Patterns to follow:**
- Existing `cmd_status` section formatting in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`.
- Current static checks that assert subcommand presence and profile.d invariants.

**Test scenarios:**
- Happy path: with a valid profile containing a test binary, `nixctl status` reports Layer 5 installed/present and shows the profile `bin` path.
- Happy path: with Layer 4 installed but no added profile packages, `nixctl status` reports an empty Layer 5 profile without error.
- Edge case: with no Layer 4 install, `nixctl status` still completes and explains that Layer 5 depends on Layer 4.
- Edge case: with a profile binary name that also exists under `/storage/bin`, `nixctl status` reports the conflict and indicates that the profile binary wins.
- Error path: with a dangling `${HOME}/.nix-profile` symlink, `nixctl status` reports broken profile state without crashing.

**Verification:**
- `nixctl status` gives a concise, readable Layer 5 summary across absent, empty, populated, conflicting, and broken-profile states.

---

- [x] **Unit 4: Add Layer 5 checks to `nix-doctor`**

**Goal:** Turn profile health into a first-class diagnostic while keeping intentional command shadowing as a warning rather than a failure.

**Requirements:** R4, R5, R7, R8

**Dependencies:** Unit 3's detection model and output terminology.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Factor reusable profile detection carefully if it overlaps with existing Layer 4 symlink checks.
- Fail only for broken states: dangling `${HOME}/.nix-profile`, unreadable profile directory, `nix profile list` failure when real Nix is installed, or profile `bin` missing despite installed profile entries.
- Warn for command conflicts and high storage usage signals.
- Preserve current offline behavior: `--offline` should skip network checks but still validate local profile state.
- Keep doctor useful when profile is absent: no Layer 5 packages installed is a valid state, not a failure.

**Patterns to follow:**
- Existing `ok`, `warn`, and `fail_check` severity model in `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`.
- Existing Layer 4 behavior that only runs real-Nix checks when real Nix is actually present.

**Test scenarios:**
- Happy path: valid profile and sourced PATH produce OK lines for profile link, profile bin, and real-Nix resolution.
- Happy path: empty profile produces no failure and explains that no profile packages are installed.
- Edge case: profile-installed `jq` shadows a lower-priority `jq`; doctor emits a warning naming both paths.
- Error path: dangling `${HOME}/.nix-profile` increments failure count.
- Error path: `nix profile list` fails with real Nix installed; doctor reports the command failure and exits non-zero.
- Integration: `nix-doctor --offline` still validates Layer 1/2/3/4 and Layer 5 local state without attempting network access.

**Verification:**
- `nix-doctor` distinguishes healthy profile use, intentional shadowing, and broken profile state with the correct OK/WARN/FAIL severity.

---

- [x] **Unit 5: Add opt-in Layer 5 runtime smoke coverage**

**Goal:** Prove the layer on hardware without making CI depend on network, cache state, or device reboot behavior.

**Requirements:** R1, R2, R6, R8

**Dependencies:** Units 3 and 4; Layer 4 install path already validated on the device.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Add a new opt-in gate such as `LAYER5_SMOKE=1`, separate from `LAYER4_SMOKE=1`.
- Preflight real Nix, storage-backed `/nix`, network, and sufficient free storage.
- Install one small, low-conflict CLI package into the Layer 5 profile exposed by `${HOME}/.nix-profile`.
- Verify the binary works by direct path and through a freshly profile-sourced shell.
- Run `nixctl status` and `nix-doctor --offline` and assert Layer 5 signals appear.
- Remove the profile package at the end of the smoke unless the caller opts into a persistence/reboot validation mode.
- Provide a manual reboot-validation mode that records the expected binary before reboot and validates it after reconnect, without requiring the default smoke to reboot the device.

**Patterns to follow:**
- Existing `LAYER4_SMOKE=1` hardware-gated section in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`.
- Existing log file pattern used for Layer 4 smoke output.

**Test scenarios:**
- Happy path: profile install of the selected package succeeds, binary runs, fresh shell resolves it from `${HOME}/.nix-profile/bin`, and doctor passes.
- Happy path: profile remove cleans up the selected package and the command is no longer provided by the Nix profile.
- Edge case: selected smoke package already exists in the profile; smoke reports/reuses it safely or chooses a deterministic cleanup strategy without removing user-owned packages accidentally.
- Edge case: command name conflicts with an existing lower-priority binary; smoke confirms status/doctor report the conflict instead of treating it as a hard failure.
- Error path: Layer 4 is absent; Layer 5 smoke exits with a clear prerequisite failure.
- Error path: network/cache fetch fails; smoke fails with a clear package-install message and leaves enough log context for recovery.
- Integration: optional reboot validation confirms the profile-installed binary persists across reboot and remains on PATH after profile.d sourcing.

**Verification:**
- Hardware smoke can prove install/use/remove and, when explicitly requested, reboot persistence without destabilizing normal CI or deleting unrelated user profile packages.

---

- [x] **Unit 6: Update operator validation and recovery docs**

**Goal:** Capture the final validated Layer 5 workflow, including what was actually tested on `thor`, so future layers and rebuilds do not rediscover the same profile/PATH/conflict issues.

**Requirements:** R6, R7, R8

**Dependencies:** Units 1-5 implemented and hardware-validated.

**Files:**
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Modify: `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
- Create: `docs/solutions/developer-experience/nix-layer-5-persistent-profiles-rocknix-2026-05-05.md`

**Approach:**
- Record the exact profile package used for validation, observed PATH resolution, status/doctor output shape, and reboot persistence result.
- Add Layer 5 validation checks to the custom-fork update procedure so future image updates catch profile.d regressions.
- Document cleanup: removing packages, deleting old generations, collecting garbage, and full Layer 4 uninstall implications.
- Cross-link the existing profile.d ordering learning so future PATH changes account for `098-busybox`.

**Patterns to follow:**
- `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md` for concise problem/symptom/solution structure.
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` for validation checklist style.

**Test scenarios:**
- Test expectation: none — this unit is documentation-only and records results from the implementation validation.

**Verification:**
- A future maintainer can repeat Layer 5 validation after a rebuild and understand how to recover disk/profile state without reading the implementation scripts.

## System-Wide Impact

- **Interaction graph:** SSH login/profile sourcing controls command precedence; `nix profile` mutates the Layer 5 profile exposed by `${HOME}/.nix-profile`; `nixctl status` and `nix-doctor` observe that state; ROCKNIX boot/UI paths remain outside the mutation path.
- **Error propagation:** Profile install/remove errors should come from standard Nix. ROCKNIX scripts should report diagnostic context but not mask Nix failures.
- **State lifecycle risks:** Profile generations and store closures can grow storage usage. The layer relies on explicit remove/delete-generation/GC workflows, plus doctor warnings for disk pressure.
- **API surface parity:** User-facing package operations are standard Nix CLI operations. `nixctl` remains a lifecycle/status/doctor front door, not an alternate package manager. The shell/profile environment is part of the user-facing contract because it determines where plain `nix profile install` writes.
- **Integration coverage:** Unit tests/static checks cannot prove persistence; opt-in hardware smoke plus manual reboot validation is required for the Layer 5 acceptance signal.
- **Unchanged invariants:** ROCKNIX owns boot, kernel, firmware, EmulationStation, Sway, and base system paths. Layer 1/2 nix-portable remains explicitly callable. Layer 4 uninstall remains the clean reset for real Nix and profile state.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Nix-profile tools shadow ROCKNIX commands unexpectedly | Keep profile precedence intentional but visible through `nixctl status`, `nix-doctor` warnings, and docs. |
| Smoke cleanup removes a package the user installed before the test | Make the smoke detect pre-existing entries and avoid destructive cleanup unless it created the entry. |
| Store/profile generations consume too much storage | Document remove/delete-generation/GC workflows and add doctor/status storage signals. |
| Profile.d ordering regresses again | Preserve the static check requiring `998-nix-integration.conf` to sort after `098-busybox`; add Layer 5 validation to update checklist. |
| Users expect Layer 5 to survive `nixctl uninstall` | Document that Layer 4 uninstall intentionally removes profile state because profiles live on the real `/nix` substrate. |
| `nix profile` command output changes across Nix versions | Keep parsing minimal and treat output display as best-effort; use Nix exit status for health. |

## Documentation / Operational Notes

- Layer 5 should be presented as an SSH/admin toolbox feature, not a game/UI feature.
- Recommended first validation package should be low-risk and easy to remove; avoid encouraging replacement of critical shell/coreutils commands as the first demo.
- The docs should explicitly show how to inspect conflicts before and after installing a tool.
- The custom fork update checklist should validate both absolute real-Nix paths and complete `/etc/profile` sourcing, matching the Layer 4 profile.d learning.

## Sources & References

- Related plan: `docs/plans/2026-05-04-001-feat-nix-layer-4-real-store-plan.md`
- Related handoff: `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md`
- Operator docs: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- Profile.d learning: `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`
- Update procedure: `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/profile.d/998-nix-integration.conf`
- External docs: Nix 2.34 `nix profile` command reference, `https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-profile.html`
- External docs: Nix 2.34 profiles, `https://nix.dev/manual/nix/2.34/package-management/profiles.html`
- External docs: Nix 2.34 garbage collection, `https://nix.dev/manual/nix/2.34/command-ref/nix-collect-garbage.html`
