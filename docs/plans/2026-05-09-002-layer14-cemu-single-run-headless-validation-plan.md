---
status: completed
created: 2026-05-09
origin: chat
scope: rocknix-layer14-cemu-headless-validation
---

# Layer 14 Cemu Single-Run Headless Validation Plan

## Completion result — 2026-05-09

Implemented and executed the single-run validation orchestrator.

- Script: `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-single-run-validation.sh`
- Thor parent run: `/storage/.guest/runs/20260509-132650-single-run-validation`
- Thor report: `/storage/.guest/runs/20260509-132650-single-run-validation/report.md`
- Best candidate: `WARN max guest-gamescope-mangohud`
- Key result: max-power guest gamescope on Nix Mesa 25.2.6 reached post70 median 30.00 FPS, p10 29.82 FPS, p1 22.58 FPS, with 10 samples below 15 FPS and one 4.23 FPS outlier. This is the strongest headless validation result so far, but it does not clear the strict PASS gate because min FPS after warmup remained below 10.
- Final state: Thor reachable, no Cemu/gamescope processes, `rocknix-guest-v2.service` active, CPU/GPU restored.

## Problem frame

The user is away from Thor and cannot visually validate BOTW/Cemu smoothness. The previous remote pass showed that guest BOTW can reach near-30 median FPS after load, but still has severe hitches in MangoHud CSV. The next step should produce a single unattended validation run that answers, as much as possible without physical observation, whether the guest is good enough to treat as host-like.

This plan extends the existing remote harness instead of relying on live visual inspection.

## Scope

### In scope

- One SSH-triggered run that performs cleanup, runs a small benchmark matrix, analyzes MangoHud CSVs, captures screenshots/logs/state, restores host power defaults, and emits a pass/fail markdown report.
- Quantitative validation only: FPS distribution, frame-time spikes, load-to-FPS timing, driver evidence, crash/error detection, thermal/power state, screenshot existence.
- Guest target variants only, plus diagnostic comparisons that do not become the product path.
- Safe remote execution with exact process cleanup and `rocknix-guest-v2.service` left active.

### Out of scope

- Requiring physical taps, visual observation, or manual confirmation.
- Productizing host Mesa shims or host Cemu.
- Reintroducing host Vulkan loader `LD_PRELOAD`.
- Broad-binding `/storage/.cache`.
- Toggling Cemu fullscreen live through sway.

## Success criteria

The single-run report should clearly answer:

1. Did every tested variant launch and reach in-game unattended?
2. Which variant has the best post-warmup frame pacing?
3. Is the guest now plausibly host-like, based on quantitative thresholds?
4. If not, is the likely remaining problem startup/cache hitches, thermal/power behavior, compositor/gamescope behavior, or runtime stack mismatch?
5. Was Thor left safe and reachable after the run?

Recommended provisional gates for `potato-30` after a 70s warmup:

- `median_fps >= 28`
- `p10_fps >= 22`
- `p1_fps >= 15`
- `min_fps >= 10` after warmup, or explicit warning if a single outlier remains
- no `Unrecoverable error`, `signal 11`, `signal 6`, or Vulkan command-buffer failure in Cemu logs
- Cemu logs expected GPU and driver
- `rocknix-guest-v2.service` active after cleanup
- GPU/CPU restored to bounded defaults after cleanup

These gates are intentionally stricter than the current data. If they fail, the report should still be useful by identifying the failure mode.

## Key decisions

### D1 — Validate steady state separately from first-load noise

MangoHud summaries include loading and shader/cache startup, which makes average FPS misleading. The analyzer should compute post-warmup metrics from raw CSV rows, using at least these windows:

- all samples
- samples after 40s
- samples after 70s
- samples after 100s for longer runs

Rationale: previous runs showed all-sample averages around 10-11 FPS while post-load median was near 30 FPS.

### D2 — Prefer profile-power and max-power comparison over more Mesa experiments

Run both:

- `RUNNER_POWER=profile`: mimics host `potato-30` caps and should be cooler/stabler.
- `RUNNER_POWER=max`: checks whether more headroom improves or worsens hitches.

Rationale: previous max-power runs hit near-30 median but still hitched; host scripts intentionally cap CPU/GPU for stability.

### D3 — Keep ROCKNIX Mesa variants diagnostic-only

Include at most one ROCKNIX-Mesa diagnostic variant if time allows, but the winning product candidate must be a Nix-native path unless later work packages the runtime coherently.

Rationale: `start_cemu_guest_rocknixmesa.sh` is useful evidence but not the final architecture.

### D4 — Use screenshots as sanity evidence, not quality scoring

A screenshot can prove a window rendered on DSI-2 and is not black, but it cannot prove smoothness. The report should record screenshot path, size, and whether it is non-empty; FPS/frametime data remains authoritative.

## Implementation units

### U1 — Add a single-run validation orchestrator

**Purpose:** Provide one command that performs the full headless validation and writes a self-contained report.

**Files:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-single-run-validation.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**

Create a host-side script that wraps `remote-cemu-runner.sh` sequentially. It should create a parent directory like:

`/storage/.guest/runs/<timestamp>-single-run-validation/`

Inside it, write:

- `report.md`
- `summary.csv` or `summary.tsv`
- `manifest.txt` listing each child run directory
- copied or linked key artifacts from each child run
- `final-state.txt`

