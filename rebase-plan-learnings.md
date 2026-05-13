# Institutional Learnings — Upstream Rebase of `custom` after Thor Checkpoint

## Search Context

- **Feature/Task**: Plan an upstream rebase of the `custom` branch (rocknix fork) after a Thor-verified checkpoint. Need prior learnings on custom fork updates, fast-iter builds, local + Thor validation, and branch/rebase workflow.
- **Keywords searched**: `rebase`, `upstream`, `custom-fork`, `fork update`, `BUILD_BRANCH`, `fast-iter`, `local-image-build`, `thor`, `checkpoint`, `ABL`, `THIN_HOST`, `Layer 14`, `PKG_DEPENDS_TARGET`, `GitHub Actions dispatch`.
- **Knowledge bases scanned**: this repo has no `docs/solutions/` of its own. The relevant store is the sibling repo `/home/simonwjackson/code/sandbox/rocknix-nix-guest/docs/solutions/` (referenced by paths embedded inside this repo's `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`). Also scanned the four in-tree `base-*.md` planning files at repo root.
- **Files scanned**: 14 markdown files across `developer-experience/`, `best-practices/`, `runtime-errors/`, `performance-issues/` in `rocknix-nix-guest`, plus 4 in-repo base-* files and `NIX_EXPERIMENT.md`.
- **Relevant matches**: 5 strong, 2 adjacent.

## Critical Patterns

No `docs/solutions/patterns/critical-patterns.md` exists in either repo — section omitted by convention.

---

## Relevant Learnings

### 1. Custom-fork SM8550 deploy with ABL skip precheck (bricking-risk gate)
- **File**: `/home/simonwjackson/code/sandbox/rocknix-nix-guest/docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
- **Module**: ROCKNIX SM8550 custom-fork deployment
- **Problem Type**: `developer_experience`
- **Severity**: medium
- **Relevance**: Directly defines the Thor-validation procedure used after every custom-branch build, including the manual `/storage/.update/*.tar` override path (official `update.rocknix.org` rejects `BUILD_BRANCH=custom`). Any rebase plan that ends with "ship to Thor" must reuse this exact recipe and its ABL precheck.
- **Key insights**:
  - The only real bricking vector is `abl_a` / `abl_b` partition `dd`. Everything else (`/flash/SYSTEM`, `/flash/KERNEL`) is recoverable via SSH-from-recovery or fastboot.
  - **Always run the ABL skip precheck** before reboot. Compare the sha256 of `abl_signed-SM8550.elf` inside the build tarball against what's actually on `abl_a` / `abl_b`. For most fork updates this returns `MATCH (no flash)` because `rocknix-abl` is pinned to a versioned upstream tarball — but never assume.
  - Pre-flight gates: `≥ 2200 MB` free on `/storage`, `/storage/.update/` empty, both ABL partitions visible, battery state captured.
  - Hand-off canonical commands (sha256 verify, rsync `--inplace --partial` then scp fallback, reboot, `for i in $(seq 1 60); do ssh ... && break; done`).
  - Post-update validation for nix-integration builds: `nix-storage-setup.service`, `nix.mount`, `/proc/mounts` line, `998-nix-integration.conf` PATH order check.
  - **Documented hazard relevant to rebase**: stale `PKG_DEPENDS_TARGET` references in `projects/ROCKNIX/packages/virtual/image/package.mk`. Upstream removed `gnupg` on 2025-11-19; a downstream re-add silently broke `make image` only at the image-stage (after toolchain+aarch64 had finished). **Rebase guidance: audit `PKG_DEPENDS_TARGET` against upstream's current tree on every pull from upstream** — that's the canonical foot-gun. A small grep guard is sketched in the doc.

### 2. Fast-iter ROCKNIX builds — CI image-only + local cgroup-bounded
- **File**: `/home/simonwjackson/code/sandbox/rocknix-nix-guest/docs/solutions/developer-experience/fast-iter-and-local-rocknix-build-2026-05-08.md`
- **Module**: ROCKNIX build / CI (rocknix-fork-maintainers)
- **Problem Type**: `developer_experience` (front-matter uses `status: ready` / `audience:` instead — older shape; classification inferred)
- **Relevance**: Defines the two iteration paths after the rebase compiles. Critical for picking the right wall-clock budget when planning the post-rebase validation cycle.
- **Key insights**:
  - **Path A (`build-image-only.yml`)**: ~25–35 min. Downloads compiled artifacts from a previous successful full "Build" run on the branch and only re-runs the image step. Requires that the **purge-artifact job in `build-device.yml` skip feature branches** — only run on `main` / `next` / tags. Outputs are suffixed `-fastiter` (matches the two `target/ROCKNIX-update-SM8550-thin-host-20260511-fastiter` and `20260512-fastiter` dirs already present in this repo).
  - **CLEAN_NIX_INTEGRATION=true** (workflow input, default true) re-runs the `post_install` step when only `package.mk` / `system.d/*` changed — without it, stamp files in `.stamps/` short-circuit the install.
  - **Path B (`scripts/local-image-build`)**: rootless-podman + `systemd-run --user --scope` with cgroup v2 caps (CPUQuota 75%, MemoryHigh 75% of (Total−12%), `nice 19`, `ionice -c 3`). SSH-safe by design; first run ~3h cold, hot ccache ~30 min. Uses the repo's `./Dockerfile` (= what CI publishes as `ghcr.io/<owner>/rocknix-build:latest`) — **not** a nixpkgs FHS shell, because every tried nixpkgs gcc (13.4/14.3/15.2) breaks a different ROCKNIX host-phase package.
  - **Time budget rule of thumb**: a clean rebase that touches only `nix-integration` should cost ~30 min via Path A after the first full "Build" run; a rebase that touches toolchain / aarch64 / arm / emu / qt6 needs the full ~5h pipeline. The doc explicitly says: *first build on a new branch → run Path B (local) or one full CI build, then iterate via Path A.*
  - **When to use full "Build" workflow**: "big change spanning toolchain + nix-integration" — i.e. an upstream rebase that pulls in toolchain bumps cannot shortcut. Plan that into the wall-clock estimate.

### 3. Trigger fork's GitHub Actions build from NixOS dev host
- **File**: `/home/simonwjackson/code/sandbox/rocknix-nix-guest/docs/solutions/developer-experience/trigger-fork-rocknix-actions-build-from-nixos-2026-05-05.md`
- **Module**: ROCKNIX build system
- **Problem Type**: `developer_experience`
- **Severity**: medium
- **Relevance**: This dev host is NixOS; `make SM8550` cannot run (no FHS `/bin/bash`, missing perl::JSON, "unsupported distro nixos"). The rebase plan must lean on CI (and/or Path B podman) — never on direct `make`.
- **Key insights**:
  - Dispatch path: push the branch, then `POST /repos/<owner>/rocknix/actions/workflows/build-nightly.yml/dispatches` with `{"ref":"<BRANCH>","inputs":{"release":"false","SM8550":"true"}}`. Returns 204; grab run ID from the next `runs?branch=...&event=workflow_dispatch` listing.
  - Token already sits at `~/.config/gh/hosts.yml` (`oauth_token`).
  - Artifact name `ROCKNIX-update-SM8550-<DATE>` is the one to feed into Learning #1's deploy. API returns a ZIP wrapping the `.tar` + `.sha256`; `unzip` itself usually needs `nix shell nixpkgs#unzip`.
  - The default `vars.SCHEDULE_DEVICES` is `SM8550`, so a no-input dispatch also works — being explicit with `SM8550=true` is recommended.

### 4. Layer 14 main-space cold-boot autostart on AYN Thor (current branch context)
- **File**: `/home/simonwjackson/code/sandbox/rocknix-nix-guest/docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md`
- **Module**: ROCKNIX nix-integration (Layer 14 / thin-host / guest auto-promote)
- **Problem Type**: `best_practice` (frontmatter is loose — inferred)
- **Relevance**: The `custom` branch HEAD (`2cb7081c80 fix(nix-integration): avoid seq during guest promotion readiness`) and recent commits (`guest promote`, `THIN_HOST`, Layer 14 helpers) sit directly on top of the work this doc records. After the rebase, the cold-boot pipeline described here is the smoke test that determines whether Thor-Go was preserved.
- **Key insight (rebase-relevant only — read the doc fully when validating)**:
  - End-state contract Thor must reach after rebase + deploy: `rocknix-recovery-toggle.service`, `rocknix-graphical.target`, `rocknix-guest-v2.service` all `active`; journal shows `Started ROCKNIX Layer 14 sway kiosk session`; wayland socket at `/run/user/0/wayland-1` inside the guest.
  - Pipeline order: `rocknix-recovery-toggle` → `rocknix-graphical.target` → `rocknix-guest-v2.service` → `ExecStartPre=/usr/bin/rocknix-layer14-prep` (relinks guest `/init` to current system profile — "Bug 6 fix") → `rocknix-guest-udev-stage` → `systemd-nspawn ... --bind=/dev/tty0 --bind=/dev/tty1 --bind-ro=/run/.guest-udev:/run/udev`.
  - **Recent commit signal in `git log`**: 2cb7081c80 "avoid seq during guest promotion readiness", 9dd3c592be "repair drifted promoted guest profile", 5af42b75e4 "auto-promote packaged guest revisions" — these are the freshly-validated bits that a sloppy rebase could regress. Treat the guest promote unit and `rocknix-layer14-prep` as the highest-risk surface.
  - The two in-repo `base-*.md` files (`base-safety-review.md`, `base-scout-sm8550.md`) name explicit invariants the rebase must preserve: host SSH on :22 (`ConditionKernelCommandLine=|ssh` or `ConditionPathExists=|/storage/.cache/services/sshd.conf`), legacy `rocknix.target` still bootable for the two-knob recovery (`/flash/rocknix.no-nspawn` + `rocknix.safe=1`), and `rocknix-guest-v2.service` carrying **no** `--bind-ro=/usr|/lib|/etc/profile|/storage`. Static checks live at `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` — re-run after rebase.

### 5. Layer 10 stale guest running-state — never trust on-disk markers (adjacent)
- **File**: `/home/simonwjackson/code/sandbox/rocknix-nix-guest/docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
- **Module**: ROCKNIX nix-integration / `nixctl` / `nix-doctor`
- **Problem Type**: `runtime_error`
- **Severity**: medium
- **Relevance**: Adjacent. If a rebase shakes guest lifecycle metadata loose (likely after pulling upstream changes that affect units or scripts), the failure mode is silent-stale state, not loud crash. Worth re-running `nixctl guest status` and `nix-doctor --offline` after the post-rebase Thor smoke to confirm they observe live host evidence and not stamp files in `/storage/.config/nix-integration/layer10/state`.

---

## Recommendations

1. **Pre-rebase checkpoint hygiene on Thor.** Before starting the rebase, record (a) full `OS_VERSION` / `BUILD_BRANCH` / `BUILD_ID` from `/etc/os-release`, (b) the three `systemctl is-active` lines from Learning #4's end-state contract, (c) one run of `rocknix-guest-soak`, and (d) the sha256 of currently-flashed `abl_a` / `abl_b`. These become the "Thor-Go before rebase" baseline you compare against post-rebase.
2. **Audit `projects/ROCKNIX/packages/virtual/image/package.mk` `PKG_DEPENDS_TARGET` immediately after the rebase resolves**, before kicking any build (Learning #1's documented hazard). Cheap grep: every name in `PKG_DEPENDS_TARGET` must still have a `package.mk` with a matching `PKG_NAME=` somewhere in `packages/` or `projects/`.
3. **Re-run the static checks** (`projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`) before pushing the rebased branch. The `base-safety-review.md` invariants in this repo (host SSH stays, `rocknix.target` still bootable, guest unit has no host-leak binds) are the failure modes the static checks catch.
4. **Pick the build path by surface area** (Learning #2):
   - If the rebase only carries forward the existing `nix-integration` deltas → first run **one full CI build** to refresh stage artifacts on the rebased branch, then iterate via **Path A `build-image-only.yml` (fast-iter)** with `BASE_RUN_ID=<that run>` and `THIN_HOST=true`. Expect ~30 min per follow-up image.
   - If upstream pulled in toolchain / kernel / linux-firmware bumps → no fast-iter shortcut exists; budget a full ~5h pipeline.
   - If CI queues are long or the change is exploratory → Path B (`scripts/local-image-build --device=SM8550 --thin-host`) in rootless podman with cgroup caps. Use `--check` first.
5. **Dispatch from NixOS via REST API** (Learning #3) — do not attempt `make SM8550` on the dev host. The token in `~/.config/gh/hosts.yml` already works for the fork.
6. **Deploy to Thor exclusively via the documented `/storage/.update/*.tar` override path** (Learning #1). Mandatory steps: pre-flight, ABL skip precheck, sha256 verify host-side and device-side, snapshot pre-update `os-release`, reboot, wait-loop, post-update validate (the nix-integration-specific block).
7. **Post-deploy Layer 14 smoke** (Learning #4): the three `systemctl is-active` lines plus the kiosk-session journal line plus `/run/user/0/wayland-1` socket presence. Then run `rocknix-guest-soak` and confirm it stays green. Also re-run `nixctl guest status` and `nix-doctor --offline` to dodge Learning #5's stale-marker trap.
8. **If anything regresses on Thor, the recovery path is already wired**: `/flash/rocknix.no-nspawn` (sticky) or `rocknix.safe=1` on kernel cmdline routes `default.target` to legacy `rocknix.target`; nuclear option is `rm -rf /storage/.nix-root && reboot`. Both documented in `base-safety-review.md` and `NIX_EXPERIMENT.md`.

## Gaps / What Wasn't Found

No prior learning describes the **rebase mechanics themselves** — there is no documented playbook for "how to handle conflicts when pulling upstream `next` into `custom`", which files are routinely conflict-prone, or which upstream commits historically broke the fork's nix-integration deltas. The closest signal is Learning #1's `gnupg`-removal anecdote (a single data point). If this rebase produces a clean conflict pattern (likely files: `projects/ROCKNIX/packages/virtual/image/package.mk`, `projects/ROCKNIX/devices/SM8550/options`, `distributions/ROCKNIX/options`, the `.github/workflows/*.yml` set), capturing that pattern with `/se-compound` after the rebase lands would close a real gap.
