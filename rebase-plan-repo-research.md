# Repo Research — Rebase/Merge Plan from Custom (Thor-proven) onto Upstream/next

Scope: `/home/simonwjackson/code/sandbox/rocknix` on branch `custom` at
checkpoint `2cb7081c80`. All paths repo-relative. No files modified.

---

## 1. Remotes, Branches, Merge Base

- Remotes (`git remote -v`):
  - `origin` → `simonwjackson/rocknix` (this fork, push target)
  - `upstream` → `ROCKNIX/distribution` (read-only sync source; default = `next`)
- Branches that matter:
  - Local `custom` — current, head `2cb7081c80` (Thor-proven checkpoint)
  - `origin/custom` — same as local head (already published)
  - `upstream/next` — upstream default, head `c71e69fc6f`
  - `upstream/mku`, `upstream/auto-pr-branch` — not relevant for this plan
- Divergence (`git merge-base custom upstream/next` → `be444ff9c1`):
  - `custom` has 182 commits the upstream lacks (all our nix-integration / SM8550 / Thor work).
  - `upstream/next` has 128 commits we lack (AYN-Thor audio, SM8750 init, CI rework, etc.).
  - 283 files differ; full diffstat: `git diff --stat custom upstream/next`.
- Current uncommitted state on `custom`: four untracked planning notes only
  (`base-architecture-minimum.md`, `base-safety-review.md`,
  `base-scout-packages.md`, `base-scout-sm8550.md`). Working tree otherwise clean.

---

## 2. Custom-Owned Surface (must survive merge)

Everything in this section is custom-only — upstream has no equivalent, so the
merge needs to *preserve* it. Most of it is the SM8550 thin-host substrate.

### 2.1 `nix-integration` package (entire subtree, custom-only)

`projects/ROCKNIX/packages/tools/nix-integration/`
- `package.mk` — SHA256-pinned fetch of `simonwjackson/rocknix-nix-guest`
  tarball; SM8550-only guard (`exit 1` on other devices); enables
  `nix-storage-setup.service`, `nix.mount`, `rocknix-graphical.target`,
  `rocknix-guest-v2.service`, `rocknix-guest-promote.service`,
  `rocknix-recovery-toggle.service`; installs runtime smoke under
  `/usr/lib/nix-integration/tests`; ships fallback doc to `/flash/`.
- `scripts/rocknix-guest-prep` — pre-spawn fixup.
- `scripts/rocknix-guest-promote` — `nix build` + profile update + restart
  guest; revision drift repair (added in last 5 commits).
- `scripts/rocknix-guest-soak` — live-device probe (SSH on 127.0.0.1:22,
  resolv ownership, host-/usr leak check, sway/pipewire alive, memory baseline).
- `scripts/rocknix-guest-udev-stage` — scrubs `/run/udev` for guest bind.
- `scripts/rocknix-recovery-toggle` — switches default.target on
  `/flash/rocknix.no-nspawn` or `rocknix.safe=1` cmdline.
- `system.d/{nix.mount,nix-storage-setup.service,rocknix-graphical.target,rocknix-guest-v2.service,rocknix-guest-promote.service,rocknix-recovery-toggle.service}`
- `tests/nix-integration-static-checks.sh` (175 lines) — fail-closed static
  contract; enforces package shape, removed-surface absence, guest unit binds,
  promote-helper contract, soak invariants. **Not currently wired into CI.**
- `tests/nix-integration-runtime-smoke.sh` (108 lines) — both source-tree and
  installed mode; `ROCKNIX_GUEST_LIVE_SMOKE=1` enables on-device probes
  (`/storage/machines/rocknix-guest`, `/nix` mountpoint, default.target value).

### 2.2 SM8550 customizations (custom-only or custom-modified)

- `projects/ROCKNIX/devices/SM8550/options` — adds
  `systemd.unified_cgroup_hierarchy=1` and `systemd.legacy_systemd_cgroup_controller=0`
  to `EXTRA_CMDLINE`, sets `SYSTEMD_DEFAULT_HIERARCHY="unified"`. Required
  for nspawn cgroup v2. **Upstream removed these and changed cmdline to
  `cgroup.memory=nokmem,nosocket`** — conflict.
