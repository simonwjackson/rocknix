---
status: active
created: 2026-05-09
origin: chat
scope: rocknix-layer14-cemu-performance
---

# Fix Layer 14 Cemu Performance Without Physical Device Access

## Problem frame

Layer 14 Nix guest Cemu runs BOTW, but it no longer matches the known-good ROCKNIX host experience:

- `potato-30` feels choppy and MangoHud reports ~3–15 FPS in game.
- Loading times are much slower than remembered from the host and from earlier guest experiments.
- Max CPU/GPU governors alone do not fix the issue.
- Direct hot-swapping ROCKNIX host Mesa under the Nix Cemu process failed because the Vulkan loader/driver stack became incoherent.

The goal is to restore host-like Cemu performance from the Nix guest **without requiring physical access to Thor** and without compromising ROCKNIX as the host/recovery plane.

## Progress update — 2026-05-09 remote run

- U1 remote cleanup/runner harness is implemented and deployed to Thor.
- Broad `pgrep -f` cleanup was fixed after it matched the nspawn bind list; cleanup now uses exact process names only.
- Guest sway startup is repaired by the runner when the kiosk service is missing an IPC socket.
- Controlled guest runs show BOTW reaches in-game unattended and often reports ~25-30 FPS after load.
- MangoHud CSV shows the remaining issue is severe hitches during/after load, not a sustained 3-15 FPS steady state under the controlled harness.
- Nix Mesa 26.0.2 is visible to `vulkaninfo` but fails Cemu with `failed to submit command buffer. Error -4`.
- ROCKNIX Mesa 26.0.6 with the Nix Vulkan loader and narrow host dependency shim is stable for diagnostics and avoids the previous two-loader crash, but does not materially improve the hitch pattern.
- Host control cannot run unchanged in thin-host mode because host Wayland is gone (`Failed to connect to wayland socket: wayland-1`). A host-control A/B now needs a dedicated thin-host-compatible harness.
- Detailed audit: `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`.

## Progress update — build-parity instrumentation

Follow-up plan `docs/plans/2026-05-09-003-fix-layer14-cemu-build-parity-plan.md` narrows the next investigation from generic Mesa/runtime swapping to Cemu build parity. The repo now contains:

- `remote-cemu-build-fingerprint.sh` for host/current-guest/candidate Cemu build/runtime comparison.
- `cemu-rocknix-style` flake output for a guest-native candidate that mirrors ROCKNIX `cemu-sa` build flags more closely.
- `start_cemu_guest_candidate.sh` and `CEMU_BIN` support in `start_cemu_guest.sh` so candidate binaries can be tested without rewriting the stable launcher.
- `remote-cemu-runtime-ab.sh` for current-vs-candidate runs and live in-game checkpoint sampling.

This does not replace the older coherent-Mesa runtime idea; it tests the more immediate hypothesis that Cemu build semantics, not raw GPU/display throughput, explain the remaining live BOTW gap.

## Current evidence

### Confirmed good host stack characteristics

Host ROCKNIX Vulkan stack:

- Mesa/Turnip: `Mesa 26.0.6`
- Vulkan loader: `1.4.347`
- GPU: `Turnip Adreno (TM) 740`
- Host BOTW potato pipeline:
  - Cemu internal resolution: `640x360`
  - gamescope output: `640x360 -> 1920x1080`
  - FSR: enabled
  - MangoHud: host Vulkan layer
  - launcher: `/storage/bin/botw-potato-30.sh`

### Confirmed guest stack characteristics

Guest Nix Cemu currently uses:

- Mesa/Turnip: `Mesa 25.2.6`
- Vulkan loader: `1.4.341`
- Direct Cemu fullscreen to sway in the standard guest launcher.
- Nix MangoHud is installed and works as a Vulkan overlay.
- Nix gamescope is installed and starts, but earlier nested gamescope tests need a controlled A/B rerun.

### Important failed experiments

1. **Broad `/storage/.cache` bind was wrong**
   - It mixed host Mesa cache and guest Mesa cache.
   - Reverted.
   - Guest cache is local again.

2. **Host Mesa ICD only was insufficient**
   - Nix Vulkan loader with host ICD lost required extensions:
     - `VK_KHR_surface`
     - `VK_KHR_wayland_surface`

3. **Host loader + host Mesa can work in `vulkaninfo` only when coherent**
   - Narrow host dep shim plus host loader reports Mesa 26.0.6 correctly.
   - But Nix Cemu still crashes because it already links Nix Vulkan loader and preloading host loader creates a two-loader process.

4. **CPU/GPU governor confusion was real but not sufficient**
   - `botw-guest.sh potato-30` downcaps CPU after host-side max tuning.
   - Raising ceilings after launch improves some cases but does not restore host-like smoothness.
   - Full max governors heat CPU7 to ~90–94C, likely power/thermal limiting.

5. **Save path case mismatch existed**
   - Actual save dir: `101c9400`
   - Cemu expected: `101C9400`
   - Compatibility symlink was added on-device.

