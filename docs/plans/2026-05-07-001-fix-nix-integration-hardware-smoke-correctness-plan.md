---
title: "fix: Nix integration hardware smoke and running-detection correctness"
type: fix
status: active
date: 2026-05-07
verify_command: "projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh && projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh"
---

# fix: Nix integration hardware smoke and running-detection correctness

## Summary

Tighten `nixctl`'s guest-running detection and the Layer 10/11/12 hardware smoke so the packaged smoke runs cleanly on a configured ROCKNIX device. Replace argv-grep idioms that self-match, fix `systemctl is-enabled` semantics that misclassify `static` units as autostart-eligible, make the hardware smoke runnable from the installed `/usr/lib/nix-integration/tests/` layout, and stop running the CI fixture preamble on hardware-only invocations.

---

## Problem Frame

During Layer 10b hardware validation on `thor`, four correctness defects in `projects/ROCKNIX/packages/tools/nix-integration/` blocked the packaged hardware smoke from running end-to-end and caused `nixctl guest status` to false-positive `running: yes`. The defects are tightly scoped to the smoke and one helper in `nixctl`, but they mask the very lifecycle behavior the smoke is supposed to verify, so they materially reduce confidence in Layer 10b/11/12 hardware Go decisions until corrected.

The Layer 10b validation succeeded only by hand-running an out-of-band start/stop sequence that worked around all four issues. None of the layer contracts (10, 10b, 11, 12) are wrong; the verification surface around them is.

---

## Requirements

- R1. `nixctl`'s `running` detection must not match shells, scripts, or pipelines whose argv merely contains the string `systemd-nspawn` or the guest-root path.
- R2. The smoke's "no enabled unit" check must treat a `static` unit (no `[Install]` section) as not autostart-eligible, while still flagging `enabled` and `enabled-runtime` correctly.
- R3. `LAYER10_SMOKE=bootable`, `LAYER11_SMOKE=1`, and `LAYER12_SMOKE=ssh` must run end-to-end from the packaged smoke at `/usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh` on a configured device.
- R4. CI fixture-only assertions (e.g., the unsafe-guest-root fixture pinning the error string `refusing unsafe guest root`) must not run on a configured device where the same input produces a different but legitimate failure (`root already exists`).
- R5. None of the Layer 10/10b/11/12 contracts change.
- R6. Repo-mode invocations of the smoke (CI, `tests/...` from a checkout) must continue to exercise the existing fixture preamble unchanged.

---

## Scope Boundaries

- Splitting `nix-integration-runtime-smoke.sh` into separate hardware-only and CI-only scripts. A single-file gate is sufficient.
- Layer 12 hardware validation. Tracked separately; it runs after these fixes land.
- Backporting these fixes to the already-flashed `2d394bec52` Layer 10b image. The next image rebuild carries them.
- Refactors to `nixctl`'s broader status reporting, command surface, or persistent-state schema beyond the running-detection helper.
- Adding new test categories or fixtures unrelated to the four findings.
- Changing the `nix-doctor` Layer 10/11/12 reporting surface.

---

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl` — `layer9_running` and `layer10_running` use the `ps -ef | grep '[s]ystemd-' + 'nspawn' | grep -F -- "<root>"` idiom. `layer10_running` is consumed by `cmd_guest_status`, `cmd_guest_run`, `cmd_guest_start`, `cmd_guest_stop`, `layer11_eligibility`, and `layer12_state`.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh` — `layer9_guest_running`, `layer10_guest_running`, `layer11_guest_running`, `layer12_guest_running` use the same idiom. `layer9_no_enabled_unit` and `layer10_no_enabled_unit` use exit-code-only `systemctl is-enabled` semantics.
- `projects/ROCKNIX/packages/tools/nix-integration/package.mk` — installs `tests/nix-integration-runtime-smoke.sh` at `/usr/lib/nix-integration/tests/`, with no sibling `profile.d/`, `scripts/`, or `system.d/`. The smoke's `PKG_DIR=$SCRIPT_DIR/..` resolves to `/usr/lib/nix-integration/`, so any `${PKG_DIR}/scripts/...` reference fails on a device.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/` and the existing `FAKE_NSPAWN` helper in the smoke (`sleep 300` for `--boot`, immediate output otherwise) is the pattern to extend for new fixture coverage.
- The fixture preamble in `nix-integration-runtime-smoke.sh` runs unconditionally before the gated `LAYER*_SMOKE` device sections. Its final fixture sets `NIX_LAYER10_GUEST_ROOT=/storage` to provoke "refusing unsafe guest root"; on a real device `/storage` exists as a directory, so the import fails earlier with `root already exists`, the `grep -q 'refusing unsafe guest root'` fails under `set -e`, and the smoke aborts before reaching the hardware section.

