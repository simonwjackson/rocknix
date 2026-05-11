---
title: Fix Layer 14 Cemu Build Parity
type: fix
status: active
date: 2026-05-09
origin: chat
---

# Fix Layer 14 Cemu Build Parity

## Summary

Build and validate a guest Cemu runtime that is materially equivalent to ROCKNIX host Cemu, then use headless and live-in-game tests to determine whether the current BOTW slowdown is caused by the Nix Cemu build/runtime rather than raw GPU/display performance.

---

## Problem Frame

Live user validation showed BOTW in the guest can fall to 7-15 FPS even with gamescope removed and settings reduced. GPU demo A/B tests showed host and guest Vulkan/GL demo performance are close, so the remaining likely gap is Cemu-specific: build flags, linked libraries, SDL/runtime behavior, shader/cache paths, or CPU scheduling inside the Nix-built Cemu runtime.

The host and guest Cemu builds use the same upstream commit (`6f6c1299e29fa6e1062ae283a035b4ef787cc397`), but they are not compiled or linked the same way. Host Cemu is built by ROCKNIX; guest Cemu is built by Nix with nixpkgs libraries, sdl2-compat, different Mesa/Vulkan loader, wrapper behavior, hardening, and patches.

---

## Requirements

- R1. Prove, with durable artifacts, how host Cemu and guest Nix Cemu differ: source commit, patches, compiler/toolchain, CMake options, linked libraries, wrappers, Mesa/Vulkan/SDL stack, cache paths, and runtime environment.
- R2. Produce at least one guest-runnable Cemu candidate that more closely matches ROCKNIX host Cemu build semantics than the current nixpkgs-derived package.
- R3. Run a controlled A/B where display/GPU path is held as constant as possible and only the Cemu build/runtime changes.
- R4. Keep ROCKNIX host as recovery plane; do not break SSH on `root@thor:22`.
- R5. Do not productize host `/usr` broad binds, host Vulkan loader `LD_PRELOAD`, or mixed-loader hacks.
- R6. Use live-in-game validation as the decisive signal; loading/title-screen FPS alone is not sufficient.
- R7. Always restore safe CPU/GPU state after benchmarks.

---

## Scope Boundaries

- This plan does not attempt to make Steam or other foreign-binary apps work.
- This plan does not replace ROCKNIX as the host/recovery plane.
- This plan does not support earlier/lower Nix layer forms.
- This plan does not treat `start_cemu_guest_rocknixmesa.sh` as a product solution; it remains diagnostic-only.
- This plan does not broad-bind `/storage/.cache` into the guest.

### Deferred to Follow-Up Work

- Full product launcher UX changes after the winning Cemu runtime is chosen.
- Long thermal soak profiles after build parity is proven.
- Packaging ROCKNIX Mesa as a fully coherent Nix component, unless Cemu build parity alone does not close the gap.

---

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk` defines the ROCKNIX host Cemu build from commit `6f6c1299e29fa6e1062ae283a035b4ef787cc397` with CMake flags such as `ENABLE_VCPKG=OFF`, `ENABLE_SDL=ON`, `ENABLE_CUBEB=ON`, `ENABLE_WXWIDGETS=ON`, `ENABLE_FERAL_GAMEMODE=OFF`, and display/Vulkan/OpenGL toggles derived from ROCKNIX build settings.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix` builds the guest Cemu from the same commit but via nixpkgs `pkgs.cemu`, Nix libraries, wxWidgets 3.3 override, fmt 11 override, Nix hardening, disabled IPO/LTO, and `004-screensaver-noop-linux.patch`.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh` already provides safe unattended Cemu runs with MangoHud CSVs and cleanup.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-single-run-validation.sh` provides parent run reports and pass/warn/fail classifications.
- `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md` records that vkcube/glmark2 are close between host and guest, while real BOTW gameplay remains low FPS in guest Cemu.

### Institutional Learnings