The default matrix should be short enough to finish unattended but long enough to evaluate steady-state. Suggested default:

1. `RUNNER_POWER=profile guest-gamescope-mangohud potato-30 180`
2. `RUNNER_POWER=profile guest-direct-mangohud potato-30 180`
3. `RUNNER_POWER=max guest-gamescope-mangohud potato-30 180`
4. optional diagnostic: `RUNNER_POWER=profile guest-gamescope-rocknixmesa-mangohud potato-30 180`

The script should continue after an individual variant fails, record the failure, cleanup, and continue to the next variant.

**Test scenarios:**

- `sh -n remote-cemu-single-run-validation.sh` passes.
- Running with a deliberately unknown variant records a failed child run and still emits `report.md`.
- Running cleanup at the end leaves `rocknix-guest-v2.service` active.
- The parent report includes every child run directory and a final recommended candidate.

### U2 — Add CSV analysis and pass/fail classification

**Purpose:** Convert MangoHud CSV output into actionable remote evidence.

**Files:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-single-run-validation.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh` if small metadata improvements are needed

**Approach:**

Parse each child run's raw MangoHud CSV and compute, per warmup cutoff:

- sample count
- average FPS
- min FPS
- p1 FPS
- p10 FPS
- median FPS
- max FPS
- frame-time average and max when available
- number of samples below 15 FPS and below 20 FPS after warmup

Also extract:

- time-to-first title containing `FPS:` from `title-samples.log`
- final/representative Cemu title FPS
- driver version from `guest-state.txt`
- Cemu error signatures from `guest-state.txt` and `cemu-stdout.log`
- thermal max from `host-state.txt`
- screenshot path and non-empty size

The report should classify each variant as:

- `PASS`: clears all gates
- `WARN`: reaches in-game and median is good, but lows/hitches fail
- `FAIL`: launch/crash/driver/rendering failure

**Test scenarios:**

- Analyzer handles missing CSV by marking the variant `FAIL` or `WARN` with a clear reason.
- Analyzer ignores MangoHud metadata rows and uses the raw `fps,...,elapsed` table.
- Analyzer does not trust all-sample average alone.
- Analyzer flags known bad signatures: `failed to submit command buffer`, `Unrecoverable error`, `signal 11`, `signal 6`, mixed Vulkan loader maps.

### U3 — Strengthen runner metadata for headless report quality

**Purpose:** Make each child run self-describing enough to debug later without the terminal scrollback.

**Files:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-cleanup.sh`

**Approach:**

Add lightweight metadata, avoiding architectural churn:

- write `variant.env` with variant/profile/duration/power/start/end timestamps
- write `driver.txt` with GPU/driver extracted from Cemu log
- write `errors.txt` with known bad signatures if any
- write `first-fps-seconds.txt` when title samples show first in-game FPS
- ensure the run directory is printed as the final line for reliable orchestration

**Test scenarios:**

- Existing direct/gamescope variants still work.
- Unknown variants still fail fast.
- Runner final line remains the run directory path.
- Cleanup still avoids broad `pgrep -f` matching nspawn bind arguments.

### U4 — Execute one unattended validation run and update the audit

**Purpose:** Produce the answer the user needs while they are away from the device.

**Files:**

- `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- `docs/plans/2026-05-09-001-fix-layer14-cemu-host-performance-plan.md` if the result changes next steps

**Approach:**

After deploying the scripts to Thor, run the single orchestrator once. The run should restore state at the end and produce a parent `report.md`. Copy key report results back into the repo audit doc.

**Validation scenarios:**

- Thor remains reachable over SSH throughout.
- Parent report exists and has pass/warn/fail classifications.
- At least one guest variant reaches in-game.
- Final cleanup leaves no Cemu/gamescope processes running.
- Final state shows guest service active and CPU/GPU restored.

## Run command

Once U1-U3 are implemented and deployed, the intended single command is:

```sh
ssh root@thor '/storage/.guest/remote-cemu-single-run-validation.sh potato-30'
```

The command should print the parent validation directory as its final line. The primary artifact is:

```sh
/storage/.guest/runs/<timestamp>-single-run-validation/report.md
```

## Risks and mitigations

- **Long unattended run time:** keep default matrix to 3-4 variants at 180s each, with per-child cleanup.
- **Thermal drift across variants:** record order, thermals, and run both profile and max power; prefer profile if max improves median but worsens lows.
- **MangoHud overhead:** include non-MangoHud runner variants later if CSV shows suspicious overlay impact. For this single-run plan, MangoHud is necessary for quantitative evidence.
- **Host-control ambiguity in thin-host mode:** do not block on host-control; current host scripts expect host Wayland. Treat guest quantitative gates as the immediate decision mechanism.
- **False confidence from screenshots:** screenshot only proves rendering, not smoothness.

## Expected output interpretation

- If `guest-gamescope-mangohud` with `RUNNER_POWER=profile` passes the gates, make gamescope/profile power the default candidate for `potato-30` and keep MangoHud off outside diagnostics.
- If median passes but p1/p10 fail, the next work should focus on shader/cache warmup, storage/cache placement, and Cemu settings rather than Mesa version.
- If profile power beats max power in lows, wire host-side profile tuning into the guest launcher path.
- If all variants fail similarly, investigate compositor/session scheduling and guest service environment before more Cemu packaging work.
