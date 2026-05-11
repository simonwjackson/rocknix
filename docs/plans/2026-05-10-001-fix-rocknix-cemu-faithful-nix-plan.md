---
title: Fix ROCKNIX-Faithful Nix Cemu Runtime
type: fix
status: active
date: 2026-05-10
origin: chat
---

# Fix ROCKNIX-Faithful Nix Cemu Runtime

## Summary

Build a stricter guest-native Nix Cemu package that faithfully mirrors ROCKNIX `cemu-sa` where the current nixpkgs-derived candidate still diverges, then validate it against the known-good host Cemu control through the same guest display path.

---

## Problem Frame

Live validation proved the Layer 14 guest display path is capable of expected BOTW performance: ROCKNIX host Cemu presented through the guest sway output reaches the 45 FPS target. A Nix Cemu candidate that added ROCKNIX patches plus `gameProfiles`/`resources` now finds BOTW's game profile and shared fonts, but still shows slow-Cemu symptoms: much slower loading/link/scanning, missing Cubeb support, and user-visible sluggishness.

The remaining gap is no longer raw GPU/display throughput or missing Cemu data resources alone. It is a deeper build/runtime parity problem between ROCKNIX `cemu-sa` and the Nix package shape.

---

## Requirements

- R1. Produce a guest-native Nix Cemu candidate that is closer to ROCKNIX `cemu-sa` than the current `cemu-rocknix-style` output on ELF type, Cubeb behavior, SDL/runtime stack, Cemu data resources, and launcher semantics.
- R2. Preserve the Layer 14 safety model: ROCKNIX remains the recovery plane, no broad host `/usr` or `/lib` binds, no host Vulkan loader `LD_PRELOAD`, no broad `/storage/.cache` bind, and no mutation of host boot/system areas.
- R3. Keep host Cemu through guest sway as the diagnostic control, not the product path.
- R4. Make parity measurable before interpreting FPS: every candidate must have a fingerprint covering source, patches, resources, ELF/linkage, runtime maps, Cemu log evidence, and Vulkan/Mesa stack.
- R5. Make live validation decisive: success requires user-visible in-game MangoHud/title evidence at the same scene/profile, not loading-screen or title-only FPS.
- R6. Harden benchmark safety: exact process cleanup, run locking, settings snapshot/restore, and power/thermal restoration on exits and interrupts.
- R7. Use Fuji or another aarch64 builder for heavy Cemu builds; Thor should receive/import built closures and run validation.

---

## Scope Boundaries

- This plan does not productize host `/usr/bin/cemu` inside the guest.
- This plan does not build a full Nix Mesa replacement for ROCKNIX Mesa; ROCKNIX Mesa passthrough remains diagnostic unless a separate plan promotes it.
- This plan does not change the Layer 14 guest lifecycle contract or boot/recovery model.
- This plan does not redesign the game launcher UI.
- This plan does not tune BOTW graphic packs beyond preserving existing profile choices needed for fair A/B validation.

### Deferred to Follow-Up Work

- Promote the winning Cemu package into a stable guest profile/default launcher after live validation passes.
- Replace diagnostic ROCKNIX Mesa passthrough with a coherent Nix Mesa/Turnip package if Cemu remains dependent on host graphics libraries.
- Long thermal soak profiles once correctness/performance parity is demonstrated.

