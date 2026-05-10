# ROCKNIX Layer 14 Cemu performance audit (2026-05-09)

## Context

Layer 14 runs Cemu inside the Nix guest while ROCKNIX remains the thin host/recovery plane. Earlier ad-hoc tests showed BOTW sometimes dropping to ~3-15 FPS in the guest.

## Remote harness

Added host-side scripts under `projects/ROCKNIX/packages/tools/nix-integration/guest/launchers/`:

- `remote-cemu-cleanup.sh` kills only exact Cemu/gamescope process names and keeps the nspawn guest service alive.
- `remote-cemu-runner.sh` creates `/storage/.guest/runs/<timestamp>-<variant>-<profile>/` with title FPS samples, Cemu logs, stdout logs, host/guest state, screenshot, and MangoHud CSV when enabled. It accepts `RUNNER_CEMU_START` so candidate Cemu wrappers can be tested without changing the stable launcher.
- `remote-cemu-build-fingerprint.sh` creates a host/current-guest/candidate build-runtime comparison report covering versions, ELF/linkage, wrappers, Vulkan ICDs, and Nix store references.
- `remote-cemu-runtime-ab.sh` runs current-vs-candidate guest Cemu binaries through the same guest display path and includes a live checkpoint mode for real in-game sampling.
- `start_cemu_guest_candidate.sh` runs a caller-selected guest-native Cemu binary via `CEMU_BIN` while preserving the normal guest config/cache setup.
- `start_cemu_guest_mangohud.sh` and `start_cemu_guest_gamescope.sh` provide Nix MangoHud/Nix gamescope wrappers.
- `start_cemu_guest_rocknixmesa.sh` is diagnostic-only: Nix Cemu + Nix Vulkan loader + ROCKNIX Mesa ICD/deps, without host Vulkan loader `LD_PRELOAD`.

## Findings

- The guest baseline is much better under controlled power/cleanup than the earlier 3-15 FPS symptom suggested.
- Post-load MangoHud CSV for `potato-30` usually has median FPS near 30, but recurring startup/scene hitches remain.
- Nix gamescope FSR (`640x360 -> 1920x1080`) does not materially change the hitch pattern by itself.
- Nix Mesa 26.0.2 is visible to `vulkaninfo`, but Cemu fails with `failed to submit command buffer. Error -4`.
- ROCKNIX Mesa 26.0.6 via a narrow ICD/dependency shim is stable and logs `Driver version: Mesa 26.0.6`, but post-load behavior is similar to Nix Mesa 25.2.6. That path is diagnostic only, not the product target.
- The old host control launcher no longer runs in thin-host mode because host Wayland is not active. Attempting host Cemu against the guest sway socket fails in GTK/Xwayland setup, so a clean host-control A/B needs a dedicated compatible harness.

## Representative post-load CSV stats

Cutoff: MangoHud samples after 40s elapsed.

| Variant | Mesa | Pipeline | Avg | Median | p10 | p1 |
|---|---:|---|---:|---:|---:|---:|
| `guest-direct-mangohud` | 25.2.6 | direct fullscreen | 31.15 | 29.93 | 23.44 | 8.51 |
| `guest-direct-rocknixmesa-mangohud` | 26.0.6 | direct fullscreen | 31.05 | 29.42 | 23.07 | 9.29 |
| `guest-gamescope-rocknixmesa-mangohud` | 26.0.6 | gamescope FSR | 31.03 | 29.97 | 23.28 | 8.35 |

After 70s elapsed the severe startup hitches largely disappear in these short runs; p1 rises to ~15-21 FPS depending on variant.

## Single-run headless validation result

A one-command validation run was executed on Thor:

- Parent: `/storage/.guest/runs/20260509-132650-single-run-validation`
- Report: `/storage/.guest/runs/20260509-132650-single-run-validation/report.md`
- Profile: `potato-30`
- Duration per child: 180s

