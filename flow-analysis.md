# Cemu host-parity closure and post-parity simplification flow analysis

## Codebase grounding

Relevant existing patterns found before reviewing the planning flow:

- The direct package candidate exists as `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-package.nix`, exported as `.#cemu-rocknix-package`. It intentionally avoids `pkgs.cemu`, exports build evidence under `$out/nix-support/rocknix-cemu-build/`, asserts BOTW runtime data/default SM8550 settings, rejects dynamic `libcubeb`, and records `vulkan-loader-lib-path`.
- `start_cemu_guest.sh` already consumes that recorded loader path and prepends it to `LD_LIBRARY_PATH` only for the launched Cemu process. That is the right pattern for the current successful candidate: narrow, process-scoped, and not a global host-loader preload.
- The harness family already has strong safety conventions: exact-name cleanup in `remote-cemu-cleanup.sh`, run directories under `/storage/.guest/runs`, static checks in `nix-integration-static-checks.sh`, settings snapshot/restore in `remote-cemu-runner.sh`, power restore traps, and lock dirs for runner/live-campaign.
- Host-control support is incomplete for this decision. `remote-cemu-runner.sh` has a `host-control` variant, but it is hard-coded to `/storage/bin/botw-potato-30.sh`. `remote-cemu-live-campaign.sh` runs guest Cemu binaries by wrapping `CEMU_BIN` inside the guest and cannot include a host binary as a first-class case today.
- Existing docs explicitly say user-visible in-game evidence outranks title/loading CSV, ROCKNIX Mesa passthrough is diagnostic-only, and host control must be same-session before promotion.

## User flows

1. **Candidate validation flow**
   - Entry point: operator has a built/imported direct Nix package path and runs fingerprint + live validation.
   - Decision points: build evidence passes? Cemu launches? BOTW reaches real in-game control? MangoHud/visible FPS meets target? runtime maps show the expected loader/driver stack?
   - Happy path: fingerprint confirms direct-package parity surfaces, live run reaches BOTW in-game, operator writes checkpoint notes, harness captures screenshot/process maps/FPS, cleanup restores processes and power state.
   - Terminal states: pass candidate, inconclusive/no checkpoint, launch failure, cleanup failure, or runtime mismatch.

2. **Same-session host-control confirmation flow**
   - Entry point: operator is ready to compare the successful direct Nix package against ROCKNIX host Cemu in the same session.
   - Decision points: host Cemu can launch through the same guest display path? profile/scene match? thermal/power state comparable? evidence capture equivalent?
   - Happy path: host-control and candidate run back-to-back through the same display path/profile/scene, with screenshots, process maps, loader/ICD evidence, power/thermal snapshots, and comparable FPS stats.
   - Terminal states: candidate matches host enough to promote; candidate underperforms; host-control cannot launch, making the session inconclusive.

3. **Promotion flow**
   - Entry point: direct package candidate has same-session host-control evidence.
   - Decision points: is product runtime free of diagnostic host Mesa/loader shims? should default launcher point to a store path, profile symlink, or flake-built closure? what diagnostics remain available?
   - Happy path: promote only the winning guest-native Cemu path into the stable launcher/profile, keep `CEMU_BIN` override and fingerprint/live harnesses, and update docs/static checks to identify the promoted output.
   - Terminal states: promoted default, deferred due to diagnostic dependency, or no-go due to unmatched host control.

4. **Post-parity simplification flow**
   - Entry point: candidate is promoted and a second validation run proves no regression.
   - Decision points: which diagnostic wrappers are still needed for rollback/future regressions? has a coherent Nix Mesa decision been made? have host-control artifacts been archived?
   - Happy path: remove only obsolete candidate paths and stale hard-coded store defaults; keep safe selectors, cleanup, fingerprint, and live A/B tooling until the next release/soak passes.
   - Terminal states: simplified stable path, deferred cleanup, or rollback to diagnostic mode.

## Gaps and edge cases

### Critical

1. **Same-session host control is not yet a first-class harness path.**
   - Missing: a validated host-control case that runs ROCKNIX `/usr/bin/cemu` through the same guest display path, same BOTW profile, same scene, and same evidence collection as `cemu-rocknix-package`.
   - Why it matters: visible ~40 FPS from the direct package is encouraging, but without same-session host control the remaining gap could be thermal state, scene choice, profile mismatch, cache state, or display-path difference.
   - Existing pattern/default: `remote-cemu-runner.sh` already has run dirs and `host-control`, but it is currently hard-coded to `botw-potato-30.sh`; default assumption should be **no promotion until this is fixed or manually documented with equivalent artifacts**.