---

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk` is the host Cemu contract: exact commit, patches, CMake flags, bundled Cubeb behavior, install layout, and dependency set.
- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/scripts/start_cemu.sh` is the host launcher contract for Cemu config, controller profile, audio sink, online/mlc/keys, and `settings.xml` mutation.
- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/config/SM8550/settings.xml` is the SM8550 default config source.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix` currently builds the Nix Cemu candidates from the same source commit but still inherits nixpkgs package shape.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-style.nix` and `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-style-classic-sdl.nix` are diagnostic candidates to extend or replace.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest.sh` already supports a `CEMU_BIN` override but still defaults to a hardcoded store path.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-build-fingerprint.sh` and `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runtime-ab.sh` provide the existing parity/reporting harnesses.

### Institutional Learnings

- `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md` records the decisive control: host Cemu through guest display reaches 45 FPS, while Nix Cemu remains slow unless build/runtime parity improves.
- `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md` captures the Layer 14 display/nspawn contract and warns against broadening host binds.
- `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md` reinforces that runtime health must be proven from live process/socket evidence, not stale state files.
- `docs/solutions/developer-experience/nix-layer-7-app-ui-experiments-rocknix-2026-05-05.md` supports keeping graphical app integration narrow, reversible, and rooted in `/nix/store` or Nix profiles.

### External References

- External research not needed for this plan. The decisive constraints come from repository-local ROCKNIX package recipes, live evidence, and existing Layer 14 operational learnings.

---

## Key Technical Decisions

- **Build from the ROCKNIX package contract, not from generic nixpkgs Cemu overrides.** The current candidate fixed resources/profile discovery but still inherits enough nixpkgs shape to behave like the slow Cemu.
- **Treat ELF type and hardening as first-class parity surfaces.** Host Cemu is an `EXEC` executable; the Nix wrapped runtime is `DYN`. The next candidate should intentionally test disabling PIE/hardening where needed to match host Cemu.
- **Make bundled Cubeb parity explicit.** Host Cemu reports Cubeb available and does not expose a separate dynamic `libcubeb` in the same way; the current Nix candidate reports Cubeb unsupported. The next candidate must either use bundled/static Cubeb like ROCKNIX or document exactly why it cannot.
- **Use classic SDL as the stricter default for parity.** The sdl2-compat/SDL3 path is a diagnostic variable, not the faithful target.
- **Keep the known-good host Cemu as a control.** It proves the display path and target scene/profile, but it must not become the product solution.
- **Require state isolation for A/B.** Cemu settings and logs should be snapshotted/restored per run; saves may be shared deliberately, but settings/cache sharing must be explicit.

---

## Open Questions

### Resolved During Planning

- **Are missing `gameProfiles` and shared fonts the only issue?** No. Adding them makes Cemu find BOTW's profile and fonts, but live validation still shows slow-Cemu behavior.
- **Is the guest display path inherently too slow?** No. Host Cemu through the guest display reaches the 45 FPS target.
- **Should builds run on Thor?** No. Heavy aarch64 Cemu builds should run on Fuji or another aarch64 builder, then be imported to Thor for validation.

### Deferred to Implementation

- **Which exact hardening flags must be disabled to produce an `EXEC` Cemu comparable to ROCKNIX?** Requires Nix build iteration and ELF fingerprinting.
- **Can bundled Cubeb be made to work in the Nix package without regressing the build?** Requires build and runtime validation.
- **Does classic SDL plus non-PIE plus bundled Cubeb close the performance gap, or is another dependency such as glslang/libstdc++ still material?** Requires live A/B measurement.
- **How much Cemu state should be isolated for fair A/B while preserving user saves?** Implementer should choose the safest minimum and document what remains shared.

---

## Implementation Units

### U1. Define the faithful Cemu derivation target

**Goal:** Add a new stricter Nix package output that represents the faithful ROCKNIX `cemu-sa` replication target, separate from existing diagnostic candidates.

**Requirements:** R1, R2, R4, R7

**Dependencies:** None

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-faithful.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Add a new output such as `cemu-rocknix-faithful` rather than mutating the existing default immediately.
- Treat `cemu-sa/package.mk` as the source of truth for commit, patches, pre-configure edits, and CMake flags.
- Carry all ROCKNIX patches plus the guest-only screensaver workaround only if still required for Nix runtime stability.
- Install Cemu runtime data into the Nix output and make this a build-time assertion.
- Avoid hardcoded Thor store paths in documentation; use the flake output name as the stable build target.

**Execution note:** Build characterization-first. Every build change should be followed by fingerprint comparison before live performance conclusions.

**Patterns to follow:**
- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-style.nix`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`

**Test scenarios:**
- Happy path: the new flake output evaluates on both supported systems and builds on an aarch64 builder.
- Happy path: the output contains `share/Cemu/gameProfiles/default/00050000101c9400.ini` and `share/Cemu/resources/sharedFonts/CafeCn.ttf`.
- Error path: if runtime data directories are absent from the source/build tree, the build fails with a clear error rather than producing another partial Cemu package.
- Integration: static checks cover the new flake file and any new patch/resource references.

**Verification:**
- The new package output exists and builds on Fuji.
- The built output has Cemu runtime data and a distinct store path from previous candidates.

---

### U2. Match ROCKNIX executable and dependency posture

**Goal:** Close the remaining binary/runtime deltas that correlate with slow-Cemu behavior: PIE/DYN vs EXEC, Cubeb support, SDL selection, and library/runtime fingerprints.

**Requirements:** R1, R4

**Dependencies:** U1

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-faithful.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Explicitly test disabling PIE/hardening enough for the runtime binary to match ROCKNIX's non-PIE executable posture when feasible.
- Force classic SDL for the faithful candidate, leaving sdl2-compat as a separate diagnostic variant.
- Rework Cubeb handling so the candidate mirrors ROCKNIX's bundled Cubeb behavior and Cemu reports Cubeb availability at runtime.
- Reduce or document dynamic dependency differences that remain unavoidable under Nix.
- Update README/fingerprint expectations so a reviewer can tell which deltas are intentionally accepted vs. still blocking.

**Patterns to follow:**
- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk`
- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/patches/000-build-fixes.patch`
- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/patches/003-disable-cmake-interprocedural-optimization.patch`