| Class | Power | Variant | Driver | first FPS approx s | post70 avg | post70 p1 | post70 p10 | post70 median | <15fps samples |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| FAIL | profile | guest-gamescope-mangohud | Mesa 25.2.6 | 66 | 26.82 | 11.64 | 13.66 | 29.92 | 407 |
| FAIL | profile | guest-direct-mangohud | Mesa 25.2.6 | 62 | 27.11 | 11.63 | 13.57 | 29.94 | 420 |
| WARN | max | guest-gamescope-mangohud | Mesa 25.2.6 | 32 | 31.02 | 22.58 | 29.82 | 30.00 | 10 |
| FAIL | profile | guest-gamescope-rocknixmesa-mangohud | Mesa 26.0.6 | 64 | 27.26 | 11.39 | 13.59 | 29.97 | 468 |

Interpretation:

- The best candidate is **max-power guest gamescope with Nix Mesa 25.2.6**.
- Profile-power is too constrained for stable frame pacing in the guest, even though median FPS still reaches ~30.
- ROCKNIX Mesa 26.0.6 diagnostic does not improve the profile-power hitch pattern.
- The best candidate is still classified `WARN`, not `PASS`, because one post-warmup outlier dropped to 4.23 FPS and the strict gate required post70 min >= 10. However, p1/p10/median are much stronger than previous runs.
- Thor was left clean: no Cemu/gamescope processes, guest service active, CPU governors restored to schedutil, GPU restored to simple_ondemand 220-680 MHz.

## 720p-45 follow-up

A focused 720p-45 guest gamescope run was executed:

- Run: `/storage/.guest/runs/20260509-134654-guest-gamescope-mangohud-720p-45`
- Command shape: `RUNNER_POWER=max remote-cemu-runner.sh guest-gamescope-mangohud 720p-45 180`
- Driver: Mesa 25.2.6
- Title samples warmed from ~30-40 FPS to sustained `45.00 FPS` for most of the run.

Post-warmup MangoHud CSV stats:

| Window | Avg | Min | p1 | p10 | Median | Below 30 | Below 40 |
|---|---:|---:|---:|---:|---:|---:|---:|
| post40s | 44.48 | 0.22 | 21.93 | 31.65 | 44.98 | 510 | 814 |
| post70s | 45.78 | 12.21 | 25.45 | 44.49 | 45.00 | 154 | 257 |
| post100s | 46.25 | 12.21 | 29.34 | 44.60 | 45.01 | 37 | 83 |
| post120s | 46.34 | 12.21 | 28.93 | 44.57 | 45.01 | 29 | 67 |

Interpretation: **720p-45 is the strongest headless result so far**. It still has startup/warmup dips, but after ~100s it is essentially locked to the 45 FPS target by median and p10, with p1 around 29 FPS. Thermals rose but stayed below the earlier 90C+ danger zone during the captured run (`cpu7-middle` peaked in the high 80s in the run-state snapshot).

## GPU demo A/B follow-up

To isolate raw GPU/display performance from Cemu emulation, a same-output A/B was run through the guest sway socket:

- Run: `/storage/.guest/runs/20260509-151751-vkcube-ab`
- Host ROCKNIX `vkcube` + Mesa 26.0.6 via guest sway: 900 frames in 7.7s
- Guest Nix `vkcube` + Mesa 25.2.6 via guest sway: 900 frames in 7.6s

A heavier `glmark2-es2-wayland` A/B was also run through the same guest sway output:

- Run: `/storage/.guest/runs/20260509-151852-glmark2-ab`
- Benchmark: `1920x1080`, `terrain`, `shading=phong`, `shadow`, 600 frames each

| Runtime | Mesa | terrain FPS | shading FPS | shadow FPS | Score |
|---|---:|---:|---:|---:|---:|
| host ROCKNIX binary via guest sway | 26.0.6 | 244 | 5623 | 1803 | 2555 |
| guest Nix binary via guest sway | 25.2.6 | 231 | 4544 | 1698 | 2156 |

