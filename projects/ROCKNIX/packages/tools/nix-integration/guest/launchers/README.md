# Layer 14 guest launchers

Shell scripts that run inside the Layer 14 Nix guest (systemd-nspawn).
They invoke nix-built emulators with proper env, settings.xml mutation,
and CPU/GPU governor tuning -- without falling back to host binaries
or host Cemu binaries.

## Files

| Script | Role |
|---|---|
| `start_cemu_guest.sh` | Generic cemu launcher. Replaces `/usr/bin/start_cemu.sh` for use inside the guest. Sets up XDG paths so the nix-built cemu shares config + saves with host's cemu, then execs cemu in fullscreen with the requested ROM. |
| `start_cemu_guest_mangohud.sh` | Nix MangoHud wrapper around `start_cemu_guest.sh`. Diagnostic/profile mode only. |
| `start_cemu_guest_gamescope.sh` | Nix gamescope wrapper matching the host 360p/540p -> 1080p FSR pipeline shape. Diagnostic/profile mode until validated. |
| `start_cemu_guest_rocknixmesa.sh` | Diagnostic-only launcher using the ROCKNIX Mesa ICD with a narrow dependency shim while keeping Cemu's Nix Vulkan loader. Do not productize as the final Nix runtime. |
| `start_cemu_guest_candidate.sh` | Diagnostic wrapper that runs a caller-selected guest-native Cemu binary via `CEMU_BIN` while preserving the normal guest config/cache setup. |
| `botw-guest.sh <profile>` | Parametric BOTW launcher. One profile per resolution / FPS combo. Mutates `settings.xml` via sed, tunes CPU/GPU sysfs, calls `start_cemu_guest.sh`, then blocks until cemu exits. Replaces all 11 host `/storage/bin/botw-*.sh` scripts. |
| `games-launcher.sh` | Touch-friendly fuzzel menu pinned to DSI-1 (Thor's bottom panel). Kept available, but not autostarted while touch/menu behavior is under validation. |
| `host-tune.sh` | Host-side sysfs tuning helper. Runs on ROCKNIX host, not inside the guest. |
| `remote-cemu-cleanup.sh` | Host-side cleanup script for unattended Cemu/gamescope experiments. |
| `remote-cemu-runner.sh` | Host-side benchmark harness. Creates `/storage/.guest/runs/<timestamp>-<variant>-<profile>/` with logs, title samples, screenshot, governor/thermal/process state. Supports `RUNNER_CEMU_START` for candidate Cemu launchers. |
| `remote-cemu-single-run-validation.sh` | Host-side one-command orchestrator. Runs a compact headless benchmark matrix, analyzes MangoHud CSVs, writes a parent `report.md`, and restores safe state. |
| `remote-cemu-build-fingerprint.sh` | Host-side build/runtime fingerprint report for ROCKNIX host Cemu, current guest Nix Cemu, and an optional candidate Cemu. |
| `remote-cemu-runtime-ab.sh` | Host-side current-vs-candidate Cemu A/B harness, including a live checkpoint mode for in-game sampling. |
| `remote-cemu-live-campaign.sh` | Host-side one-session live campaign. Runs current Nix Cemu and classic-SDL candidate sequentially, waits for in-game checkpoint notes, captures maps/thread/cache/CSV evidence, then cleans up and restores power state. |

## BOTW profiles

| Profile | Resolution | FPS | Cluster caps (P3/P7 kHz) | GPU governor |
|---|---|---|---|---|
| `potato-30`  | 640x360   | 30 | 1401600 / 1478400 | simple_ondemand 220-475 MHz |
| `540p-30`    | 960x540   | 30 | 1401600 / 1478400 | simple_ondemand 220-550 MHz |
| `540p-45`    | 960x540   | 45 | 1785600 / 1843200 | performance |
| `720p-30`    | 1280x720  | 30 | 1401600 / 1478400 | simple_ondemand 220-615 MHz |
| `720p-45`    | 1280x720  | 45 | 2054400 / 2092800 | performance |
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
  Replaced by sed.

CPU/GPU sysfs writes still target `/sys/devices/system/cpu/cpufreq/`
and `/sys/class/devfreq/`, both bind-mounted into the guest by the
nspawn drop-in. Failures on read-only sysfs paths are non-fatal -- the
host's defaults remain in effect.

## Cemu store path coupling

`start_cemu_guest.sh` defaults to the nix-built cemu by its full
`/nix/store/<hash>-cemu-2.999.0/bin/Cemu` path. Update on every
flake rebuild that changes inputs.

Build-parity diagnostics may override the binary with `CEMU_BIN` via
`start_cemu_guest_candidate.sh`; this keeps settings, saves, XDG paths,
and logging identical while changing only the Cemu binary under test.
Do not use `CEMU_BIN` to point at host `/usr/bin/cemu` as a product
path; host binaries are diagnostic-only and must not become the Layer 14
runtime contract.

The direct ROCKNIX package replica is built as
`cemu-rocknix-package` from `guest/flakes/cemu/rocknix-package.nix`.
Build it on Fuji or another aarch64 builder, then import its closure into the
Thor guest store when Thor is back online. Record the resolved store path in the
fingerprint report before live testing; do not edit the default launcher just to
try one candidate.

Future improvement: read the default from a `nix profile` symlink under
`/storage/.guest/profile/bin/Cemu` so the launcher does not need
editing on each cemu rebuild.

## Required nspawn binds

```
--bind=/storage/.config/Cemu:/storage/.config/Cemu
--bind=/storage/.config/MangoHud:/storage/.config/MangoHud
--bind=/storage/roms/bios:/storage/roms/bios
--bind=/storage/roms                 # already present
--bind=/sys/devices/system/cpu/cpufreq
--bind=/sys/class/devfreq
```

## Validation status (2026-05-09)

- `botw-guest.sh 540p-30` end-to-end: BOTW window title progressed to
  "FPS: 28.00 [Vulkan] [Generic] [TitleId: 00050000-101c9400]
  Breath of the Wild [US v208]". 290% CPU under PPC recompiler.
  No host-binary fallback at any point.
- `games-launcher.sh` renders all 7 BOTW profile entries on DSI-1,
  full labels (FAST / NATIVE / POTATO suffixes), tap or `Mod+G`.

## Single-run headless validation

Run from the ROCKNIX host over SSH when no one can visually inspect the device:

```sh
/storage/.guest/remote-cemu-single-run-validation.sh potato-30
```

The command creates `/storage/.guest/runs/<timestamp>-single-run-validation/` and writes `report.md` plus `summary.tsv`. By default it runs profile-power gamescope, profile-power direct, max-power gamescope, and a diagnostic ROCKNIX-Mesa gamescope variant when that diagnostic wrapper exists. Use `VALIDATION_DURATION=120` for a shorter smoke or `VALIDATION_SKIP_ROCKNIXMESA=1` to skip the diagnostic shim.

## Build fingerprint and runtime A/B

Run from the ROCKNIX host over SSH:

```sh
# Compare host ROCKNIX Cemu, current guest Nix Cemu, and optionally a candidate.
CANDIDATE_CEMU=/nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu \
  /storage/.guest/remote-cemu-build-fingerprint.sh

# Run current-vs-candidate through the same guest display path.
CANDIDATE_CEMU=/nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu \
  /storage/.guest/remote-cemu-runtime-ab.sh potato-30 120

# Live in-game checkpoint mode. Start the run, move BOTW to an in-game scene,
# then signal from another SSH shell. Optional text in the signal file is copied
# into the report as the user-observed FPS note.
CANDIDATE_CEMU=/nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu \
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

The campaign defaults to `720p-45` through `guest-gamescope-mangohud` and runs:

1. current Nix Cemu,
2. `cemu-rocknix-style-classic-sdl`, and
3. any optional `FAITHFUL_CEMU` or `ROCKNIX_PACKAGE_CEMU` path you provide.

For each case, get BOTW to a real in-game scene, then from another SSH shell write the observed FPS and notes:

```sh
echo 'visible FPS: <value>; notes: <loading/stutter>' > /storage/.guest/live-checkpoint
```

The script samples for 45 seconds after each checkpoint, records process maps, hot threads, pressure, shader-cache shape, screenshot, and recent MangoHud FPS stats, then advances to the next case. The final report lands in `/storage/.guest/runs/<timestamp>-cemu-live-campaign/report.md`.

Override cases with newline-separated `label=/nix/store/.../bin/Cemu` entries:

```sh
CAMPAIGN_CASES="current=$CURRENT_CEMU
classic=$CLASSIC_SDL_CEMU
rocknix-package=/nix/store/...-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu" /storage/.guest/remote-cemu-live-campaign.sh
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

- Do not bind all of `/storage/.cache` into the guest. Host and guest Mesa shader caches may belong to different Mesa versions.
- Do not mix host and Nix Vulkan loaders in the Cemu process. The host-Mesa hot-swap experiment reached Mesa 26 in `vulkaninfo` but crashed Cemu due to an incoherent two-loader process.
- Nix Mesa 26.0.2 can be made visible to the guest with `VK_ICD_FILENAMES`, but it failed Cemu with `failed to submit command buffer. Error -4`; keep that as negative evidence.
- ROCKNIX Mesa 26.0.6 via `start_cemu_guest_rocknixmesa.sh` is stable for diagnostics, but it is still a host artifact shim and not the product target.
- Do not toggle Cemu fullscreen live with sway while Vulkan is active; relaunch instead.