- `projects/ROCKNIX/packages/sysutils/systemd/package.mk` — adds
  `default-hierarchy=${SYSTEMD_DEFAULT_HIERARCHY:-hybrid}` (parameterized) and
  SM8550-gated keep of `systemd-nspawn` + `systemd-nspawn@.service`.
  **Upstream still hard-codes `default-hierarchy=hybrid` and unconditionally
  strips nspawn** — conflict.
- `projects/ROCKNIX/packages/virtual/image/package.mk` — adds the
  `[ "${DEVICE}" = "SM8550" ] && PKG_DEPENDS_TARGET+=" nix-integration"` line
  (custom-only).
- `projects/ROCKNIX/devices/SM8550/patches/linux/0054-edt-ft5x06-honour-DT-input-name.patch`
  (custom-only) + DT change in `qcs8550-ayn-thor.dts` (`input-name = "ft5x06-top";`)
  to disambiguate the two ft5x06 touchscreens for Wayland. **Upstream rewrote
  the same DTS sections to add audio (model "AYN-Thor", IN1_HPHL routing,
  DMIC3) but did not touch the touchscreen block. The input-name addition will
  conflict structurally even though changes target different parts of the
  same file.**
- Custom commit `4977706975 fix(rocknix): disable thor joystick leds`
  (touches SM8550 device tree / inputplumber config) — verify it's not
  superseded by upstream `c71e69fc6f` (AYN Thor internal mic merge).

### 2.3 Build / CI surface (custom-only or custom-modified)

- `.github/workflows/build-image-only.yml` (custom-only, 213 lines) — fast-iter
  workflow: reuses arm/emu-libretro/emu-standalone artifacts from a prior
  successful `Build` run, runs only the image step, clean-bumps
  `nix-integration` to force `post_install` re-run, ships
  `-thin-host` suffix on SM8550 artifacts. **No upstream equivalent.**
- `.github/workflows/build-device.yml` — custom added the comment-block guard
  on the `purge-artifact` job to skip artifact cleanup on feature branches
  (so the fast-iter workflow can reuse them).
- `.github/workflows/build-aarch64-image.yml` — custom adds the
  `-thin-host` artifact-suffix step for `DEVICE=SM8550`. **Upstream removed
  this and added `SM8750` exclusions** — conflict.
- `.github/workflows/trigger-fail-if-upstream-changed.yml` — custom changed
  trigger from `pull_request` to manual-only (because the fork intentionally
  patches upstream packages, e.g. systemd). Comment explicitly mentions
  "Layer 9 NixOS-in-nspawn".