- Do not mix host and Nix Vulkan loaders in one Cemu process; it previously crashed.
- Do not broad-bind `/storage/.cache`; Mesa shader caches may belong to incompatible Mesa versions.
- Host-side GPU tuning is required because guest `/sys/class/devfreq` writes are not reliable inside nspawn.
- Cemu title FPS and loading/title-screen measurements are not enough; live in-game MangoHud/user-observed FPS is decisive.

---

## Key Technical Decisions

- **Treat current Nix Cemu as suspect, not the display path.** GPU demo A/B showed guest display/runtime performance close to host for simple demos, while Cemu remained slow in real gameplay.
- **Pursue build parity before more Mesa swaps.** Host and guest use the same Cemu commit but different build systems/libraries. Mesa-only tests did not explain the gap.
- **Make diagnostics reproducible before changing the package.** A build fingerprint report should be generated first so later changes can be judged against concrete differences.
- **Prefer a ROCKNIX-style Nix build over running host `/usr/bin/cemu` as the product path.** Host Cemu can be used for diagnostics, but the product target remains a Nix derivation in the guest.
- **Use live-in-game checkpoints.** Automated benchmarks are useful, but the decisive A/B must let the user reach a real in-game scene and then sample FPS/thermals/state.

---

## Open Questions

### Resolved During Planning

- **Is the Cemu source version different?** No. Both host and guest are based on commit `6f6c1299e29fa6e1062ae283a035b4ef787cc397`, but version metadata differs (`host: 0.0`, `guest: 2.999`) and build/runtime stacks differ.
- **Is guest raw GPU/display throughput catastrophically slower?** No. vkcube was essentially equal; glmark2 was roughly 5-16% slower in guest, not 5x slower.

### Deferred to Implementation

- **Which specific build difference causes the slowdown?** Requires building candidates and measuring live BOTW behavior.
- **Can host ROCKNIX Cemu run directly against guest sway without GTK/Xwayland failures?** Needs a safer diagnostic harness and may not be worth productizing.
- **Does the Nix Cemu wrapper or sdl2-compat contribute materially?** Requires candidate builds/wrappers and A/B tests.

---

## Implementation Units

### U1. Add Cemu build fingerprint diagnostics

**Goal:** Generate a comparable fingerprint for host ROCKNIX Cemu and guest Nix Cemu so differences are explicit and durable.

**Requirements:** R1, R4, R7

**Dependencies:** None

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-build-fingerprint.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Capture host `/usr/bin/cemu` version, ELF metadata, linked libraries, CMake/build-package source info, runtime Vulkan/SDL/Wayland library paths, and relevant environment.
- Capture guest `/nix/store/...-cemu-2.999.0/bin/Cemu` wrapper and `.Cemu-wrapped` metadata, linked libraries, Nix store references, CMake/package inputs, runtime Vulkan/SDL/Wayland paths, and relevant environment.
- Record known mismatches: sdl2-compat vs ROCKNIX SDL2, Nix wrapper, glibc/toolchain, Mesa/Vulkan loader versions, hardening, disabled IPO/LTO, and patches.
- Write output under `/storage/.guest/runs/<timestamp>-cemu-build-fingerprint/` and summarize in markdown.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-single-run-validation.sh`

**Test scenarios:**
- Happy path: script runs on Thor and creates `report.md` with host and guest sections.
- Error path: if a tool like `readelf` or `file` is missing in the guest, script records `missing` instead of aborting the entire report.
- Integration: final report includes both host and guest Cemu source commit and linked SDL/Vulkan/Wayland evidence.

**Verification:**
- `sh -n` passes for the script.
- Static checks include the new script.
- A sample run produces a markdown report usable for comparing future candidate builds.

---

### U2. Build a ROCKNIX-style Cemu Nix candidate

**Goal:** Produce a guest-runnable Nix Cemu derivation that follows ROCKNIX host build semantics more closely than the current nixpkgs-derived package.

**Requirements:** R2, R5

**Dependencies:** U1

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-style.nix` *(or equivalent split if implementation favors inline flake outputs)*
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Add a second package output, e.g. `.#cemu-rocknix-style`, without replacing the known-working current `.#cemu` output initially.
- Mirror host CMake options from `cemu-sa/package.mk` where applicable.
- Avoid sdl2-compat if a true SDL2 package is available or can be selected safely in Nix; otherwise make the SDL difference explicit in the candidate name/report.
- Avoid Nix hardening differences only where justified and documented. Consider matching Release flags and disabling hardening/fortify/PIE if fingerprint evidence suggests meaningful divergence.
- Keep the same Cemu source commit and ROCKNIX build-fix patches.
- Do not introduce host Vulkan loader preloads or host `/usr` broad runtime dependencies.