**Test scenarios:**
- Happy path: fingerprint shows whether the faithful candidate is `EXEC` or explains the accepted remaining ELF difference.
- Happy path: Cemu runtime log reports Cubeb available or the candidate is marked failed for parity.
- Edge case: if non-PIE conflicts with Nix linking or hardening, the build failure is isolated to this candidate and does not break existing outputs.
- Integration: linked SDL, Cubeb, glslang, Vulkan, and wxWidgets surfaces are captured in the fingerprint report for host/current/candidate.

**Verification:**
- Fingerprint report shows fewer unexplained host/guest binary/runtime deltas than `cemu-rocknix-style`.
- Existing `cemu` and diagnostic outputs still evaluate/build independently.

---

### U3. Port the required host launcher semantics into a Nix-native launcher

**Goal:** Make the guest launcher reproduce the parts of `start_cemu.sh` that affect BOTW correctness/performance without depending on host `/usr`.

**Requirements:** R1, R2, R5, R6

**Dependencies:** U1, U2

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest_candidate.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/botw-guest.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Keep the guest launcher Nix-native but audit it against `start_cemu.sh` for config bootstrap, controller profile copy, online/mlc/keys layout, audio device selection, and graphic settings mutation.
- Replace hardcoded default Cemu store paths with a stable profile/symlink or explicit package-output handoff after a candidate wins.
- Ensure MangoHud wrapping is explicit and reliable by routing through the MangoHud launcher when requested rather than relying on environment variables that Cemu does not consume.
- Keep `CEMU_BIN`, `CEMU_START`, `CEMU_ROM`, and `CEMU_AFFINITY_MASK` as diagnostic selectors, but document their precedence.

**Patterns to follow:**
- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/scripts/start_cemu.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest_mangohud.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/botw-guest.sh`

**Test scenarios:**
- Happy path: missing guest `settings.xml` is bootstrapped before launch.
- Happy path: BOTW launch log shows shared fonts found, BOTW game profile present, expected FPS++ limit, and expected resolution.
- Error path: missing Cemu binary fails clearly before sway launch, without leaving stale windows.
- Integration: MangoHud-enabled launch produces visible overlay and a CSV for a renamed candidate binary.
- Safety: guest sysfs GPU write failures remain non-fatal and host-side power tuning remains the supported path.

**Verification:**
- Candidate launch no longer depends on manual ad-hoc wrapper files.
- A live candidate run shows the intended Cemu binary path, MangoHud status, and launcher-selected profile in collected artifacts.

---

### U4. Harden A/B validation safety and state isolation

**Goal:** Ensure current/candidate/control comparisons are fair, repeatable, and safe to interrupt.

**Requirements:** R2, R3, R4, R5, R6

**Dependencies:** U3

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runtime-ab.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-live-campaign.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-cleanup.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Add a run lock so current/candidate/control Cemu sessions cannot overlap accidentally.
- Snapshot and restore mutable Cemu settings around each run; document whether saves and shader caches are shared or isolated.
- Add `EXIT`, `INT`, and `TERM` restoration traps to host-side runners that touch power state.
- Make MangoHud CSV detection binary-name agnostic; do not assume `.Cemu-wrapped` naming.
- Scope cleanup to exact process names and, where possible, run-owned markers; avoid killing unrelated guest UI tools unless explicitly forced.
- Record actual profile, gamescope dimensions, Cemu binary, runtime maps, and thermal state in each report.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-cleanup.sh`
- `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`

**Test scenarios:**
- Happy path: current and candidate runs produce separate artifacts with restored settings between cases.
- Error path: missing candidate binary produces a failed report and cleanup without killing the guest service.
- Error path: interrupting a run restores safe clocks and leaves SSH/guest service alive.
- Edge case: cleanup with no active benchmark does not mutate Cemu settings or kill recovery/session infrastructure.
- Integration: a host-control diagnostic is clearly labeled as diagnostic-only and uses the same guest display output.

**Verification:**
- Re-running current → candidate → current does not inherit profile/settings mutations except explicitly shared state.
- Runner reports include enough evidence to compare FPS against Cemu binary/runtime surfaces.

---

### U5. Build on Fuji and import candidate closures to Thor

**Goal:** Make the build/deploy loop reproducible without tying up Thor with heavy compilation.

**Requirements:** R4, R7