2. **Promotion threshold is underspecified.**
   - Missing: what counts as “close enough” to host parity: median FPS, p10/p1, visible loading/RPL/HLE time, sample length, allowed stutter count, and acceptable thermal envelope.
   - Why it matters: developers may promote on a single visible 40 FPS observation even if host holds 45 FPS with materially better p10/loading behavior.
   - Existing pattern/default: live campaign already captures recent avg/p10/median and screenshot/process evidence. Default: require candidate median within ~10% of host, p10 within ~15%, no repeated visible loading/title regression, and a real in-game checkpoint sample of at least 45s.

3. **Diagnostic-stack dependence must block product promotion.**
   - Missing: a clear distinction between a pass with only the direct package + process-scoped Nix Vulkan loader path and a pass that still depends on `start_cemu_guest_rocknixmesa.sh` / host Mesa ICD/libs.
   - Why it matters: promoting a diagnostic host Mesa shim would violate the Layer 14 product target and blur host recovery boundaries.
   - Existing pattern/default: README and `start_cemu_guest_rocknixmesa.sh` mark ROCKNIX Mesa as diagnostic-only. Default: a ROCKNIX-Mesa-assisted pass can justify a separate graphics-stack plan, not Cemu promotion.

### Important

4. **Live campaign cannot safely compare host and guest cases today.**
   - Missing: case type support for `host-control` in `remote-cemu-live-campaign.sh`, or a separate same-session script that can alternate host/candidate cases while preserving the same checkpoint workflow.
   - Why it matters: current campaign validates guest binaries only; a manual host-control run can drift in order, scene, power, and evidence.
   - Existing pattern/default: add host-control as a special case rather than forcing it through `CEMU_BIN` guest wrappers.

5. **Launch-only live campaign releases the runner lock while Cemu remains active.**
   - Missing: protection against an operator starting another runner while live campaign is waiting for the in-game checkpoint.
   - Why it matters: concurrent Cemu/gamescope runs would corrupt FPS, process maps, cleanup, and possibly user settings.
   - Existing pattern/default: campaign lock exists, but runner lock does not cover active launch-only Cemu. Default: live campaign should either hold a global Cemu lock for the whole case or all runners should refuse when any exact-name Cemu/gamescope process is active unless explicitly forced.

6. **Shared settings/cache state can bias A/B results.**
   - Missing: explicit rule for whether host and candidate share existing shader caches/settings, run cold, or run warm after the same pre-warm procedure.
   - Why it matters: Cemu profile mutation, shader cache growth, and host/guest cache incompatibilities can make the second case look better or worse independent of package parity.
   - Existing pattern/default: runner snapshots settings and warns against broad `/storage/.cache` binds. Default: keep user cache intact, record cache shape before/after each case, run candidate-host-candidate or host-candidate-host ordering, and do not delete caches without backup.

7. **Cleanup ordering needs a promotion-specific gate.**
   - Missing: a required final cleanup verification before declaring a validation or promotion run successful.
   - Why it matters: stale Cemu/gamescope processes or unrecovered CPU/GPU governors can make the next run unfair and degrade the user’s device after testing.
   - Existing pattern/default: cleanup and power restore already exist. Default: acceptance requires final `remote-cemu-cleanup.sh`, no exact-name Cemu/gamescope processes in host or guest, guest service active, and CPU/GPU governors restored.

8. **Removing diagnostics too early would destroy the ability to explain regressions.**
   - Missing: cleanup scope after parity. Which of `remote-cemu-build-fingerprint.sh`, `remote-cemu-runtime-ab.sh`, `remote-cemu-live-campaign.sh`, candidate wrappers, and old flake outputs remain?
   - Why it matters: the current win depends on subtle surfaces: bundled Cubeb, ELF posture, runtime data, process-scoped Vulkan loader path, and loader/ICD maps. If diagnostics are removed before a second host-control confirmation and a soak, regressions become guesswork.
   - Existing pattern/default: static checks already keep these tools syntax-valid. Default: remove only dead hard-coded store paths/failed candidate defaults; keep fingerprint, cleanup, `CEMU_BIN` override, and live A/B for at least one post-promotion soak/release.

9. **Default launcher promotion mechanism is brittle if it remains a raw store path.**
   - Missing: whether the stable launcher should point at a named profile path, flake-built closure, or hard-coded `/nix/store/...` path.
   - Why it matters: garbage collection, rebuild/import changes, or stale rootfs profiles can break the default even though the flake output is correct.
   - Existing pattern/default: `CEMU_BIN` override exists for diagnostics. Default: promote through a stable profile/symlink or generated launcher value, and keep `CEMU_BIN` override for rollback.

