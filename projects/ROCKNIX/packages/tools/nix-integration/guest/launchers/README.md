# Layer 14 guest launchers

Shell scripts that run inside the Layer 14 Nix guest (systemd-nspawn).
They invoke nix-built emulators with proper env, settings.xml mutation,
and CPU/GPU governor tuning -- without falling back to host binaries
or host Cemu binaries.

## Files

| Script | Role |
|---|---|
| `start_cemu_guest.sh` | Thin compatibility launcher. Selects promoted/override Cemu, normalizes real-binary overrides back to package-owned `bin/cemu` when available, requires guest-session env, delegates user-data layout to `cemu-storage-adapter.sh`, then execs Cemu fullscreen with the requested ROM. |
| `cemu-storage-adapter.sh` | Guest-owned `/storage` compatibility adapter. Idempotently preserves existing Cemu settings/saves/keys/MLC layout under XDG paths and `/storage/roms/bios/cemu`; never part of the generic package wrapper. |
| `cemu-sm8550-performance.sh` | Guest/session-owned SM8550 Cemu performance profile. Applies measured CPU caps, best-effort GPU devfreq policy, and Cemu thread affinity; generic package wrapper never owns this device policy. |
| `start_cemu_guest_mangohud.sh` | Nix MangoHud wrapper around `start_cemu_guest.sh`. Diagnostic/profile mode only. |
| `start_cemu_guest_gamescope.sh` | Nix gamescope wrapper matching the host 360p/540p -> 1080p FSR pipeline shape. Diagnostic/profile mode until validated. |
| `start_cemu_guest_rocknixmesa.sh` | Diagnostic-only launcher using the ROCKNIX Mesa ICD with a narrow dependency shim while keeping Cemu's Nix Vulkan loader. Do not productize as the final Nix runtime. |
| `start_cemu_guest_candidate.sh` | Diagnostic wrapper that runs a caller-selected guest-native Cemu binary via `CEMU_BIN` while preserving the normal guest config/cache setup. |
| `botw-guest.sh <profile>` | Parametric BOTW launcher. One profile per resolution / FPS combo. Mutates `settings.xml` via guest-available Perl, tunes CPU/GPU sysfs, calls `start_cemu_guest.sh`, then blocks until cemu exits. Replaces all 11 host `/storage/bin/botw-*.sh` scripts. |
| `games-launcher.sh` | Touch-friendly fuzzel menu pinned to DSI-1 (Thor's bottom panel). Kept available, but not autostarted while touch/menu behavior is under validation. |
| `host-tune.sh` | Temporary host-side sysfs tuning helper. Runs on ROCKNIX host only for privileged controls the guest cannot safely own yet, especially GPU devfreq. |
| `remote-cemu-cleanup.sh` | Host-side cleanup script for unattended Cemu/gamescope experiments. Kills exact process names and closes stale guest Sway Cemu windows. |
| `remote-cemu-runner.sh` | Host-side benchmark harness. Creates `/storage/.guest/runs/<timestamp>-<variant>-<profile>/` with logs, title samples, screenshot, governor/thermal/process state. Supports `RUNNER_CEMU_START` for guest candidates and `RUNNER_HOST_LAUNCHER` for typed host-control cases. |
| `remote-cemu-single-run-validation.sh` | Host-side one-command orchestrator. Runs a compact headless benchmark matrix, analyzes MangoHud CSVs, writes a parent `report.md`, and restores safe state. |
| `remote-cemu-build-fingerprint.sh` | Host-side build/runtime fingerprint report for ROCKNIX host Cemu, current guest Nix Cemu, and an optional candidate Cemu. |
| `remote-cemu-runtime-ab.sh` | Host-side current-vs-candidate Cemu A/B harness, including a live checkpoint mode for in-game sampling. |
| `remote-cemu-live-campaign.sh` | Host-side one-session live campaign. Runs typed guest and host-control cases sequentially, waits for in-game checkpoint notes, captures maps/thread/cache/CSV evidence, then cleans up and restores power state. Child run directories are indexed so A/B/A repeats do not overwrite evidence. |
| `remote-cemu-promote.sh` | Host-side promotion helper. Installs an already-imported `nix-sm8550` Cemu output into `/nix/var/nix/profiles/per-user/root/cemu-promoted` inside the guest as a stable GC-rooted rollback path. |
| `launch-host-cemu-through-guest-display.sh` | Diagnostic host-control launcher. Runs host `/usr/bin/cemu` through the guest-visible display path for same-session parity checks. |

## BOTW profiles

| Profile | Resolution | FPS | Cluster caps (P3/P7 kHz) | GPU governor |
|---|---|---|---|---|
| `potato-30`  | 640x360   | 30 | 1401600 / 1478400 | simple_ondemand 220-475 MHz |
| `540p-30`    | 960x540   | 30 | 1401600 / 1478400 | simple_ondemand 220-550 MHz |
| `540p-45`    | 960x540   | 45 | 2803200 / 2956800 | simple_ondemand 680-680 MHz |
| `720p-30`    | 1280x720  | 30 | 1401600 / 1478400 | simple_ondemand 220-615 MHz |
| `720p-45`    | 1280x720  | 45 | 2803200 / 2956800 | simple_ondemand 680-680 MHz |
| `900p-30`    | 1600x900  | 30 | 1401600 / 1478400 | simple_ondemand 220-680 MHz |
| `native-30`  | 1920x1080 | 30 | 1401600 / 1478400 | simple_ondemand 220-680 MHz |

The host script aliases (`botw-fast.sh`, `botw-fsr.sh`, `botw-balanced-fast.sh`, `botw-540p-fsr.sh`, etc.) all collapse into one of the profiles above.

## Differences from `/storage/bin/botw-*.sh`

The host scripts rely on:

- **gamescope** for FSR upscaling.
  Direct fullscreen was initially used to avoid an early nested-gamescope crash, but performance work showed this does not match the host pipeline. `start_cemu_guest_gamescope.sh` restores the host-shaped 640x360/960x540 -> 1080p FSR path for controlled A/B testing.
- **mangohud** for HUD overlay.
  `pkgs.mangohud` is available on aarch64 and `start_cemu_guest_mangohud.sh` uses the Nix package rather than the host layer. Remote runs should prefer MangoHud CSV/log output over visual inspection.
- **`/usr/bin/start_cemu.sh`** with `set_kill`, `/etc/profile`, etc.
  Replaced by `start_cemu_guest.sh`.
- **python3** for `settings.xml` mutation.
  Replaced by guest-available Perl because the live guest's `/usr/bin/sed` is BusyBox and lacks GNU `sed -z`.

CPU/GPU/affinity policy is centralized in `cemu-sm8550-performance.sh`.
Guest sysfs writes target `/sys/devices/system/cpu/cpufreq/` and
`/sys/class/devfreq/`, both bind-mounted into the guest by the nspawn unit.
Failures on read-only sysfs paths are non-fatal; `host-tune.sh` remains the
explicit temporary host adapter for privileged GPU devfreq writes.

## Cemu promotion and override contract

`start_cemu_guest.sh` defaults to the main-space guest system package:

```text
/run/current-system/sw/bin/cemu
```

It retains `/nix/var/nix/profiles/per-user/root/cemu-promoted/bin/cemu` as a live rollback fallback for guests that have not switched to the current system package yet.

Promote only an already-imported `cemu` output from [`nix-sm8550`](https://github.com/simonwjackson/nix-sm8550):

```sh
/storage/.guest/remote-cemu-promote.sh \
  /nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/cemu
```

The helper installs the package output into a dedicated Nix profile/GC root and refuses outputs that lack the direct package's `nix-support/rocknix-cemu-build/vulkan-loader-lib-path` evidence. The launcher resolves the profile symlink with `readlink -f` before reading package metadata, so Vulkan loader discovery still comes from the real store output.

Build-parity diagnostics may override the binary with `CEMU_BIN` via `start_cemu_guest_candidate.sh`; this keeps settings, saves, XDG paths, and logging identical while changing only the Cemu binary under test. Do not use `CEMU_BIN` to point at host `/usr/bin/cemu` as a product path; host binaries are diagnostic controls only and must not become the Layer 14 runtime contract.

The Cemu package is built as `cemu` in [`nix-sm8550`](https://github.com/simonwjackson/nix-sm8550) and installed into `rocknix-guest-main-space`. Build it on Fuji or another aarch64 builder, import its closure into the Thor guest store when Thor is back online, fingerprint it, live-test it against same-session host control, then promote a rollback profile with `remote-cemu-promote.sh` only when needed.

## Cemu runtime responsibility map

This is the Layer 14 Cemu peelback baseline. Do not delete launcher behavior until its destination and validation gate are explicit.

| Current responsibility | Current owner | Target owner | Classification | Validation gate |
|---|---|---|---|---|
| Cemu source/build/resources | `nix-sm8550/packages/cemu/package.nix` | Cemu package | Required correctness | Build/fingerprint proves generic `gameProfiles` and `resources` exist. |
| Vulkan loader visibility | `start_cemu_guest.sh` reads package metadata | Cemu package wrapper | Required correctness | Direct package entry logs Vulkan backend and Nix Mesa driver without old launcher setup. |
| Promoted binary selection | `start_cemu_guest.sh` / `remote-cemu-promote.sh` | Deployment/profile adapter | Temporary ROCKNIX adapter | Direct package entry works, while profile rollback still functions. |
| HOME/XDG/display/audio defaults | `start_cemu_guest.sh` and Sway unit | Guest session profile | Required session policy | Cemu launched from guest session inherits correct env without Cemu-specific exports. |
| `/storage` config/save/BIOS layout | `cemu-storage-adapter.sh` | Guest compatibility adapter or migration | Temporary ROCKNIX adapter | Existing settings/saves/keys survive; fresh state seeds once; no broad bind added. |
| SM8550 default settings | Cemu package metadata + guest storage seed | Guest/device profile | Device policy | Package-owned launch works while SM8550 settings remain explicit and reviewable. |
| SDL screensaver workaround | `start_cemu_guest.sh` | Package wrapper or guest session | Required if crash still reproduces | Run without/with hint and keep only if it prevents a real crash. |
| CPU affinity | `cemu-sm8550-performance.sh` via guest session `CEMU_AFFINITY_MASK` | SM8550 guest/device profile | Measured optimization | Paired in-game run proves pinned guest Cemu improves FPS/frame pacing. |
| CPU/GPU governors/clocks | `cemu-sm8550-performance.sh` / temporary `host-tune.sh` | SM8550 guest/device profile, host helper only if privileged | Measured optimization | Paired in-game run proves benefit and restore path. |
| BOTW profile/settings mutation | `botw-guest.sh` | Game-specific validation/helper | Validation workload only | Never enters generic Cemu package or package wrapper. |
| Host Cemu parity control | `launch-host-cemu-through-guest-display.sh` | Diagnostic harness | Temporary diagnostic | Used only for future parity comparisons; not product path. |

## Required nspawn binds

```
--bind-ro=/storage/roms             # ROM content is read-only
--bind=/storage/roms/bios:/storage/roms/bios
--bind=/storage/.config/Cemu:/storage/.config/Cemu
--bind=/storage/.config/MangoHud:/storage/.config/MangoHud
--bind=/storage/.local:/storage/.local
--bind=/sys/devices/system/cpu/cpufreq
--bind=/sys/class/devfreq
```

## Validation status (2026-05-10)

- U8 adapter thinning follows once package-owned launch is proven and passed a live MangoHud run: `/storage/.guest/runs/20260510-231352-u8-thin-adapter-mangohud`. `start_cemu_guest.sh` no longer owns Vulkan loader setup, launched requested/binary path `/nix/var/nix/profiles/per-user/root/cemu-promoted/bin/cemu`, and recorded avg 47.26 / median 45.00 / p10 44.47 FPS early in-game.
- U6 performance-policy relocation passed a live MangoHud run: `/storage/.guest/runs/20260510-230455-u6-sm8550-performance-helper-mangohud`. The run uses `cemu-sm8550-performance.sh` for CPU/GPU/affinity policy while keeping the package entry generic; post-pin CSV stats were avg 43.92 / median 44.96 / p10 34.67 FPS with CPU/GPU unrestricted and affinity `0xF8`.
- U5 storage-adapter peelback passed a live MangoHud run: `/storage/.guest/runs/20260510-225813-u5-storage-adapter-mangohud-unrestricted`. The run used the package-owned entry point through `start_cemu_guest.sh`, logged `cemu_storage_adapter=ok`, preserved existing settings/saves/keys paths before/after, and recorded MangoHud CSV stats around avg 48.50 / median 45.01 / p10 44.55 FPS early in-game with CPU/GPU unrestricted.
- Promoted Nix Cemu (`/nix/var/nix/profiles/per-user/root/cemu-promoted/bin/cemu`) runs BOTW 540p-45 through native Nix Mesa/Freedreno at host-like performance: live ~40-45 FPS, MangoHud median ~40 FPS after warmup. Current main-space guests prefer `/run/current-system/sw/bin/cemu` and keep the promoted profile as rollback.
- Same-session host control (`/usr/bin/cemu`, ROCKNIX Mesa 26.0.6) matches once it is pinned to the same big-core affinity. A false ~25 FPS host result was traced to unpinned lowercase `cemu`, not to graphics-driver passthrough.
- Product path remains Nix Cemu + Nix Vulkan loader + Nix Mesa/Freedreno. ROCKNIX Mesa passthrough is diagnostic-only.
- `games-launcher.sh` renders all 7 BOTW profile entries on DSI-1,
  full labels (FAST / NATIVE / POTATO suffixes), tap or `Mod+G`.

## Single-run headless validation

Run from the ROCKNIX host over SSH when no one can visually inspect the device:

```sh
/storage/.guest/remote-cemu-single-run-validation.sh potato-30
```

The command creates `/storage/.guest/runs/<timestamp>-single-run-validation/` and writes `report.md` plus `summary.tsv`. By default it runs the promoted Nix Cemu path with profile-power gamescope, profile-power direct, and max-power gamescope. Use `VALIDATION_DURATION=120` for a shorter smoke. Set `VALIDATION_INCLUDE_ROCKNIXMESA=1` only when explicitly diagnosing the host-Mesa shim.

## Build fingerprint and runtime A/B

Run from the ROCKNIX host over SSH:

```sh
# Compare host ROCKNIX Cemu, current guest Nix Cemu, and optionally a candidate.
CANDIDATE_CEMU=/nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/cemu \
  /storage/.guest/remote-cemu-build-fingerprint.sh

# Run current-vs-candidate through the same guest display path.
CANDIDATE_CEMU=/nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/cemu \
  /storage/.guest/remote-cemu-runtime-ab.sh potato-30 120

# Live in-game checkpoint mode. Start the run, move BOTW to an in-game scene,
# then signal from another SSH shell. Optional text in the signal file is copied
# into the report as the user-observed FPS note.
CANDIDATE_CEMU=/nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/cemu \
  /storage/.guest/remote-cemu-runtime-ab.sh live 720p-45 300
printf 'user-visible MangoHud ~= 14 FPS in-game\n' > /storage/.guest/live-checkpoint
```

Reports land under `/storage/.guest/runs/<timestamp>-cemu-build-fingerprint/`
and `/storage/.guest/runs/<timestamp>-cemu-runtime-ab/`.

## One-session live campaign

When Thor is available and you can spend one uninterrupted in-game session, run:

```sh
/storage/.guest/remote-cemu-live-campaign.sh
```

The campaign defaults to `720p-45` through `guest-gamescope-mangohud` and runs the promoted Nix Cemu profile. Add `ROCKNIX_PACKAGE_CEMU` or newline-separated `EXTRA_GUEST_CASES` only when testing an explicit new guest candidate.

For the final parity gate, use typed cases so host controls and guest candidates are explicit. Recommended shape is A/B/A or B/A/B, for example:

```sh
CAMPAIGN_CASES="host:host-control:/storage/.guest/launch-host-cemu-through-guest-display.sh:720p-45
guest:nix-sm8550:/nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/cemu
host:host-control-repeat:/storage/.guest/launch-host-cemu-through-guest-display.sh:720p-45" \
  /storage/.guest/remote-cemu-live-campaign.sh
```

A host-control launcher must run host `/usr/bin/cemu` through the same guest-visible display path, accept `RUN_DIR`, `PROFILE`, `VARIANT`, `CEMU_ROM`, `MANGOHUD_CONFIGFILE`, `XDG_RUNTIME_DIR`, and `WAYLAND_DISPLAY`, and write comparable host-side Cemu/MangoHud/log evidence into `RUN_DIR`. If that contract cannot be proven, the case is inconclusive rather than a parity result.

For each case, get BOTW to a real in-game scene, then from another SSH shell write the observed FPS and notes:

```sh
echo 'visible FPS: <value>; notes: <loading/stutter>' > /storage/.guest/live-checkpoint
```

The script samples for 45 seconds after each checkpoint, records process maps, hot threads, pressure, shader-cache shape, screenshot, and recent MangoHud FPS stats, then advances to the next case. The final report lands in `/storage/.guest/runs/<timestamp>-cemu-live-campaign/report.md`.

Guest-only overrides still work with newline-separated `label=/nix/store/.../bin/Cemu` entries:

```sh
EXTRA_GUEST_CASES="next-candidate=/nix/store/.../bin/Cemu" \
  /storage/.guest/remote-cemu-live-campaign.sh
```

## Remote benchmark harness

Run from the ROCKNIX host over SSH:

```sh
/storage/.guest/remote-cemu-runner.sh guest-direct potato-30 90
/storage/.guest/remote-cemu-runner.sh guest-direct-mangohud potato-30 90
/storage/.guest/remote-cemu-runner.sh guest-gamescope potato-30 90
/storage/.guest/remote-cemu-runner.sh guest-gamescope-mangohud potato-30 90

# Diagnostic only: Nix Cemu + Nix Vulkan loader + ROCKNIX Mesa ICD/deps.
/storage/.guest/remote-cemu-runner.sh guest-direct-rocknixmesa-mangohud potato-30 90
/storage/.guest/remote-cemu-runner.sh guest-gamescope-rocknixmesa-mangohud potato-30 90
```

Each run creates a directory under `/storage/.guest/runs/` containing:

- `status.log`
- `title-samples.log`
- `host-state.txt`
- `guest-state.txt`
- `cleanup.log`
- `screenshot-DSI2.png` when `grim` succeeds
- MangoHud CSV/log files when MangoHud logging starts

Safety notes:

- `remote-cemu-cleanup.sh` exits non-zero if exact-name Cemu/gamescope/MangoHud processes or stale guest Sway Cemu windows survive cleanup. Use `CLEANUP_ALLOW_STALE=1` only for manual diagnostics, never for parity promotion.
- Do not bind all of `/storage/.cache` into the guest. Host and guest Mesa shader caches may belong to different Mesa versions.
- Do not mix host and Nix Vulkan loaders in the Cemu process. The host-Mesa hot-swap experiment reached Mesa 26 in `vulkaninfo` but crashed Cemu due to an incoherent two-loader process.
- Nix Mesa 26.0.2 can be made visible to the guest with `VK_ICD_FILENAMES`, but it failed Cemu with `failed to submit command buffer. Error -4`; keep that as negative evidence.
- ROCKNIX Mesa 26.0.6 via `start_cemu_guest_rocknixmesa.sh` is stable for diagnostics, but it is still a host artifact shim and not the product target.
- Do not toggle Cemu fullscreen live with sway while Vulkan is active; relaunch instead.
