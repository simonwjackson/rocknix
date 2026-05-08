---
title: Fast-iter ROCKNIX builds (CI image-only + local cgroup-bounded)
date: 2026-05-08
slug: fast-iter-and-local-rocknix-build
status: ready
audience: rocknix-fork-maintainers
related-plans:
  - 2026-05-07-003-feat-rocknix-layer-14-thin-host-main-space-plan
  - 2026-05-04-002-feat-local-nix-build-shell-plan
---

# Fast-iter ROCKNIX builds

When iterating on `nix-integration/` (or any package with
`PKG_TOOLCHAIN="manual"` whose only effect is `post_install` at
image-build time), every full CI run rebuilds 4 hours 25 minutes
of toolchain / aarch64 / arm / emu / qt6 work that did not change.
The branch `feat/rocknix-layer-14-thin-host` triggered three full
builds in 12 hours over 2026-05-07 / 2026-05-08, each ~5 hours,
each producing the SAME compiled binaries — only the
`nix-integration/install_pkg/` tree differed.

Two complementary tools cut this:

1. **`build-image-only.yml`** — fast-iter CI workflow that downloads
   compiled artifacts from a previous successful "Build" run and
   only re-runs the image step. **~30 min** instead of ~5 hours.
2. **`scripts/local-image-build`** — local build wrapper with strict
   cgroup v2 caps so the SSH session and host stay responsive
   throughout. Use when offline, when CI queues are long, or when
   you want full control over the iteration loop.

Both are SSH-safe by design: never lock up the host, never starve
the user shell, never page the kernel into swap death. They are
**additive** — they do not replace the full pipeline. The full
pipeline still runs on `main` / `next` / tags and on any
`workflow_dispatch` to "Build".

## Path A — fast-iter CI (`build-image-only.yml`)

### Pre-requisite: artifact retention on feature branches

`build-device.yml`'s artifact-cleanup job historically deleted
`arm (DEVICE)`, `emu-libretro (DEVICE)`, etc. at the end of every
successful run. We narrowed that to only run on `main` / `next` /
tags. Feature-branch runs now leave the per-stage artifacts
behind:

```yaml
# build-device.yml -> purge-artifact job
if: >-
  ${{ always() && !cancelled() && !contains(needs.*.result, 'failure')
      && (github.ref_name == 'main' || github.ref_name == 'next'
          || startsWith(github.ref, 'refs/tags/')) }}
```

This costs storage on long-lived feature branches but unlocks the
fast-iter loop. Storage cost is bounded by GitHub's default
artifact retention (90 days).

### Use it

1. Find the most recent successful "Build" run on your branch:

   ```text
   gh run list --branch <BRANCH> --workflow Build \
     --status success --limit 5
   ```

   Note the run ID (e.g. `25541232603`).

2. Trigger the fast-iter workflow:

   ```text
   gh workflow run "Build image only (fast-iter)" \
     --repo <owner>/rocknix \
     --ref <BRANCH> \
     -f BASE_RUN_ID=25541232603 \
     -f DEVICE=SM8550 \
     -f THIN_HOST=true
   ```

3. Total wall: ~25-35 min:
   - Maximize disk + checkout: ~3 min
   - Download artifacts (6-8 GB): ~5 min
   - Clean nix-integration: 1 min
   - `scripts/build_distro` (no recompile, only install + image): ~20-25 min
   - Upload artifacts: ~2 min

### Forced post_install re-run

`scripts/build_distro` checkpoints package install via stamp files
under `.stamps/`. To make `nix-integration/package.mk`'s
`post_install` actually re-run when only `package.mk` changed,
the workflow has a `CLEAN_NIX_INTEGRATION` input (default `true`)
that runs `./scripts/clean nix-integration` before the build.

### Output

Artifacts are suffixed with `-fastiter` so they don't collide with
the full pipeline's outputs:

```text
ROCKNIX-image-SM8550-thin-host-DATE-fastiter
ROCKNIX-update-SM8550-thin-host-DATE-fastiter
```

## Path B — local build (`scripts/local-image-build`)

### SSH-safety contract

This wrapper is the canonical way to build ROCKNIX images on the
maintainer workstation while an SSH session is connected. It
applies cgroup v2 caps + nice/ionice that GUARANTEE the SSH
session stays responsive:

| Resource | Default cap (auto-resolved) | Why |
|---|---|---|
| `CPUQuota` | 75% of total threads (max 12 of 16) | Reserve 25% for SSH/kernel/agent |
| `CPUWeight` | 50 (default 100) | When system is busy, host wins |
| `MemoryHigh` | 75% of (Total - 12% reserve) | Kernel throttles before OOM |
| `MemoryMax` | Total - 12% (min 4 GB reserved) | Hard kill before swap death |
| `IOWeight` | 50 (default 100) | NVMe stays responsive |
| `nice` | 19 (lowest CPU priority) | SSH preempts instantly |
| `ionice` | class=3 (idle) | Build only gets disk when nothing else needs it |

