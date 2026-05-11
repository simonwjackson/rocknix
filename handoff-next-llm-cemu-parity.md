# Handoff Prompt for New LLM: ROCKNIX Layer 14 Cemu Host-Parity Work

You are in repo:

```sh
cd /home/simonwjackson/code/sandbox/rocknix
```

Current branch:

```text
feat/rocknix-layer-14-thin-host
```

User wants to continue work on getting Layer 14/Nix Cemu as close as possible to host ROCKNIX Cemu parity, then simplifying the accumulated diagnostic complexity. Stay on this branch. Make atomic commits. Use Fuji for heavy aarch64 Nix builds. Thor/device is currently offline unless user says otherwise.

## Important safety constraints

- Do not mutate ROCKNIX host SSH/root state except explicit validation/deploy actions.
- ROCKNIX host remains recovery plane.
- Avoid `/usr`, `/flash`, `/boot`, host `/etc` mutation.
- Do not broad-bind `/storage/.cache`.
- Do not mix host/Nix Vulkan loaders via `LD_PRELOAD`.
- Use exact process cleanup (`pgrep -x`) only.
- Trust live user-visible MangoHud FPS over title/headless-only results.
- ROCKNIX Mesa passthrough is diagnostic only, not product path.
- Successful fixed Cemu path uses native Nix Mesa/Freedreno + package-recorded Nix Vulkan loader path.

## Where to read context first

1. Plan:
   - `docs/plans/2026-05-10-003-fix-cemu-host-parity-simplification-plan.md`
2. Audit/history:
   - `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
3. Launcher docs:
   - `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
4. Core scripts:
   - `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest.sh`
   - `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-promote.sh`
   - `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-live-campaign.sh`
   - `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh`
   - `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-cleanup.sh`