### Institutional Learnings

- `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md` — already documents the broader problem of trusting state files alone; this plan addresses the matching live-process detector that backs the running state.
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md` — Layer 10/10b/11/12 operator flow and validation evidence captured here is the public surface this plan must keep correct.

### External References

- `pgrep(1)` from `procps-ng` supports `-x` (exact comm match) and `-a` (full command line), used to replace the argv-grep idiom. ROCKNIX ships `procps-ng`, so both flags are available on device.
- `proc(5)` `/proc/<pid>/cmdline` is NUL-separated, so `tr '\0' '\n' </proc/<pid>/cmdline` yields one argument per line for safe substring matching against the guest-root path.

---

## Key Technical Decisions

- **Process detection by exec-name + cmdline scan, not argv grep.** Use `pgrep -x systemd-nspawn` to find candidate PIDs by exact program name, then read `/proc/<pid>/cmdline` and check for an argument equal to or starting with `--directory=<root>`. This eliminates self-match because the parent shell's exec name is `sh`, not `systemd-nspawn`. Centralize the detector in one helper in `nixctl` and one helper in the smoke, both behaviorally identical.
- **Autostart eligibility = explicit allowlist of `is-enabled` states.** Treat only `enabled`, `enabled-runtime`, and `alias` as autostart-eligible. `static`, `disabled`, `masked`, `linked`, `transient`, `generated`, `indirect`, and "not-found" are all not autostart. Capture `is-enabled` stdout with `2>/dev/null` and case-match.
- **Hardware sections discover binaries via PATH; fixture preamble keeps using `${PKG_DIR}`.** Introduce a `resolve_smoke_bin <name>` helper used only inside the gated `LAYER*_SMOKE` device sections. It returns the first hit from PATH (`/usr/bin/nixctl`, `/usr/bin/nix-doctor` on device) and falls back to `${PKG_DIR}/scripts/<name>` for repo invocations. Fixture preamble continues using explicit `${PKG_DIR}/scripts/` references because the fixtures need the in-tree script, not the installed one.
- **Single gate for "skip CI fixture preamble".** When at least one hardware-mode flag is set (`LAYER10_SMOKE=bootable`, `LAYER11_SMOKE=1`, or `LAYER12_SMOKE=ssh`) and no CI-mode flag is set (`LAYER4_SMOKE`, `LAYER5_SMOKE`, `LAYER6_SMOKE`, `LAYER7_SMOKE`, `LAYER8_SMOKE`, `LAYER9_SMOKE`, `LAYER10_SMOKE=proof`), skip the fixture preamble and go straight to hardware sections. Default invocation (no flags) and any CI-mode invocation keep current behavior.
- **`LAYER10_SMOKE=proof` stays in the CI-mode bucket.** Proof mode runs against a fixture-staged proof rootfs and shares fixture-preamble assumptions; only `bootable` is the hardware-mode case for Layer 10.
- **Bug-fix-only posture.** No new commands, flags, or contract surface. The smoke shape, file location, and invocation style stay the same.

---

## Open Questions

### Resolved During Planning

- **Should the fix split the smoke file?** No. A single-file gate keeps the fixture suite where it is and limits blast radius.
- **Should `nixctl`'s state machine be reworked?** No. Only the `layer*_running` helpers change; everything that consumes them keeps its current contract.
- **What about `LAYER10_SMOKE=proof`?** It stays in the fixture-preamble-runs bucket because the proof flow is fixture-staged.

### Deferred to Implementation

- Exact name and signature of the new running-detector and path-resolver helpers in `nixctl` and the smoke. Pick names consistent with existing `layer10_*` / `resolve_*` style at implementation time.
- Whether the new `nixctl` running-detector helper additionally falls back to the legacy `ps -ef` path when `pgrep` is unavailable. Probe for `pgrep -x` once at first call; if absent, fail closed (treat as not running) and let `nix-doctor` surface the missing dependency. Decide at implementation time if a richer fallback is worth the code.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
nixctl::layer10_running()                tests::layer10_guest_running()
       │                                          │
       └──────────► common detector shape ◄───────┘
                    pgrep -x systemd-nspawn
                      │
                      ▼
                    for each PID:
                      read /proc/$PID/cmdline (NUL-separated)
                      if any argument matches "--directory=<root>"
                         or equals "<root>"
                      then return running

tests/nix-integration-runtime-smoke.sh
   ┌────────────────────────────────────────────────┐
   │ if hardware-only invocation:                   │
   │     skip fixture preamble                      │
   │     resolve nixctl/nix-doctor via PATH         │
   │ else:                                          │
   │     run fixture preamble (PKG_DIR/scripts)     │
   │     resolve nixctl/nix-doctor via PKG_DIR      │
   │ run any LAYER*_SMOKE sections that are gated   │
   └────────────────────────────────────────────────┘
```