The defaults are computed at runtime from the host's actual
resources — on a 16-thread / 32 GB host the build sees 12 threads
and ~28 GB; on an 8-thread / 16 GB host it sees 6 threads and
~14 GB. No hardcoded numbers.

### Use it

```text
# 1. Inspect what would happen (does NOT start the build):
scripts/local-image-build --check
scripts/local-image-build --check --thin-host

# 2. Run in foreground (Ctrl+C cleanly stops the cgroup):
scripts/local-image-build --device=SM8550 --thin-host

# 3. Run in background, log to ~/.cache/rocknix-local-build/:
scripts/local-image-build --device=SM8550 --thin-host --background

# 4. Check the running build's resource state:
scripts/local-image-build --status

# 5. Abort the running build (clean cgroup teardown):
scripts/local-image-build --abort

# 6. Override caps for very large or constrained hosts:
scripts/local-image-build --cpu-percent=600 --memory-max=12G
```

### Implementation

The wrapper does not invoke `make image` directly — it goes through
two layers:

```text
scripts/local-image-build
  -> systemd-run --user --scope --collect
       --property=CPUQuota=...
       --property=CPUWeight=50
       --property=MemoryHigh=...
       --property=MemoryMax=...
       --property=IOWeight=50
       --setenv=PROJECT=ROCKNIX
       --setenv=DEVICE=...
       --setenv=THIN_HOST=...
     -- rocknix-env -c "nice -n 19 ionice -c 3 make image"
```

`rocknix-env` is the FHS sandbox shell exposed by this repo's
`flake.nix`. It provides `/usr/include` etc. for ROCKNIX's
`scripts/checkdeps`. No docker / podman is needed.

`Nice=` and `IOSchedulingClass=` are NOT accepted as `systemd-run
--user` properties (PolicyKit blocks them in user mode). We get
the same effect by wrapping the inner command with `nice -n 19`
and `ionice -c 3`, which the kernel honors in cgroup v2 just as
well as the systemd properties.

### Disk + memory pre-flight

The wrapper refuses to start unless:

- ≥ 30 GB free on the cwd's filesystem
- ≥ 4 GB available memory (`MemAvailable`)
- The user slice has `memory` and `cpu` controllers delegated

If `MemAvailable` is below 4 GB it warns rather than aborts —
the cgroup MemoryHigh will still throttle the build cleanly.

### Output

Same as the CI image step:

```text
target/ROCKNIX-SM8550.aarch64-DATE.tar          (live update tarball)
target/ROCKNIX-SM8550.aarch64-DATE.tar.sha256
target/ROCKNIX-SM8550.aarch64-DATE.img.gz       (full flashable)
target/ROCKNIX-SM8550.aarch64-DATE.img.gz.sha256
```

`scp` the `.tar` directly to Thor's `/storage/.update/` — no GitHub
round-trip required.

## When to use which

| Situation | Path |
|---|---|
| Iterating on `nix-integration/package.mk` from any branch | A (fast-iter CI) |
| First build on a branch (no base run yet) | B (local) — or one full CI build then A from then on |
| Offline / on a plane / CI queue is busy | B (local) |
| Need to compare reproducibility against CI | A (forces use of CI's docker container) |
| Small one-line tweak to `system.d/*.service` | B (local) — turnaround in 25 min on hot ccache |
| Big change spanning toolchain + nix-integration | Full "Build" workflow (no shortcut available) |

## Time budget reality check

Run history from 2026-05-07 / 2026-05-08:

| Build | Path | Wall | Outcome |
|---|---|---|---|
| #1 (25541232603) | Full CI | 4h57m | initial scaffold |
| #2 (25559056951) | Full CI | ~5h    | contract-fix verification |
| #3 (25559498323) | Full CI | ~5h    | first THIN_HOST=yes |
| projected #4 | Fast-iter A | ~30m | next iteration |
| projected #5 | Local B | ~30m hot / ~3h cold | parallel iteration |

Total CI wall saved per future iteration: **~4h 30m**.

## See also

- Plan: `docs/plans/2026-05-07-003-feat-rocknix-layer-14-thin-host-main-space-plan.md`
- Brief on local build setup: `docs/plans/2026-05-04-002-feat-local-nix-build-shell-plan.md`
- Trigger fork actions builds doc:
  `docs/solutions/developer-experience/trigger-fork-rocknix-actions-build-from-nixos-2026-05-05.md`