## Scope

### In scope

- Remote-only diagnosis and implementation over SSH.
- Reproducible remote benchmarking using logs, MangoHud CSVs, screenshots, and Cemu title FPS.
- Nix-native packaging of the coherent Cemu runtime stack.
- Matching the host pipeline shape: Cemu + gamescope 360p/540p FSR + MangoHud.
- Persisting final launcher/profile changes in the repo.

### Out of scope

- Requiring the user to tap/click/observe the device physically.
- Breaking host SSH on `root@thor:22`.
- Using host `/usr/bin/cemu` as the product solution.
- Blanket binding host `/usr` or full `/storage` into the guest.
- Keeping temporary host-Mesa LD_PRELOAD hacks as a product path.

## Success criteria

Remote validation must show:

1. Host control still performs as expected on the current image.
2. Guest candidate reaches in-game without user input.
3. Guest candidate uses a coherent Vulkan stack, with no mixed host/Nix Vulkan loaders.
4. MangoHud CSV shows for `potato-30`:
   - median FPS near 30 in the same scene,
   - no sustained ~3–15 FPS failure mode,
   - frame pacing materially closer to host control.
5. Load time is within an acceptable range of host control for the same launch path.
6. SSH remains available throughout; any display failure is recoverable by SSH reboot/service restart.

## Implementation units

### U1 — Remote safety and cleanup harness

**Purpose:** Make remote experiments safe before doing more graphics-stack work.

**Files to add/update:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-cleanup.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh`

**Plan:**

- Add a cleanup script that kills only exact Cemu/gamescope processes, not the shell invoking it.
- Restore clean launch scripts before every run:
  - no stale host MangoHud wrappers,
  - no host Mesa LD_PRELOAD wrapper unless explicitly testing it,
  - no broad `/storage/.cache` bind.
- Capture pre/post state:
  - `systemctl status rocknix-guest-v2.service`,
  - current CPU/GPU governors,
  - Cemu log,
  - stdout log,
  - journal excerpt,
  - screenshot with `grim`.
- Add a watchdog mode: if Cemu/gamescope is still on `Loading...` after a timeout, collect logs and kill it.

**Test scenarios:**

- Run cleanup when no Cemu is active: exits 0 and keeps SSH alive.
- Run cleanup while Cemu/gamescope are active: removes only those processes.
- Run runner with a deliberately invalid command: logs failure and restores guest service.

### U2 — Remote performance characterization matrix

**Purpose:** Establish hard evidence for host vs guest instead of relying on perceived smoothness.

**Files to add/update:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/remote-cemu-runner.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/mangohud-botw.conf`
- `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`

**Plan:**

Run the same remote test envelope for each variant:

1. **Host control**
   - `/storage/bin/botw-potato-30.sh`
   - Host Cemu + host Mesa 26 + host gamescope + host MangoHud.

2. **Guest baseline**
   - Nix Cemu + Nix Mesa 25.2.6 + direct fullscreen.

3. **Guest Nix gamescope**
   - Nix Cemu + Nix Mesa 25.2.6 + Nix gamescope 640x360 -> 1080p FSR.

4. **Guest Nix MangoHud on/off**
   - Same as variants 2 and 3 with/without MangoHud to measure overlay overhead.

5. **Host-Mesa hot-swap record**
   - Keep as negative evidence only; do not productize.

Metrics to collect:

- Time from launch to first `FPS:` title.
- Time from launch to in-game stable FPS.
- MangoHud CSV: average FPS, 1% low, frametime spikes.
- `Cemu share/log.txt`: driver version, shader/cache messages, errors.
- Thermal snapshots before/after.
- Screenshot from DSI-2.

**Test scenarios:**

- Each variant produces a run directory under `/storage/.guest/runs/<timestamp>-<variant>/`.
- A failed launch still produces logs and a clear status file.
- Host control and guest variants use the same BOTW profile/settings mutation.

### U3 — Build a coherent ROCKNIX-aligned Cemu Vulkan runtime

**Purpose:** Avoid the failed mixed-loader approach by making the Cemu runtime internally consistent.

**Files to add/update:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/flake.nix`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest.sh`

**Plan:**

Preferred path:

- Build Cemu against a Nix-provided Mesa/Vulkan stack that matches ROCKNIX host as closely as possible:
  - Mesa 26.0.6,
  - Vulkan loader 1.4.347 or compatible,
  - libdrm/wayland/gbm versions aligned enough to avoid loader/ICD mismatch.

Fallback path:

- Package the ROCKNIX Mesa artifacts as a coherent Nix runtime component, not as ad-hoc `/host/lib` preloads.
- Ensure only one Vulkan loader is present in the Cemu process.
- Disable conflicting implicit layers when needed.

Do not repeat the failed pattern:

- Nix Cemu linked to Nix `libvulkan.so` plus host `LD_PRELOAD=/host/lib/libvulkan.so.1`.

**Test scenarios:**