---

## Implementation Units

### U1. Replace argv-grep running detection in `nixctl` with exec-name + cmdline scan

**Goal:** Stop `layer9_running` and `layer10_running` from matching any process whose argv contains the literal `systemd-nspawn` substring or the guest-root path.

**Requirements:** R1, R5

**Dependencies:** None

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Introduce a single private helper that returns running/not-running for a given guest root by enumerating `pgrep -x systemd-nspawn` candidates and inspecting each `/proc/<pid>/cmdline`.
- Match an argument that is exactly the guest root, or starts with `--directory=<root>` (account for both `--directory=<root>` and `--directory <root>` argv forms).
- Replace both `layer9_running` and `layer10_running` bodies with calls to the helper.
- Keep all existing call sites and return-code semantics unchanged.

**Patterns to follow:**
- Reuse the `canonical_path` helper already in `nixctl` to normalize the guest-root argument before comparison.
- Match the existing `layer*_state`/`layer*_eligibility` helper style for naming and shell idioms.

**Test scenarios:**
- Happy path: a live `systemd-nspawn --boot --register=no --directory=/tmp/<root>` process is detected as running for `/tmp/<root>`.
- Edge case: argv form `--directory /tmp/<root>` (space-separated) is detected.
- Edge case: argv form `--directory=/tmp/<root>/` (trailing slash) is detected.
- Regression: a shell whose argv contains the substring `systemd-nspawn` and the guest-root path but whose exec name is `sh` is reported as not running. This is the exact false-positive observed during Layer 10b validation.
- Edge case: no `pgrep` binary on PATH → helper reports not running and the smoke records a skip note rather than crashing.
- Integration: extend the existing fixture-mode `FAKE_NSPAWN` smoke section so a backgrounded `--boot` instance is detected and a foregrounded immediate-exit instance is not.

**Verification:**
- Static check confirms the new helper is defined and used by both `layer9_running` and `layer10_running`.
- Runtime smoke fixture coverage above passes.
- On `thor`, running `bash -c '... systemd-nspawn ... /storage/machines/rocknix-guest ...'` no longer flips `nixctl guest status` to `running: yes` while no real nspawn is alive.

---

### U2. Fix autostart-detection semantics in the runtime smoke

**Goal:** `layer9_no_enabled_unit` and `layer10_no_enabled_unit` must reject `static` and "not-found" as not autostart-eligible while still flagging `enabled` and `enabled-runtime` correctly.

**Requirements:** R2, R5

**Dependencies:** None

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Introduce a `unit_autostarts <unit-name>` helper that captures `systemctl is-enabled <unit> 2>/dev/null` stdout and returns true only when the value is `enabled`, `enabled-runtime`, or `alias`.
- Replace the body of `layer9_no_enabled_unit` and `layer10_no_enabled_unit` with negated calls to the helper. Keep both helper names and call sites intact so the rest of the smoke is unaffected.
- Skip gracefully when `systemctl` is unavailable (existing behavior).

**Patterns to follow:**
- Existing `layer*_no_enabled_unit` helpers in the same file — keep the same return-code convention.

**Test scenarios:**
- Happy path: a unit whose `is-enabled` returns `static` is treated as not autostart-eligible (this is the current Layer 10 generated unit case).
- Happy path: a unit whose `is-enabled` returns `enabled` is treated as autostart-eligible.
- Edge case: a unit whose `is-enabled` returns `enabled-runtime` is treated as autostart-eligible.
- Edge case: a unit whose `is-enabled` errors with non-zero (e.g., `not-found`, `disabled`, `masked`) is treated as not autostart-eligible.
- Use a fake `systemctl` shim (write to a temp dir, prepend to PATH) to drive each branch deterministically, mirroring how the existing smoke uses `FAKE_NSPAWN`.

**Verification:**
- Runtime smoke fixture coverage above passes against the fake `systemctl`.
- On `thor` after Layer 10 start/stop, the smoke's autostart check no longer flags `rocknix-guest.service` (`static`) as autostart-eligible.