Interpretation: the guest GL/Vulkan display path is within roughly 5-16% of the host binary for these demos, not 5x slower. This strongly suggests the live BOTW 7-15 FPS issue is **not raw GPU/display throughput**. It is more likely Cemu/emulation/runtime/cache/CPU behavior in the guest.

Caveat: this was not a true standard-host-compositor test because the Layer 14 thin host does not currently have its own active host Wayland session. Both host and guest demo apps presented through guest sway to avoid disrupting the user's live display.

## Build parity instrumentation added

The next diagnostic layer now exists in-tree:

| Tool | Purpose | Product status |
|---|---|---|
| `remote-cemu-build-fingerprint.sh` | Compare ROCKNIX host Cemu, current guest Nix Cemu, and optional candidate build/runtime surfaces. | Diagnostic, safe to keep. |
| `cemu-rocknix-style` flake output | Guest-native Nix derivation that mirrors ROCKNIX `cemu-sa` CMake/compiler posture more closely. | Candidate only until live validation wins. |
| `start_cemu_guest_candidate.sh` | Runs an explicit `CEMU_BIN` through the normal guest launcher setup. | Diagnostic selector, not a host-binary bridge. |
| `remote-cemu-runtime-ab.sh` | Runs current-vs-candidate Cemu A/B under the same guest display path, plus live checkpoint mode. | Diagnostic, safe to keep. |

This keeps the investigation aligned with the Layer 14 product target: a coherent guest-native Nix runtime, not broad host binds or a mixed Vulkan loader process.

## Host Cemu parity breakthrough

A later live A/B proved that the guest display path can run BOTW at the expected target when the **ROCKNIX host Cemu binary/runtime** is used through the guest sway output:

- Run: `/storage/.guest/runs/20260509-234946-host-cemu-direct-540p45-botw`
- Binary: `/usr/bin/cemu`
- Cemu version string: `Cemu 6f6c129`
- Driver: `Mesa 26.0.6`
- BOTW profile: `gameProfiles/default/00050000101c9400.ini`
- Graphics pack: `960x540`, `45FPS Limit`
- Live/CSV result: stable around `45 FPS`

That same display route is therefore not the limiting factor. The current guest-native Nix Cemu remains materially different from ROCKNIX Cemu despite using the same source commit in the flake.

### Exact ROCKNIX Cemu package behavior to replicate in Nix

ROCKNIX `cemu-sa` is defined in `projects/ROCKNIX/packages/emulators/standalone/cemu-sa/package.mk`:

- Source: `cemu-project/Cemu` commit `6f6c1299e29fa6e1062ae283a035b4ef787cc397`.
- Build dependencies include `libzip glslang glm curl rapidjson openssl boost libfmt pugixml libpng gtk3 wxwidgets SDL2 libsodium hidapi spirv-tools`, plus display/GPU deps based on ROCKNIX options.
- Pre-configure mutations:
  - remove `find_package(cubeb)` so the bundled cubeb submodule is built/used;
  - replace `glm::glm` with `glm` in CMake files;
  - add `-fpch-preprocess`;
  - set CMake flags: `ENABLE_VCPKG=OFF`, `ENABLE_DISCORD_RPC=OFF`, `ENABLE_SDL=ON`, `ENABLE_CUBEB=ON`, `ENABLE_WXWIDGETS=ON`, `CMAKE_BUILD_TYPE=Release`, `ENABLE_FERAL_GAMEMODE=OFF`, plus Wayland/OpenGL/Vulkan toggles.
- Patches:
  - `000-build-fixes.patch`: explicit OpenSSL link, NEON reinterpret fixes, wxWidgets `sharpyuv` link, aarch64 imgui `-mcmodel=large`.
  - `002-opt-seeprom-mlc01-keys-dir.patch`: redirects online/key files into `online/` and `keys/` under the Cemu user-data path.
  - `003-disable-cmake-interprocedural-optimization.patch`: disables upstream IPO/LTO.