### Minor

10. **Operator checkpoint semantics are loose.**
    - Missing: exact scene/save position and what notes must be written to `/storage/.guest/live-checkpoint`.
    - Why it matters: “visible FPS” without scene identity makes cross-run comparison weaker.
    - Default: checkpoint note should include profile, scene/location, visible FPS, loading/stutter notes, and whether controls were responsive.

11. **Current 40 FPS observation needs artifact naming.**
    - Missing: a canonical run directory/report that represents the successful direct-package run.
    - Why it matters: future cleanup/promotion should reference immutable evidence, not chat memory.
    - Default: archive the run dir path, Cemu store path, and fingerprint report in the plan before promotion.

## Acceptance criteria

Before promotion:

1. Direct package fingerprint report shows expected source rev, all three patches, runtime data/default settings, no dynamic `libcubeb`, build evidence present, and process maps/env show the intended Vulkan loader/ICD stack.
2. Candidate launches through the product-intended guest-native path, not through ROCKNIX Mesa diagnostic shim, unless the promotion is explicitly deferred to a graphics-stack plan.
3. Same-session A/B includes host-control and direct package on the same BOTW profile and same in-game scene, with order controlled enough to account for thermals (prefer candidate-host-candidate or host-candidate-host).
4. Each case has screenshot, user checkpoint notes, MangoHud CSV/recent stats, process maps, loader/ICD evidence, host thermal/power snapshot, and shader-cache shape.
5. Candidate is within the agreed threshold of host-control: default assumption is median FPS within 10%, p10 within 15%, no repeated sub-30 FPS stutter in a 45 FPS profile after warmup, and no user-visible loading/RPL/HLE regression relative to host.
6. Final cleanup proves no Cemu/gamescope/mangohud processes remain, guest service is active, settings are restored or intentionally preserved, and CPU/GPU governors are restored.
7. Promotion changes are reversible: `CEMU_BIN` override and previous/current Cemu output remain available for at least one soak.

After promotion, before simplification:

1. Run one clean-boot validation of the promoted default launcher, not only `CEMU_BIN` override.
2. Run one rollback/override validation proving an alternate Cemu can still be selected.
3. Archive the winning run dirs and fingerprints in docs/plans or docs/solutions.
4. Only then remove obsolete failed-candidate defaults or stale hard-coded store paths.

## Questions

1. **Which BOTW profile and scene are the promotion gate?** Stakes: host/candidate comparisons are not fair if one uses 540p-45 and another uses 720p-45 or a different scene. Default: use the profile/scene from the successful ~40 FPS direct-package run, plus one host-proven 540p-45 control if different.
2. **What numeric host-parity threshold should be used?** Stakes: “looks good” can promote a candidate that is still materially below host. Default: candidate median within 10% of host and p10 within 15% after warmup.
3. **Must the winning run be fully guest-native Nix Mesa, or is ROCKNIX Mesa passthrough acceptable for an interim product path?** Stakes: accepting passthrough changes the architectural boundary. Default: passthrough remains diagnostic-only.
4. **How should the promoted launcher reference the winning Cemu: profile symlink, flake output copied into a profile, or raw store path?** Stakes: raw store paths are easy but brittle. Default: stable profile/symlink plus `CEMU_BIN` override.
5. **How long should diagnostics be retained after promotion?** Stakes: removing them too early makes regression analysis expensive. Default: retain fingerprint/live A/B/cleanup and candidate override for one soak or release cycle.

## Recommended sequencing

1. Freeze the current successful direct-package store path and create/record a fingerprint report before changing anything else.
2. Add or run a same-session host-control harness that can compare host Cemu and `cemu-rocknix-package` under the same profile/scene/evidence envelope. Do not promote before this.
3. Run an A/B/A or B/A/B live validation to reduce thermal/order bias, using explicit checkpoint notes and final cleanup verification.
4. If candidate passes without diagnostic ROCKNIX Mesa, promote it via a stable launcher/profile path while preserving `CEMU_BIN` override and diagnostics.
5. Reboot or clean-start, validate the promoted default path, then validate rollback/override.
6. Only after those pass, reduce complexity: remove stale store-path defaults and clearly failed candidate shortcuts first; keep cleanup, fingerprint, runtime A/B, live campaign, and direct package build evidence until a later soak confirms the simplified path.