**Patterns to follow:**
- `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix`

**Test scenarios:**
- Happy path: `nix build .#cemu-rocknix-style --system aarch64-linux` completes on the aarch64 builder.
- Error path: if true SDL2 is unavailable or incompatible, candidate records that limitation rather than silently falling back to sdl2-compat without annotation.
- Integration: built Cemu reports the same source commit/version metadata policy and starts far enough to print `--version`/`--help` on Thor.

**Verification:**
- New candidate has a distinct store path.
- Fingerprint report shows the candidate is closer to host Cemu than current Nix Cemu on CMake options and linked/runtime libraries.

---

### U3. Add Cemu runtime A/B harness

**Goal:** Run current Nix Cemu, ROCKNIX-style Nix Cemu, and optional host-Cemu diagnostic through the same guest display/session envelope.

**Requirements:** R3, R4, R5, R6, R7

**Dependencies:** U1, U2

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runtime-ab.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest.sh`
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest_candidate.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Parameterize the Cemu binary path through an explicit environment variable such as `CEMU_BIN`, defaulting to the current known Cemu path.
- Add a candidate launcher that can run any guest Cemu binary without rewriting the main launcher.
- Extend the runner to compare:
  - current Nix Cemu,
  - ROCKNIX-style Nix Cemu,
  - optional host-Cemu diagnostic only if it can be run without unsafe binds or mixed Vulkan loaders.
- Keep the display path constant for the main comparison: direct Cemu to guest sway with MangoHud visible, and optionally gamescope as a separate dimension.
- Always collect Cemu title FPS, MangoHud CSV where possible, process thread CPU, thermals, driver evidence, and screenshot.

**Execution note:** Characterization-first. Do not replace default launchers until the A/B shows a clear winner.

**Patterns to follow:**
- `remote-cemu-runner.sh`
- `remote-cemu-single-run-validation.sh`
- `start_cemu_guest_mangohud.sh`

**Test scenarios:**
- Happy path: current Nix Cemu and candidate Cemu both launch BOTW to the loading screen and produce separate run directories.
- Error path: a missing candidate binary is reported as `FAIL` with no lingering Cemu/gamescope processes.
- Integration: A/B report clearly shows which Cemu binary was used, which libraries were mapped, and which driver was used.
- Safety: cleanup leaves `rocknix-guest-v2.service` active and restores CPU/GPU state.

**Verification:**
- Running the A/B with only the current Cemu available still produces a valid baseline report.
- Running with the candidate produces side-by-side metrics and artifacts.

---

### U4. Add live-in-game checkpoint mode

**Goal:** Make live user validation first-class so we stop over-trusting loading/title-screen benchmark numbers.

**Requirements:** R3, R6, R7

**Dependencies:** U3

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runtime-ab.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- Modify: `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`

**Approach:**
- Add a mode that launches one candidate and then waits for an operator signal file or command, e.g. `/storage/.guest/live-checkpoint now`, before sampling.
- At checkpoint, capture 30-60 seconds of title FPS, MangoHud CSV if enabled, Cemu thread CPU, thermals, screenshot, driver evidence, and process maps.
- Keep cleanup separate so the user can inspect visually before the run is stopped.

**Patterns to follow:**
- Existing manual live checks from the audit doc.
- `remote-cemu-runner.sh` state collection blocks.

**Test scenarios:**
- Happy path: user reaches in-game, triggers checkpoint, report captures live metrics.
- Edge case: checkpoint never arrives; script times out and reports `NO_CHECKPOINT` without killing SSH/session.
- Error path: Cemu exits before checkpoint; report captures logs and classifies failure.

**Verification:**
- Live checkpoint reports distinguish loading/title FPS from in-game FPS.
- Report includes user-observed FPS field when provided.

---

### U5. Update audit and choose next runtime direction

**Goal:** Convert A/B evidence into a clear decision: keep current Nix Cemu, switch to ROCKNIX-style Nix Cemu, or pursue deeper Cemu/runtime investigation.

**Requirements:** R1, R2, R3, R6

**Dependencies:** U1, U2, U3, U4

**Files:**
- Modify: `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- Modify: `docs/plans/2026-05-09-001-fix-layer14-cemu-host-performance-plan.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`