- `vulkaninfo --summary` inside the guest reports Mesa 26.0.6 using the candidate runtime.
- Cemu starts and logs `Driver version: Mesa 26.0.6` without segfault.
- Process maps show only one Vulkan loader family.
- BOTW reaches in-game under the candidate runtime.

### U4 — Restore host-equivalent gamescope pipeline inside the guest

**Purpose:** Match the host performance pipeline instead of relying on direct Cemu fullscreen.

**Files to add/update:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest_gamescope.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/botw-guest.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`

**Plan:**

- Add explicit launch modes:
  - `direct`
  - `gamescope-fsr`
  - `gamescope-linear`
- For `potato-30`, match host exactly:
  - `gamescope --backend sdl -f --force-windows-fullscreen -W 1920 -H 1080 -w 640 -h 360 -r 60 -S fit -F fsr --sharpness 5 -- ...`
- Keep gamescope logs in each run directory.
- Treat gamescope XKB/PipeWire warnings as nonfatal unless the process exits.

**Test scenarios:**

- `potato-30 gamescope-fsr` starts gamescope and Cemu remotely.
- Cemu log still uses the intended Mesa runtime.
- MangoHud overlay or CSV works through gamescope.
- A gamescope failure returns to guest sway and leaves SSH intact.

### U5 — Make MangoHud a first-class guest dependency

**Purpose:** Keep frametime/FPS proof available without host-layer hacks.

**Files to add/update:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/dev-env.nix`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/main-space.nix`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/mangohud-botw.conf`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/start_cemu_guest_mangohud.sh`

**Plan:**

- Add `pkgs.mangohud` to the relevant guest profile.
- Add a stable MangoHud config with:
  - FPS,
  - frametime graph,
  - CPU/GPU stats,
  - CSV logging for unattended runs.
- Keep interactive overlay optional; always write CSV for remote validation.

**Test scenarios:**

- Guest profile contains `mangohud` after rebuild.
- Launch with MangoHud writes a CSV/log file under `/storage/.guest/runs/...`.
- Launch without MangoHud has no `LD_PRELOAD=libMangoHud_shim.so`.

### U6 — Persist remote-safe launch profiles

**Purpose:** Convert the winning runtime into durable launch scripts.

**Files to add/update:**

- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/botw-guest.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/host-tune.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/dev-env.nix`

**Plan:**

- Update `botw-guest.sh` so CPU/GPU tuning does not fight explicit host-side overrides.
- Add a `--power-mode` or environment override:
  - `cool`,
  - `balanced`,
  - `max`,
  - `no-tune`.
- Stop having the guest script silently downcap CPU after host-side tuning when running diagnostics.
- Keep menu autostart disabled until touch/menu behavior is explicitly revalidated.

**Test scenarios:**

- `botw-guest.sh potato-30` defaults to safe/cool profile.
- `BOTW_POWER_MODE=max botw-guest.sh potato-30` does not downcap CPU/GPU.
- `BOTW_RENDER_PIPELINE=gamescope-fsr botw-guest.sh potato-30` uses gamescope.
- Existing direct mode still works.

### U7 — Document the root cause and final decision

**Purpose:** Prevent repeating the same false starts.

**Files to add/update:**

- `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/README.md`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/README.md`

**Plan:**

Capture:

- Why direct fullscreen diverged from host performance.
- Why broad cache binding is unsafe across Mesa versions.
- Why host Mesa hot-swap via `LD_PRELOAD` crashes.
- Which coherent runtime won.
- Exact remote commands to reproduce benchmark runs.

**Test scenarios:**

- Documentation includes the negative findings and final accepted runtime.
- Future launchers point to the documented flow.

## Remote execution order

1. U1: install cleanup/runner harness on Thor and in repo.
2. U2: run characterization matrix; do not change packages yet.
3. U3: build coherent Mesa/Cemu runtime candidate.
4. U4: add gamescope FSR launch mode and test with the candidate runtime.
5. U5: integrate MangoHud as a guest package and CSV logger.
6. U6: persist the winning profile and remove diagnostic wrappers.
7. U7: document findings and commit.

## Safety rules for unattended work

- Do not disable or restart host SSH.
- Do not touch host port 22.
- Do not bind full host `/storage` into the guest.
- Do not leave host `/usr` as the app runtime solution.
- Do not leave broad `/storage/.cache` bind active.
- Do not toggle Cemu fullscreen state live through sway; relaunch instead.
- Every experiment must have a timeout and cleanup path.
- Every experiment must collect logs before cleanup.
- If Thor becomes unreachable, wait and retry before assuming failure; use reboot only when SSH is available.

## Open technical questions

1. Can nixpkgs provide Mesa 26.0.6 / Vulkan loader 1.4.347 for aarch64 without custom packaging?
2. Does Nix gamescope + Nix Mesa 25 already fix performance if launched in the exact host pipeline shape?
3. Is ROCKNIX Mesa 26 specifically required, or is any coherent Mesa 26 stack enough?
4. Does MangoHud materially affect the slow path, or is it only observing it?
5. Does host Cemu still perform well on this new image and current thermal state?