- Install layout:
  - `${PKG_BUILD}/bin/Cemu_*` -> `/usr/bin/cemu`.
  - package scripts -> `/usr/bin/`, especially `/usr/bin/start_cemu.sh`.
  - device config `${PKG_DIR}/config/${DEVICE}/*` -> `/usr/config/Cemu`.
  - `${PKG_BUILD}/bin/gameProfiles` and `${PKG_BUILD}/bin/resources` -> `/usr/share/Cemu`.

The `/usr/share/Cemu` install is critical. Host Cemu has:

- `/usr/share/Cemu/gameProfiles/default/00050000101c9400.ini`
- `/usr/share/Cemu/resources/sharedFonts/Cafe*.ttf`
- 236 game profile files and 23 resource files on Thor.

The current Nix Cemu store outputs only desktop/icon metadata under `$out/share`; it does **not** install `gameProfiles` or `resources`. This is why Nix Cemu logs:

```text
gameprofile path:  (not present)
Shared font CafeCn.ttf is not present
```

while ROCKNIX Cemu logs:

```text
gameprofile path: gameProfiles/default/00050000101c9400.ini
COS: System fonts found. Generated shareddata
```

### Nix Cemu differences observed before the faithful candidate

Earlier guest Nix Cemu candidates showed these deltas against host Cemu:

- Binary: `/nix/store/wl4g8jjlw6pck4sh4ayah9pdl03z8brp-cemu-2.999.0/bin/Cemu`
- Runtime binary: wrapped `.Cemu-wrapped` with a Nix RUNPATH.
- Version string: `2.999`, not `Cemu 6f6c129`.
- Missing `$out/share/Cemu/gameProfiles` and `$out/share/Cemu/resources` until the resource-install fix landed.
- Dynamically linked several libs that ROCKNIX does not expose the same way, including `libboost_program_options.so.1.89.0`, `libglslang.so.16`, `libcubeb.so.0`, and initially `sdl2-compat` rather than ROCKNIX classic SDL2.
- Initially applied `000-build-fixes.patch` and `003-disable-cmake-interprocedural-optimization.patch`, but not `002-opt-seeprom-mlc01-keys-dir.patch`.

The resource-fixed `cemu-rocknix-style` candidate now installs `gameProfiles`/`resources` and applies `002`, but live testing still showed slow RPL/HLE times and low visible FPS. Resource parity was necessary but insufficient.

### 2026-05-10 faithful Nix candidate

A stricter flake output now exists for the next live A/B:

- Output: `.#cemu-rocknix-faithful`
- Local derivation file: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-faithful.nix`
- Fuji/Thor store path: `/nix/store/5jsidzsal8l3k5m3v8ibk8ipny49bx22-cemu-rocknix-faithful-2.999.0-rocknix-faithful/bin/Cemu`
- Build host: Fuji (`aarch64`)
- Build result: succeeded; closure imported into Thor's guest Nix store.
- Runtime data assertions passed:
  - `$out/share/Cemu/gameProfiles/default/00050000101c9400.ini`
  - `$out/share/Cemu/resources/sharedFonts/CafeCn.ttf`
- Fuji fingerprint: real `.Cemu-wrapped` is ELF `EXEC` and no longer lists dynamic `libcubeb.so.0` in `NEEDED`/`ldd`.
- Thor fingerprint report: `/storage/.guest/runs/20260510-011343-cemu-build-fingerprint/report.md`

This candidate removes nixpkgs `cubeb` from the build inputs after deleting `find_package(cubeb)`, starts from the classic SDL2 candidate, and passes `-no-pie` through executable link flags.

First validation attempts:

- `/storage/.guest/runs/20260509-231602-faithful-cemu-live-540p45`: accidentally ran against Nix Mesa 25.2.6 due the candidate wrapper bypassing the ROCKNIX Mesa launcher; user reported it was still slow; recent CSV averaged 5.63 FPS.
- `/storage/.guest/runs/20260509-232506-faithful-cemu-rocknixmesa-wrapperfix-live-540p45`: fixed the candidate wrapper to preserve `start_cemu_guest_rocknixmesa.sh`; Cemu log confirmed Mesa 26.0.6, BOTW profile/resources, RPL link time ~530ms, HLE scan time ~408ms, and `Cubeb: not supported`. The user reported loading/title remained slow like other slow Cemu runs before reaching in-game. The post-checkpoint CSV averaged 47.22 FPS with median 45.00, but this was not a decisive in-game sample and should not override the user-visible slow-loading/title observation.

Conclusion so far: ELF `EXEC`, no dynamic `libcubeb.so.0`, classic SDL2, runtime data, and ROCKNIX Mesa passthrough still do **not** reproduce host Cemu's fast RPL/HLE behavior. The remaining gap is deeper than the first faithful-candidate parity surfaces.

### Native Nix replication target

A real `rocknix-cemu` Nix derivation should not be a generic nixpkgs Cemu override. It should mirror the ROCKNIX package contract:

1. Build the exact commit `6f6c1299e29fa6e1062ae283a035b4ef787cc397` with submodules.
2. Apply all three ROCKNIX patches, including `002-opt-seeprom-mlc01-keys-dir.patch`.
3. Use ROCKNIX-equivalent CMake flags and pre-configure edits, especially bundled cubeb and IPO disabled.
4. Install Cemu data resources:
   - `bin/gameProfiles` -> `$out/share/Cemu/gameProfiles`
   - `bin/resources` -> `$out/share/Cemu/resources`
5. Ensure the compiled/installed data path resolves to `$out/share/Cemu` in the Nix store.
6. Provide a Nix-native launcher equivalent to `start_cemu.sh` that initializes `/storage/.config/Cemu`, links `/storage/.local/share/Cemu`, redirects `online/mlc01/keys` into `/storage/roms/bios/cemu`, mutates settings via XML, and launches with the coherent graphics runtime.
7. Run with a coherent Vulkan/Mesa stack. Short term this means ROCKNIX Mesa 26.0.6 passthrough; long term it means a Nix Mesa matching ROCKNIX's Turnip behavior.

## Decision

Do not productize host Mesa shims or host Vulkan loader preloads. Host Cemu through guest display is now the control that proves the display path can hit 45 FPS. The native Nix path is to turn ROCKNIX `cemu-sa` into a faithful Nix derivation, including data-resource installation and launcher semantics, rather than continuing to tune the generic nixpkgs-derived Cemu output.

### 2026-05-10 direct ROCKNIX package replica

A direct package-replica output now exists alongside the nixpkgs-derived controls:

- Output: `.#cemu-rocknix-package`
- Manifest: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-package-manifest.nix`
- Derivation: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-package.nix`
- Fuji build result: `/nix/store/841c43k9pw1awij24lp140hwg4yapwxk-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu`
- Build posture: direct `stdenv.mkDerivation`, no `pkgs.cemu`/`baseCemu`/`overrideAttrs`, no `wrapGAppsHook3`, no nixpkgs imgui replacement.
- Runtime data assertions passed:
  - `$out/share/Cemu/gameProfiles/default/00050000101c9400.ini`
  - `$out/share/Cemu/resources/sharedFonts/CafeCn.ttf`
  - `$out/share/Cemu/config/SM8550/settings.xml`
- Fuji fingerprint: ELF `EXEC`, no dynamic `libcubeb.so.0` in `NEEDED`, bundled Cubeb build path, classic SDL2 (`libSDL2-2.0.so.0`), SM8550 default settings, and build evidence under `$out/nix-support/rocknix-cemu-build/`.
- Version evidence: the binary contains `Cemu 6f6c129`; `Cemu --version` still prints `0.0`, matching the upstream numeric-version fallback when `EMULATOR_VERSION_MAJOR/MINOR/PATCH` remain zero.

Thor is offline, so this closure has **not** yet been imported or live-tested on-device. Next validation step is to import this Fuji-built closure into the Thor guest store, run `remote-cemu-build-fingerprint.sh` against the candidate, then run same-session host-control vs candidate live BOTW A/B before interpreting FPS.