**Dependencies:** U1, U2

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Document Fuji as the expected aarch64 builder for Cemu candidate builds.
- Document closure import/export expectations at the process level without hardcoding machine-specific transient store paths.
- Ensure validation scripts accept a candidate path resolved from the imported closure or a stable guest profile link.
- Keep Thor focused on launch/fingerprint/live validation.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`
- `docs/solutions/developer-experience/fast-iter-and-local-rocknix-build-2026-05-08.md`

**Test scenarios:**
- Happy path: candidate built on Fuji is importable into the Thor guest store and executable there.
- Error path: missing imported closure is reported before launch.
- Integration: fingerprint report records both the flake output name and resolved store path for the imported candidate.

**Verification:**
- A developer can reproduce the build/import/validate loop from docs without editing scripts for each store hash.

---

### U6. Run decisive live validation and update evidence docs

**Goal:** Decide whether the faithful Nix candidate closes the gap, using live in-game evidence against the host Cemu control.

**Requirements:** R3, R4, R5, R6

**Dependencies:** U3, U4, U5

**Files:**
- Modify: `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Validate the host Cemu control, current Nix Cemu, and faithful Nix candidate through the same guest display scene/profile.
- Prefer 540p-45 for the direct host-control comparison because it already demonstrated the target with host Cemu.
- Capture live MangoHud/user-visible FPS, title FPS, CSV where available, thermals, process maps, Cemu logs, screenshots, and cleanup outcome.
- Promote or reject the candidate based on live behavior, not just logs proving resource/profile parity.
- Update the performance audit with the final decision and any remaining deltas.

**Patterns to follow:**
- `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runtime-ab.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-live-campaign.sh`

**Test scenarios:**
- Happy path: faithful candidate reaches the same scene and sustains the target FPS envelope comparable to host Cemu.
- Error path: candidate shows slow loading/FPS; report preserves enough evidence to identify remaining deltas.
- Edge case: MangoHud CSV missing but visible overlay/title samples available; report marks CSV missing without discarding live observations.
- Integration: final audit clearly separates diagnostic host-control evidence from guest-native product-candidate evidence.

**Verification:**
- The audit doc contains a clear promote/reject decision for the faithful candidate.
- No stale Cemu/gamescope/MangoHud process remains after validation.
- Host CPU/GPU power state is restored unless the operator explicitly requests otherwise.

---

## System-Wide Impact

- **Interaction graph:** Cemu flake outputs feed Fuji builds, imported Thor guest closures, guest launchers, host-side runner scripts, and documentation evidence.
- **Error propagation:** Build failures should fail package outputs; launch failures should become run reports; cleanup failures should warn without hiding unsafe residual state.
- **State lifecycle risks:** Shared `settings.xml`, shader caches, logs, saves, and power state can invalidate A/B runs unless explicitly isolated or restored.
- **API surface parity:** Existing launcher environment variables remain compatibility surfaces for diagnostics and should not be silently removed.
- **Integration coverage:** Unit/static checks are insufficient; the decisive integration test is a live BOTW scene with the candidate binary and captured runtime maps/logs.
- **Unchanged invariants:** ROCKNIX host SSH, recovery plane, guest nspawn lifecycle, and broad-bind prohibitions remain unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Disabling PIE/hardening breaks Nix build or runtime | Isolate in `cemu-rocknix-faithful`; keep existing outputs intact until candidate wins. |
| Cubeb parity is difficult under Nix | Treat Cubeb availability as a parity gate; document if a separate candidate is needed. |
| Candidate appears fast due to stale host/current process overlap | Add run locks, exact cleanup, and process evidence before interpreting results. |
| A/B runs mutate user Cemu settings | Snapshot/restore settings around runs and document shared state. |
| Max-power validation overheats Thor | Add restore traps and thermal warn/fail thresholds in reports. |
| Store paths go stale after rebuilds | Resolve candidates through flake outputs, Nix profiles, or explicit imported closure paths recorded at runtime. |

---

## Documentation / Operational Notes

- Update the Cemu flake README with the new faithful output, its parity checklist, and Fuji build guidance.
- Update launcher README with safe candidate selection and live validation flow.
- Update the performance audit after validation so future sessions do not rediscover stale conclusions.
- Keep diagnostic host-control and host-Mesa paths explicitly labeled as diagnostics.

---

## Sources & References

- Existing plan: `docs/plans/2026-05-09-003-fix-layer14-cemu-build-parity-plan.md`
- Performance audit: `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- ROCKNIX Cemu package: `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk`
- ROCKNIX Cemu launcher: `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/scripts/start_cemu.sh`
- Guest Cemu flake: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix`
- Guest launchers: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/`
