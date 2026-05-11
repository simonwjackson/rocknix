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
7. Run with a coherent Vulkan/Mesa stack. The direct package's successful path uses native Nix Mesa/Freedreno plus the package-recorded Nix Vulkan loader path; ROCKNIX Mesa passthrough remains diagnostic only for isolating graphics-stack deltas.

## Decision

Do not productize host Mesa shims or host Vulkan loader preloads. Host Cemu through guest display is now the control that proves the display path can hit 45 FPS. The native Nix path is to turn ROCKNIX `cemu-sa` into a faithful Nix derivation, including data-resource installation and launcher semantics, rather than continuing to tune the generic nixpkgs-derived Cemu output.

### 2026-05-10 direct ROCKNIX package replica

A direct package-replica output now exists alongside the nixpkgs-derived controls:

- Output: `.#cemu-rocknix-package`
- Manifest: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-package-manifest.nix`
- Derivation: `projects/ROCKNIX/packages/tools/nix-integration/guest/flakes/cemu/rocknix-package.nix`
- Initial Fuji build result: `/nix/store/841c43k9pw1awij24lp140hwg4yapwxk-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu`
- Vulkan-loader-fixed Thor candidate: `/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu`
- Build posture: direct `stdenv.mkDerivation`, no `pkgs.cemu`/`baseCemu`/`overrideAttrs`, no `wrapGAppsHook3`, no nixpkgs imgui replacement.
- Runtime data assertions passed:
  - `$out/share/Cemu/gameProfiles/default/00050000101c9400.ini`
  - `$out/share/Cemu/resources/sharedFonts/CafeCn.ttf`
  - `$out/share/Cemu/config/SM8550/settings.xml`
- Fuji fingerprint: ELF `EXEC`, no dynamic `libcubeb.so.0` in `NEEDED`, bundled Cubeb build path, classic SDL2 (`libSDL2-2.0.so.0`), SM8550 default settings, and build evidence under `$out/nix-support/rocknix-cemu-build/`.
- Version evidence: the binary contains `Cemu 6f6c129`; `Cemu --version` still prints `0.0`, matching the upstream numeric-version fallback when `EMULATOR_VERSION_MAJOR/MINOR/PATCH` remain zero.

The first imported direct candidate was invalid for performance because Cemu fell back to OpenGL (`Vulkan loader not available`). The package now records `nix-support/rocknix-cemu-build/vulkan-loader-lib-path`, and `start_cemu_guest.sh` adds that path to `LD_LIBRARY_PATH` only for the Cemu process.

Validated Vulkan-fixed run:

- Run: `/storage/.guest/runs/20260510-094138-cemu-live-package-vulkanfix/report.md`
- Candidate: `/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu`
- Runtime stack: native Nix Mesa/Freedreno, `Driver version: Mesa 25.2.6`, with Cemu using the package-recorded Nix Vulkan loader path.
- Cemu evidence: `Init Vulkan graphics backend`, BOTW profile `gameProfiles/default/00050000101c9400.ini`, RPL link time about `153ms`, HLE scan time about `145ms`.
- Live result: user-corrected visible FPS about `40 FPS`; MangoHud CSV avg `38.11`, median `38.34`, p10 `35.77`.
- Operator correction artifact: `/storage/.guest/runs/20260510-094138-cemu-live-package-vulkanfix/rocknix-package-vulkanfix-guest-gamescope-mangohud-720p-45/operator-correction.txt`.

Remaining gap: historical host-control evidence was about `45 FPS`, but it was not captured in the same session as the fixed direct candidate. The next validation must be same-session host-control vs direct Nix Cemu using the typed live-campaign harness. Native Nix Mesa is product-eligible if it passes that gate; ROCKNIX Mesa passthrough is diagnostic-only and should redirect to a graphics-stack plan if it alone closes the gap.

### 2026-05-10 parity/simplification harness update

The follow-up plan is `docs/plans/2026-05-10-003-fix-cemu-host-parity-simplification-plan.md`. Supporting harness changes:

- `remote-cemu-live-campaign.sh` accepts typed `guest:<label>:<cemu-bin>` and `host:<label>:<host-launcher>:<profile>` cases, indexes child run directories (`001-...`, `002-...`) so A/B/A repeats do not overwrite evidence, and marks cleanup-incomplete cases explicitly.
- `remote-cemu-runner.sh` exposes `RUNNER_HOST_LAUNCHER` for host-control cases and captures host-side process/env/maps/log evidence under the same run directory schema.
- `remote-cemu-cleanup.sh` now fails if exact-name emulator processes survive cleanup unless `CLEANUP_ALLOW_STALE=1` is set for manual diagnostics.
- `start_cemu_guest.sh` now defaults to the dedicated promoted profile `/nix/var/nix/profiles/per-user/root/cemu-promoted/bin/Cemu`, preserves `CEMU_BIN` for rollback/diagnostics, and resolves profile symlinks with `readlink -f` before reading direct-package metadata.
- `remote-cemu-promote.sh` promotes an already-imported direct package output into the dedicated profile only after verifying its direct-package Vulkan loader evidence.

### 2026-05-10 same-session parity result and simplification decision

Thor came back online and the fixed direct package was promoted into:

```text
/nix/var/nix/profiles/per-user/root/cemu-promoted/bin/Cemu
```

The promoted profile resolved to:

```text
/nix/store/2vahrn6mc766rk5zchxk4a9601c0h648-cemu-rocknix-package-2.999.0-rocknix-package/bin/Cemu
```

Clean promoted Nix run:

- Run: `/storage/.guest/runs/20260510-191237-redo-clean-promoted-540p45`
- Runtime: Nix Cemu + Nix Vulkan loader + Nix Mesa/Freedreno (`Driver version: Mesa 25.2.6`).
- BOTW profile: `960x540`, FPS++ `45FPS Limit`, `gameProfiles/default/00050000101c9400.ini` present.
- Live operator result: fast loading, visible `40-45 FPS`.
- MangoHud after warmup: median about `40 FPS`, p10 about `36 FPS`.
- Cleanup verified: no exact-name emulator processes and no stale guest Sway Cemu windows.

Same-session host control:

- Run: `/storage/.guest/runs/20260510-192613-host-observe-540p45`
- Runtime: host `/usr/bin/cemu` + ROCKNIX Mesa/Freedreno (`Driver version: Mesa 26.0.6`) through the guest-visible display path.
- Initial live result was only about `25 FPS` because host-control failed to detect/pin lowercase `cemu` and Cemu threads landed across all cores.
- After pinning host Cemu to `0xF8`, a 30s capture (`post-pin-30s-*`) showed MangoHud avg `40.58`, median `40.74`, p10 `36.54`; title samples averaged `40.25`.

Conclusion: the remaining Cemu gap was launcher affinity/control hygiene, not ROCKNIX Mesa passthrough. Native Nix Mesa/Freedreno is product-eligible for Cemu. ROCKNIX Mesa wrappers remain diagnostic-only for future graphics-stack investigations.

Simplification decision:

- Keep `cemu-rocknix-package`, promoted profile launch, `CEMU_BIN` rollback, exact cleanup, stale-window cleanup, fingerprinting, and typed host-control support.
- Retire the override-based flake outputs and files (`cemu-rocknix-style`, `cemu-rocknix-style-classic-sdl`, `cemu-rocknix-faithful`).
- Remove ROCKNIX-Mesa variants from default validation matrices; require an explicit diagnostic opt-in.

### 2026-05-11 guest-owned runtime peelback baseline

The next step is not more emulator breadth. It is to peel Cemu away from ROCKNIX launcher glue while preserving in-game performance. The current responsibility map is:

| Responsibility | Current owner | Target owner | Keep condition |
|---|---|---|---|
| Cemu build/resources | Direct Nix package | Cemu package | Always; generic runtime data only, not BOTW-specific assertions. |
| Vulkan loader visibility | `start_cemu_guest.sh` | Cemu package wrapper | Required until direct package launch proves Vulkan without old launcher setup. |
| Promoted binary selection | Launcher/profile helper | Deployment adapter | Temporary until direct package entry is proven and rollback remains clear. |
| HOME/XDG/display/audio defaults | Launcher plus guest Sway unit | Guest session profile | Keep in guest session, not in the generic Cemu package. |
| `/storage` settings/saves/keys layout | Launcher | Guest compatibility adapter or migration | Keep only to preserve existing user state; avoid package hardcoding. |
| SM8550 settings/performance policy | Package/launcher/BOTW helper | Guest/device profile | Keep only with measured benefit or compatibility need. |
| CPU/GPU tuning and affinity | BOTW helper/host tune | SM8550 profile, host helper only if privileged | Keep only with paired in-game evidence and restore path. |
| BOTW profile mutation | `botw-guest.sh` | Game-specific validation helper | Validation workload only; never generic derivation scope. |
| Host Cemu control | Diagnostic launcher | Diagnostic harness | Future parity control only, not product path. |

Each peelback should compare against the promoted baseline and classify the result as PASS, FAIL, or INCONCLUSIVE using live in-game evidence, Vulkan/driver logs, MangoHud stats, and cleanup proof.