5. Static checks:
   - `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
6. Direct Cemu package:
   - `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-package.nix`
   - `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-package-manifest.nix`

## Recent commits already made

```text
c67e77f477 docs(rocknix): document cemu parity gate
6506c583e5 feat(rocknix): add cemu parity promotion harness
4401f2866c docs(rocknix): plan cemu parity simplification
```

Key changes in these commits:

- Wrote the new follow-up plan.
- Added typed live campaign cases:
  - `guest:<label>:<cemu-bin>`
  - `host:<label>:<host-launcher>:<profile>`
- Indexed live-campaign child run dirs (`001-...`, `002-...`) so A/B/A repeats do not overwrite evidence.
- Added host-control launcher contract via `RUNNER_HOST_LAUNCHER`.
- Added host-side process/env/maps/log evidence capture.
- Hardened cleanup: `remote-cemu-cleanup.sh` exits non-zero if exact-name emulator processes survive unless `CLEANUP_ALLOW_STALE=1`.
- Added `remote-cemu-promote.sh`, which promotes an already-imported direct Cemu output into:
  - `/nix/var/nix/profiles/per-user/root/cemu-promoted/bin/Cemu`
- Changed `start_cemu_guest.sh` default to the promoted profile while preserving `CEMU_BIN` override.
- `start_cemu_guest.sh` now resolves symlinks with `readlink -f` before reading direct-package metadata, so `vulkan-loader-lib-path` still comes from the real store output.
- Updated static checks and docs/audit.

Verified after commits:

```sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh
sh -n projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/*.sh
git diff --check
```

## Current Cemu build state

Fuji is reachable and should be used for aarch64 Nix builds.

Already built/realized on Fuji:

```text
/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package
```

Binary:

```text
/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu
```

Closure info from Fuji:

```text
582 paths
~2.6 GB closure
```

The build was done by copying the flake to Fuji and running:

```sh
rsync -a --delete projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/ fuji:/tmp/rocknix-cemu-flake/
ssh fuji 'cd /tmp/rocknix-cemu-flake && nix build --no-write-lock-file --print-out-paths --no-link .#packages.aarch64-linux.cemu-rocknix-package'
```

It resolved to the same already-known good store path.

## Current validation state

Thor is offline. Do not try device operations until user says it is online.

Known successful fixed direct-package run from prior session:

- Run report:
  - `/storage/.guest/runs/20260510-094138-cemu-live-package-vulkanfix/report.md`
- Candidate:
  - `/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu`
- Runtime:
  - Native Nix Mesa/Freedreno
  - `Driver version: Mesa 25.2.6`
  - `Init Vulkan graphics backend`
  - BOTW profile path present: `gameProfiles/default/00050000101c9400.ini`
  - RPL link time ~153ms
  - HLE scan time ~145ms
- Live result:
  - User-corrected visible FPS ~40 FPS
  - MangoHud avg `38.11`, median `38.34`, p10 `35.77`
- Correction artifact:
  - `/storage/.guest/runs/20260510-094138-cemu-live-package-vulkanfix/rocknix-package-vulkanfix-guest-gamescope-mangohud-720p-45/operator-correction.txt`

Earlier invalid direct-package live run fell back to OpenGL due `Vulkan loader not available`; ignore its FPS for parity decisions.

Historical host-good run:

- `/storage/.guest/runs/20260509-234946-host-cemu-direct-540p45-botw`
- Host `/usr/bin/cemu`
- ~45 FPS

But final same-session host-control vs fixed direct Nix Cemu has **not** been run yet. That is the next proof gate once Thor is online.

## Next steps when Thor is online

1. Import/copy Fuji-built closure into Thor guest store if not already present:
   - Source on Fuji:
     - `/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package`
   - Use real Nix store tooling; do not just copy random files.
2. Run fingerprint:

```sh
CANDIDATE_CEMU=/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu \
  /storage/.guest/remote-cemu-build-fingerprint.sh
```

3. Promote candidate in guest if parity gate passes, using:

```sh
/storage/.guest/remote-cemu-promote.sh \
  /nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu
```

4. Run same-session typed live campaign. Shape should be A/B/A or B/A/B, using host-control and guest direct package. Example (host launcher path may need to be created/proven first):

```sh
CAMPAIGN_CASES="host:host-control:/storage/.guest/launch-host-cemu-through-guest-display.sh:720p-45
guest:rocknix-package:/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu
host:host-control-repeat:/storage/.guest/launch-host-cemu-through-guest-display.sh:720p-45" \
  /storage/.guest/remote-cemu-live-campaign.sh
```

Host-control launcher contract:

- Must run host `/usr/bin/cemu` through the same guest-visible display path.
- Must accept env:
  - `RUN_DIR`
  - `PROFILE`
  - `VARIANT`
  - `CEMU_ROM`
  - `MANGOHUD_CONFIGFILE`
  - `XDG_RUNTIME_DIR`
  - `WAYLAND_DISPLAY`
- Must write comparable host-side Cemu/MangoHud/log evidence into `RUN_DIR`.
- If this contract cannot be proven, mark host-control inconclusive; do not claim parity.

5. Promotion threshold from plan:

- Candidate median within 10% of same-session host.
- Candidate p10 within 15% of same-session host.
- No visible loading regression.
- Runtime evidence proves Vulkan + BOTW gameprofile + expected direct package.

6. If native Nix Mesa candidate misses parity, run diagnostic ROCKNIX Mesa passthrough only to classify the delta. Do not productize it without a separate graphics-stack decision/plan.

## Current git status caveat

There are pre-existing untracked files not related to the latest work, including older plan docs and scratch artifacts. Do not blindly `git add .`. Stage only files relevant to your current logical unit.

At handoff time the latest committed work tree had no tracked diffs after the three commits above, but untracked files remained.

## If asked whether more compiling can be done

For current direct Cemu candidate, useful compile work is already done on Fuji. Full ROCKNIX image build could be done, but it is probably overkill unless user explicitly wants a flashable image. The launcher/harness changes are scripts/docs/static checks and do not require compilation.