---

### U3. Make hardware smoke sections runnable from the packaged install layout

**Goal:** `LAYER10_SMOKE=bootable`, `LAYER11_SMOKE=1`, and `LAYER12_SMOKE=ssh` run end-to-end from `/usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh` without sibling assets.

**Requirements:** R3, R5, R6

**Dependencies:** U4 (gate must exist so hardware-only invocations skip the fixture preamble that hard-depends on `${PKG_DIR}/scripts/`).

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Introduce a `resolve_smoke_bin <name>` helper used only inside the gated `LAYER10_SMOKE`, `LAYER11_SMOKE`, and `LAYER12_SMOKE` sections. It returns the first match in this order: PATH (via `command -v`), then `${PKG_DIR}/scripts/<name>`.
- Set `NIXCTL` and `DOCTOR` from the helper at the top of each gated hardware section, replacing the current unconditional `${PKG_DIR}/scripts/...` assignment in the device-side block.
- The fixture preamble (`tests/fixtures/...` and the per-fixture environment setup at the top of the file) continues to use explicit `${PKG_DIR}/scripts/` paths because it requires the in-tree script.
- Do not touch `package.mk`; the install layout is correct, the smoke is what was wrong.

**Patterns to follow:**
- The existing `NIXCTL=${PKG_DIR}/scripts/nixctl` pattern just before the `LAYER4_SMOKE` block — keep its shape, swap the right-hand side for the helper call.

**Test scenarios:**
- Repo invocation with no `LAYER*_SMOKE` flag set: behavior identical to today (fixture preamble runs against `${PKG_DIR}/scripts/...`).
- Repo invocation with `LAYER10_SMOKE=proof`: fixture preamble runs, hardware section uses `resolve_smoke_bin` which returns `${PKG_DIR}/scripts/...` because `/usr/bin/nixctl` is not on PATH in repo CI.
- Device invocation with `LAYER10_SMOKE=bootable` from `/usr/lib/nix-integration/tests/...`: fixture preamble is skipped (per U4), hardware section uses `resolve_smoke_bin` which returns `/usr/bin/nixctl`.
- Edge case: `resolve_smoke_bin` called with a name that is neither on PATH nor at `${PKG_DIR}/scripts/<name>` exits non-zero with a clear error, instead of silently producing an empty string that later runs as `""`.

**Verification:**
- Static check asserts the helper is defined and used by all three hardware-mode sections (`LAYER10_SMOKE`, `LAYER11_SMOKE`, `LAYER12_SMOKE`).
- On `thor`, running `LAYER10_SMOKE=bootable /usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh` reaches and executes the Layer 10 hardware section without sourcing or invoking any sibling under `${PKG_DIR}`.

---

### U4. Gate the CI fixture preamble for hardware-only invocations

**Goal:** Skip the fixture preamble when only hardware-mode flags are set, so a configured device cannot abort on fixture-only assertions.

**Requirements:** R3, R4, R6

**Dependencies:** None

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Compute a `HARDWARE_ONLY_MODE` boolean near the top of the file: true iff at least one of `LAYER10_SMOKE=bootable`, `LAYER11_SMOKE=1`, or `LAYER12_SMOKE=ssh` is set, AND none of `LAYER4_SMOKE`, `LAYER5_SMOKE`, `LAYER6_SMOKE`, `LAYER7_SMOKE`, `LAYER8_SMOKE`, `LAYER9_SMOKE`, `LAYER10_SMOKE=proof` is set.
- Wrap the fixture preamble in a single guard that exits-early-with-skip-note when `HARDWARE_ONLY_MODE` is true. The guard goes just after the existing `mktemp -d` / `trap` setup so `TMP_DIR` exists for any later code that touches it.
- Print a single `[smoke] hardware-only mode: skipping CI fixture preamble` line when the gate fires, so the operator can see why fixtures didn't run.
- Default invocation (no flags) keeps the current "fixture preamble runs, then prints skipped messages and exits" behavior unchanged.

**Patterns to follow:**
- The existing `LAYER10_REQUESTED` / `LAYER11_REQUESTED` / `LAYER12_REQUESTED` block just below the fixture preamble — extend the same flag-detection style for the new boolean.