- `Dockerfile`, `Makefile`, `scripts/local-image-build`, `flake.nix`,
  `flake.lock` — custom-modified or custom-only. `scripts/local-image-build`
  documents the SSH-safety contract (CPU/memory caps, "host SSH must stay
  responsive"). **Upstream deleted `scripts/local-image-build`** — conflict
  is "modify vs delete"; keep ours.

### 2.4 Documentation / planning artifacts

- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
  (custom-only, 803 lines) — full Layer 4-14 history.
- `base-architecture-minimum.md`, `base-safety-review.md`,
  `base-scout-packages.md`, `base-scout-sm8550.md` — present in working tree
  only (untracked). Need to decide: commit on `custom` *before* rebase, or
  stash and re-apply after.

---

## 3. Upstream-Incoming Changes (must survive merge)

128 upstream commits. Highest-risk overlaps:

### 3.1 SM8550 device files (overlap territory)

- `projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayn-thor.dts`
  — upstream adds full audio model (commit `c71e69fc6f` "AYN Thor internal mic"
  via merged PR #2675; commit `1443758698` "Add AYN Thor audio support").
- `qcs8550-ayaneo-pocket-common.dtsi`, `qcs8550-ayn-common.dtsi`,
  `qcs8550-retroidpocket-rp6.dts` — upstream changes.
- New firmware blob: `projects/ROCKNIX/devices/SM8550/filesystem/usr/lib/kernel-overlays/base/lib/firmware/qcom/sm8550/AYN-Thor-tplg.bin`.
- New patches:
  - `0070-drm-msm-remove-DRIVER_SYNCOBJ_TIMELINE.patch`
  - `0104-drm-panel-Add-Retroid-Pocket-6-panel.patch`
  - `0200-ASoC-wcd938x-add-DMIC-DAPM-inputs.patch`
  - `projects/ROCKNIX/packages/audio/alsa-ucm-conf/patches/SM8550/0005_Add-AYN-Thor.patch`
- `projects/ROCKNIX/devices/SM8550/linux/linux.aarch64.conf` — small upstream change.
- New quirks: `005-thermal_path`, `020-fan_control`, `095-force_zink`,
  `bin/fancontrol` under
  `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/`.

These all matter for SM8550 functionality and intersect with custom's
Thor / SM8550 patches. **Expect non-trivial DTS / patch conflicts.**

### 3.2 CI workflow churn (overlap territory)

- `.github/workflows/build-aarch64-image.yml` — SM8750 exclusions added; the
  custom `-thin-host` suffix step deleted in upstream. Need to preserve
  custom step.
- `.github/workflows/build-nightly.yml` — large rewrite upstream (monthly
  release schedule, runner start-time change, debug-deps step).
- `.github/workflows/build-device.yml` — small upstream changes (the
  feature-freeze gate) intersect with the custom purge-job comment.
- `.github/workflows/build-aarch64-toolchain.yml` — upstream moved `llvm:host`
  here.
- `.github/workflows/build-aarch64-emu-standalone.yml`, `build-aarch64-qt6.yml`,
  `build-arm.yml` — SM8750 added to allowlists.
- New upstream: `.github/workflows/feature-freeze.yml`, `.github/scripts/generate-release-body.sh`.
- `.github/release-body.md` — deleted upstream (replaced by script). Custom
  doesn't touch this; safe to take upstream.
- `.github/workflows/trigger-fail-if-upstream-changed.yml` — upstream
  diverged (still pull-request-triggered there); **custom intentionally
  switched to manual-only — keep ours**.

### 3.3 Other upstream changes worth noting

- `Dockerfile` — upstream changes 43 lines; custom also changed it.
- `Makefile` — 6-line upstream change; small.
- `scripts/checkdeps` — upstream bumped gcc dep mappings.
- `flake.nix` / `flake.lock` deleted upstream (we own them).
- Removed packages: `waylandpp` + its patch (upstream cleanup).
- Many emulator/quirks updates: `mangohud` SM8750 patch, RA jitter, GPcal
  inputplumber stop, Retroid Pocket 6 panel, fex-emu 25-05, etc. These are
  unlikely to conflict structurally with custom changes but should be
  reviewed for SM8550 side-effects.

---

## 4. Validation Surface (what the plan must use)

### 4.1 Existing static checks (`tests/`)

Both run from the package directory, no on-device required for the static side:

- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
  - Enforces package shape (no Layer 4-13 surface, manual toolchain, fetched
    guest tarball, mandatory SHA256 verify).
  - Enforces guest unit binds (`--bind=/dev/input`, `--bind=/dev/snd`,
    `--bind-ro=/run/.guest-udev:/run/udev`, no `--bind-ro=/usr`, no
    `--bind-ro=/lib`, no `ExecStopPost=`, must be `WantedBy=rocknix-graphical.target`).
  - Enforces promote-helper contract (`nix build`, `nix-env -p
    /nix/var/nix/profiles/system --set`, restart guest, `rocknix-guest-revision`
    marker, `resolve_guest_system_profile`, drift-repair messages).
  - Enforces soak-helper invariants (`check_host_ssh_responsive`,
    `check_resolv_owned`).
  - Forbidden tokens scan (`NIX_INTEGRATION_SUPPORT`, `NIX_NSPAWN_SUPPORT`,
    `NIX_DAEMON_SUPPORT`, `THIN_HOST`) across the tree.

- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
  - Source-tree mode: checks files/units/scripts present in
    `${PKG_DIR}/{scripts,system.d}`.
  - Installed mode: checks `/usr/bin/rocknix-*`, `/usr/lib/systemd/system/*`.
  - `ROCKNIX_GUEST_LIVE_SMOKE=1` on device: `/storage/machines/rocknix-guest`,
    `/storage/.nix-root`, `/nix` mounted, all four units installed,
    `systemctl get-default` ∈ {`rocknix-graphical.target`, `rocknix.target`}.

### 4.2 On-device validation (`rocknix-guest-soak`)

`projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-guest-soak`
samples:
- Host SSH on `127.0.0.1:22` (the canonical SSH-keep probe).
- Guest resolv-ownership (no host leak through `/etc/resolv.conf`).
- Host-/usr leak check via guest `$PATH`.
- Sway / pipewire alive inside guest.
- Baseline memory growth.

This is the only on-device check that exercises the SSH-keep invariant
end-to-end. **It is not currently called from CI** — only manually on the
device.

### 4.3 SSH-keep mechanism (the floor of validation)

- `packages/network/openssh/system.d/sshd.service` — `WantedBy=multi-user.target`,
  gated by `ConditionKernelCommandLine=|ssh` OR
  `ConditionPathExists=|/storage/.cache/services/sshd.conf`.
- `packages/network/openssh/package.mk` — `enable_service sshd.service` always;
  Condition gates remain.
- `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-graphical.target`
  declares `Requires=multi-user.target` so the guest plane cannot replace the
  SSH plane.
- **`packages/network/openssh/` has no incoming upstream diff** (`git diff
  --stat custom upstream/next -- packages/network/openssh` is empty). Safe.

### 4.4 CI validation entry points

- `.github/workflows/build-nightly.yml` — full 11-device matrix; default
  device set is now `SM8550` only on the custom branch. Useful for confirming
  the merged tree builds end-to-end on SM8550.
- `.github/workflows/build-image-only.yml` — fast-iter, ~30 min vs ~5 h.
  Requires a prior successful `Build` run on the same branch. Will be the
  primary validation harness post-merge (image-step changes only).
- Neither workflow currently invokes
  `tests/nix-integration-static-checks.sh` or `nix-integration-runtime-smoke.sh`
  outside the package build itself. Static checks ride along with
  `post_install`, so they execute whenever nix-integration builds.

---

## 5. Thor Install / Verification Pattern

Reading the on-device update flow + the local target artifacts (the two
existing fast-iter outputs in `target/`):

### 5.1 Artifact shape (already produced by `build-image-only.yml`)

Two folders already live in `target/` on this checkout:
- `target/ROCKNIX-update-SM8550-thin-host-20260511-fastiter/`
- `target/ROCKNIX-update-SM8550-thin-host-20260512-fastiter/`

Each contains exactly:
- `ROCKNIX-SM8550.aarch64-<date>.tar`
- `ROCKNIX-SM8550.aarch64-<date>.tar.sha256`

The image variant (workflow uploads both) would additionally drop
`ROCKNIX-*.img.gz` + sha256 under
`ROCKNIX-image-SM8550-thin-host-<date>-fastiter/`.

### 5.2 Install path on device (legacy ROCKNIX flow, reused)

- Drop `.tar` + `.tar.sha256` into `/storage/.update/` on the device.
- `projects/ROCKNIX/packages/rocknix/sources/scripts/rocknix-update`
  handles checks and downloads from `update.rocknix.org` when invoked
  online; for hand-flashed builds the user copies the `.tar` directly.
- `projects/ROCKNIX/devices/SM8550/bootloader/update.sh` (host) updates the
  ABL via `$SYSTEM_ROOT/usr/bin/updateabl`, writes `UPDATE` to
  `/storage/.boot.hint`, remounts `/flash` ro, requires a reboot.
- On next boot, `projects/ROCKNIX/packages/rocknix/autostart/003-upgrade`
  reads `/storage/.boot.hint == UPDATE` and runs
  `/usr/share/post-update` (i.e. `projects/ROCKNIX/packages/rocknix/sources/post-update`)
  which rebuilds the library cache, syncs configs, etc. The post-update
  script logs to `/var/log/upgrade.log`.
- ABL checksum is enforced by `updateabl`
  (`projects/ROCKNIX/packages/rocknix/sources/scripts/updateabl`,
  `SUM_UPDATE=$($SYSTEM_ROOT/usr/bin/sha256sum "${ELF}" | awk '{print $1}')`).

### 5.3 Verification on device (in order)

1. **Boot reaches `multi-user.target`** — SSH is gated on it (Section 4.3).
   If SSH stops answering on `:22` the merge is invalid; this is the
   non-negotiable floor.
2. **Recovery escape works** — `touch /flash/rocknix.no-nspawn` (or
   `rocknix.safe=1` cmdline) flips `default.target` back to
   `rocknix.target` via the toggle oneshot. Documented in
   `/flash/HOW-TO-FALL-BACK.md` (shipped from
   `rocknix-nix-guest/docs/contracts/HOW-TO-FALL-BACK.md`).
3. **Runtime smoke** — `ROCKNIX_GUEST_LIVE_SMOKE=1
   /usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh` exits 0.
4. **Soak** — `rocknix-guest-soak` exits 0 (sampling SSH, resolv, PATH,
   sway/pipewire, memory).
5. **Promote idempotence** — `systemctl restart rocknix-guest-promote.service`
   succeeds without drift after a clean boot (drift-repair branch is the
   newest behavior, last 4 commits on `custom`).

---

## 6. Repo Conventions (worth aligning the plan to)

- **Commit messages**: conventional commits with scope. Dominant scopes on
  recent custom history: `fix(nix-integration)`, `refactor(nix-integration)`,
  `feat(rocknix)`, `chore(rocknix)`, `test(nix-integration)`, `docs(rocknix)`.
  Upstream itself uses sentence-style commit subjects and merge commits
  (`Merge pull request #XXXX from author/branch`).
- **PR template** (`.github/pull_request_template.md`): Summary / Testing
  (with device + build artifact URL) / Additional Context / AI Usage (YES |
  PARTIALLY | NO). The `ai-usage.yml` workflow auto-labels.
- **Issue template**: `.github/ISSUE_TEMPLATE/bug-report.md` + `config.yml`.
- **Upstream-package guard**: `.github/workflows/trigger-fail-if-upstream-changed.yml`
  was originally a `pull_request` block on changes to `packages/`. Custom
  intentionally relaxed it to `workflow_dispatch` so we can patch
  `packages/systemd` etc. Keep the relaxed form post-merge.
- **Device-gating discipline**: anything host-shape-changing on SM8550 must
  be guarded by `[ "${DEVICE}" = "SM8550" ]` so the other 10 device images
  keep building byte-identical to upstream. The static checks already
  enforce this at the package level. Three current gating sites:
  - `projects/ROCKNIX/packages/virtual/image/package.mk` (SM8550-only
    `PKG_DEPENDS_TARGET+=" nix-integration"`)
  - `projects/ROCKNIX/packages/sysutils/systemd/package.mk` (SM8550-only
    keep of `systemd-nspawn`)
  - `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
    (SM8550-only `exit 1` guard)
- **Tests live next to package**: `projects/ROCKNIX/packages/tools/nix-integration/tests/`.
  No top-level `tests/` directory. `make test` not wired.
- **Build env**: ubuntu-24.04 runners, podman-rootless locally via
  `scripts/local-image-build`, ccache + maximize-runner-space pattern.

---

## 7. Conflict-Risk Inventory (file-by-file)

High-risk (custom and upstream both touched, semantic conflict expected):

| File | Custom side | Upstream side |
|------|-------------|---------------|
| `projects/ROCKNIX/devices/SM8550/options` | adds unified cgroup cmdline + var | rewrote cmdline to `cgroup.memory=...` |
| `projects/ROCKNIX/packages/sysutils/systemd/package.mk` | param hierarchy + SM8550 nspawn keep | hard-codes hybrid + strips nspawn always |
| `projects/ROCKNIX/packages/virtual/image/package.mk` | adds SM8550 nix-integration dep | removed (line not present) |
| `projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayn-thor.dts` | `input-name` on touchscreen | full audio model added |
| `projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayaneo-pocket-common.dtsi` | (TBD) | upstream changed |
| `projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayn-common.dtsi` | (TBD) | upstream changed |
| `.github/workflows/build-aarch64-image.yml` | `-thin-host` suffix step | removed; added SM8750 exclusions |
| `.github/workflows/build-device.yml` | feature-branch purge skip comment | upstream small change |
| `.github/workflows/build-nightly.yml` | SM8550-only default device set | large rewrite (monthly release etc.) |
| `.github/workflows/trigger-fail-if-upstream-changed.yml` | manual-only | upstream still PR-triggered |
| `Dockerfile` | custom mods | 43-line upstream change |
| `Makefile` | custom mods | 6-line upstream change |
| `scripts/local-image-build` | exists (410 lines) | deleted upstream |
| `flake.nix`, `flake.lock` | exist | absent upstream |

Medium-risk (custom adds, upstream untouched — should be clean):

- All of `projects/ROCKNIX/packages/tools/nix-integration/` subtree.
- `.github/workflows/build-image-only.yml` (custom-only).
- Custom commits adding `projects/ROCKNIX/devices/SM8550/patches/linux/0054-edt-ft5x06-honour-DT-input-name.patch`.

Low-risk (upstream adds in territory custom doesn't touch):

- All new upstream patches under `projects/ROCKNIX/devices/SM8550/patches/linux/0070-`, `0104-`, `0200-`.
- All upstream quirks files under `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/{005,020,095}-*`.
- Upstream-only file `projects/ROCKNIX/devices/SM8550/filesystem/usr/lib/kernel-overlays/base/lib/firmware/qcom/sm8550/AYN-Thor-tplg.bin`.
- `.github/workflows/feature-freeze.yml` (new upstream).
- `.github/scripts/generate-release-body.sh` (new upstream).

---

## 8. Open Questions / Gaps Worth Resolving Before Rebase

1. **Untracked planning docs** (`base-*.md`): commit on `custom` first, or
   stash? They reference the current state of nix-integration; once the
   merge lands and Thor audio paths change, parts of `base-scout-sm8550.md`
   may need updating.
2. **Static checks in CI**: `nix-integration-static-checks.sh` is not run
   by any workflow today. The natural place to wire it is a new lightweight
   workflow that runs `sh -n` + the static script on PR. This would catch
   merge breakage in ~30 s instead of waiting for a 5 h build. Out of
   scope for the merge itself, but worth flagging.
3. **Recovery readme** (`HOW-TO-FALL-BACK.md`) is fetched from the pinned
   `rocknix-nix-guest` tarball at build time. After the merge, confirm
   the guest pin (`PKG_NIX_GUEST_REV=5f1a19c3...` in `package.mk`) still
   builds against an upstream that may have changed the SM8550 audio /
   firmware shape — the guest's own audio config may need a bump.
4. **AYN Thor audio + custom touchscreen disambiguation**: both edit the
   same `qcs8550-ayn-thor.dts` file in non-overlapping sections, but
   `git merge`'s line-based resolution may produce churn. Plan a manual
   diff review of the resolved file before committing.
5. **SM8750 init** is new upstream and is *not* covered by custom's
   SM8550-only gating. Verify the new device path doesn't accidentally
   pull `nix-integration` (it shouldn't — image meta gates it on
   `SM8550`).
6. **Fast-iter base run after merge**: the merge commit will be a new SHA,
   so `build-image-only.yml` will need a fresh "Build" run as its base.
   Plan for one full `build-nightly.yml` (SM8550-only) right after the
   merge to populate the artifact cache for subsequent fast-iter runs.

---

## 9. Recommended Next Steps for the Planner

(These are observations, not prescriptions — the planner owns the strategy.)

1. **Commit the planning notes first** so they're versioned alongside the
   merge state (`base-*.md` → `custom` HEAD).
2. **Pick merge strategy** with awareness that:
   - Many overlap files are *semantic* conflicts (gating logic, parameterized
     vs hard-coded values), not just text overlaps. A straight `git merge -X
     theirs/ours` will silently lose invariants — avoid.
   - Custom's checkpoint `2cb7081c80` is the only validated state. Any
     intermediate state during the rebase that breaks the static checks is
     not a checkpoint we can resume from on device.
3. **Validation order** (cheapest → most expensive):
   - `sh -n` over all touched shell scripts.
   - `bash tests/nix-integration-static-checks.sh` from the package dir.
   - `bash tests/nix-integration-runtime-smoke.sh` (source-tree mode).
   - Trigger `build-image-only.yml` for SM8550 against the prior `Build`
     run (still valid only until the artifacts age out).
   - If artifact base aged out: trigger `build-nightly.yml` with default
     `SM8550` device.
   - Flash the produced `.tar`, reboot, run on-device:
     `ROCKNIX_GUEST_LIVE_SMOKE=1 nix-integration-runtime-smoke.sh` →
     `rocknix-guest-soak` → manually confirm host SSH still answers and
     `/flash/HOW-TO-FALL-BACK.md` is present.
4. **SSH-keep invariant** is the gating check at every step:
   - `WantedBy=multi-user.target` on `sshd.service` must survive.
   - `Requires=multi-user.target` on `rocknix-graphical.target` must
     survive.
   - The condition gates (`|ssh` cmdline / sshd.conf path) must survive.
   - Soak's `check_host_ssh_responsive` is the canonical probe; keep it
     green at every checkpoint.