**Approach:**
- Add a comparison table for host Cemu, current Nix Cemu, and ROCKNIX-style candidate.
- Include live-in-game FPS observations, not only automated benchmark medians.
- Record whether build parity materially improved loading time and in-game FPS.
- If candidate wins, document how to promote it to the default guest launcher in a follow-up change.
- If candidate does not win, document the next suspected layer: shader/precompiled cache behavior, storage path latency, CPU scheduler/thermal, or Cemu AArch64 backend differences under Nix.

**Test scenarios:**
- Documentation includes enough evidence for another agent to reproduce the chosen next step.
- No diagnostic-only host shim is represented as a product target.

**Verification:**
- Audit doc states the selected next direction and why.
- Plan status can be updated after implementation evidence lands.

---

## System-Wide Impact

- **Interaction graph:** Cemu launcher scripts, Nix flake packaging, guest sway, MangoHud, host-side CPU/GPU tuning, and Thor live validation all interact.
- **Error propagation:** Candidate build failures should fail as package/build errors; runtime launch failures should be captured in run directories, not hidden in SSH scrollback.
- **State lifecycle risks:** Candidate launchers must not overwrite stable Cemu settings or leave high clocks/gamescope/Cemu processes running.
- **API surface parity:** If `CEMU_BIN` is introduced, all wrapper scripts must preserve current default behavior when it is unset.
- **Integration coverage:** Static shell checks are necessary but insufficient; Thor runtime A/B reports are the real integration proof.
- **Unchanged invariants:** Host SSH on port 22 remains untouched; ROCKNIX remains the recovery plane; guest runtime state stays under `/storage`.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Candidate still differs from host in hidden ways | Fingerprint host/current/candidate and compare before interpreting perf numbers. |
| Host-Cemu diagnostic destabilizes the display | Keep it optional and behind explicit diagnostic mode; main A/B compares guest Cemu binaries only. |
| Thermal throttling confuses results | Record thermals and power state at live checkpoint; restore safe clocks after each run. |
| Loading/title FPS misleads again | Require live-in-game checkpoint metrics before declaring success. |
| Nix build takes too long on local workstation | Build on aarch64 builder/Fuji with limited jobs; avoid locking the SSH session. |

---

## Documentation / Operational Notes

- Update the launchers README with candidate build usage and clear warnings that host-Cemu/host-Mesa shims are diagnostic-only.
- Keep all run artifacts under `/storage/.guest/runs/`.
- Keep the audit doc as the durable narrative of what was tried and what each result ruled out.

---

## Sources & References

- Related plan: `docs/plans/2026-05-09-001-fix-layer14-cemu-host-performance-plan.md`
- Related plan: `docs/plans/2026-05-09-002-layer14-cemu-single-run-headless-validation-plan.md`
- Audit: `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- Host Cemu package: `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk`
- Guest Cemu flake: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix`
- Launch harnesses: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/`