**Test scenarios:**
- Default invocation (no flags): fixture preamble runs, skipped messages print, exit 0. Identical to today.
- `LAYER4_SMOKE=1` (CI mode): fixture preamble runs, Layer 4 section runs. Identical to today.
- `LAYER10_SMOKE=proof` (CI-staged proof mode): fixture preamble runs, proof section runs. Identical to today.
- `LAYER10_SMOKE=bootable` only (hardware): fixture preamble is skipped, hardware section runs.
- `LAYER10_SMOKE=bootable` + `LAYER9_SMOKE=1` (mixed): fixture preamble runs because at least one CI-mode flag is set.
- `LAYER12_SMOKE=ssh` only (hardware): fixture preamble is skipped.
- Regression: the fixture that pins the unsafe-guest-root error string (`grep -q 'refusing unsafe guest root'`) does not execute when `LAYER10_SMOKE=bootable` is set on a configured device.

**Verification:**
- Runtime smoke fixture coverage above passes.
- A static check (or grep-based assertion in `nix-integration-static-checks.sh`) confirms the gate exists and references all six CI-mode flags plus the three hardware-mode flags.
- On `thor`, `LAYER10_SMOKE=bootable /usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh` no longer aborts in the unsafe-guest-root fixture.

---

## System-Wide Impact

- **Interaction graph:** `layer10_running` is consumed by `cmd_guest_status`, `cmd_guest_run`, `cmd_guest_start`, `cmd_guest_stop`, `layer11_eligibility`, `layer12_state`, and `layer12_eligibility`. Tightening it makes every one of those call sites more accurate but does not change their contract — false positives become correct negatives.
- **Error propagation:** None of the four units change error contracts. U1 and U2 narrow what is detected; U3 and U4 change which code paths run for which invocation, not what they emit.
- **State lifecycle risks:** None. `nixctl`'s persisted state files (`state`, `rootfs-provenance`, `updated-at`) are untouched.
- **API surface parity:** `nixctl guest status` `running:` field becomes accurate when an unrelated process happens to have a matching argv substring. This is a behavioral correction in the right direction; no consumer should observe regression.
- **Integration coverage:** `LAYER10_SMOKE=bootable` regains end-to-end coverage on a configured device. `LAYER10_SMOKE=proof` and the unflagged CI invocation are unchanged.
- **Unchanged invariants:** Layer 10/10b/11/12 contracts, `nixctl` command surface, `nix-doctor` reporting structure, the location and invocation style of the smoke, and `package.mk` install layout are all unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `pgrep -x` not available on the test host or device | ROCKNIX ships `procps-ng`. Probe once and fall back to "not running" rather than back to the buggy `ps -ef` idiom; `nix-doctor` already reports environment health. |
| The new running detector misses an argv shape we did not enumerate | Add explicit fixtures for `--directory=<root>`, `--directory <root>`, and trailing-slash forms; if a future call site invents a new shape, the detector is centralized so the fix is one place. |
| `is-enabled` returns a state we did not enumerate (e.g., `linked-runtime`, `transient`) on a future systemd | Allowlist is conservative-by-default — anything outside `enabled`, `enabled-runtime`, `alias` is treated as not autostart. New auto-start states require an explicit code change, which is the desired behavior for a security-adjacent check. |
| `resolve_smoke_bin` accidentally picks up an unrelated `nixctl` on `PATH` in repo CI | Order `${PKG_DIR}/scripts/` first when `HARDWARE_ONLY_MODE` is false; PATH-first only when hardware-only. CI invocations keep current behavior. |
| Fixture preamble gate misclassifies a future flag combination | Single boolean computed in one place; covered by static check that enumerates every flag the gate reads. |

---

## Documentation / Operational Notes

- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md` — note the false-positive history under the Layer 10 Go evidence and link this plan as the corrective change.
- `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md` — extend with a short note that the live-process detector backing the stale-state recovery is now exec-name + cmdline based.
- No operator-facing flag, command, or invocation changes; no rollout coordination required.
- The Layer 10b validation evidence already on `thor` is unaffected — these fixes change what subsequent invocations of the smoke do, not what already happened.

---

## Sources & References

- Related code:
  - `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl` (`layer9_running`, `layer10_running`)
  - `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh` (fixture preamble and `LAYER10_SMOKE` / `LAYER11_SMOKE` / `LAYER12_SMOKE` blocks)
  - `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
- Related plans:
  - `docs/plans/2026-05-06-001-feat-nix-layer-10-managed-guest-operations-plan.md`
  - `docs/plans/2026-05-06-003-feat-nix-layer-10b-bootable-rootfs-plan.md`
  - `docs/plans/2026-05-06-004-feat-nix-layer-12-opt-in-guest-ssh-plan.md`
- Related learnings:
  - `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
- Operator surface:
  - `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
