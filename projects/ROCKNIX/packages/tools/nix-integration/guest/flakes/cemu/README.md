# cemu (Wii U emulator) — aarch64 nix flake

Native aarch64-linux build of cemu for the Layer 14 Nix guest.

## Why this exists

`nixpkgs#cemu` is `x86_64-linux` only — it pins to cemu v2.6, which
predates the upstream `BackendAArch64` JIT backend.

ROCKNIX (the host system) builds cemu from upstream commit
`6f6c1299e29fa6e1062ae283a035b4ef787cc397` (2026-04-22), which has
the AArch64 backend. The older diagnostic outputs re-use the same commit and
ROCKNIX's vendored patches while layering on top of `nixpkgs#cemu`'s
derivation.

`cemu-rocknix-package` is the newer parity candidate: it builds Cemu from a
direct `stdenv.mkDerivation` using `rocknix-package-manifest.nix` instead of
inheriting from `nixpkgs#cemu`. Use it when testing whether nixpkgs' package
shape, wrappers, fixups, and inherited dependency choices are the remaining
performance variable.

This means cemu can run **inside the Layer 14 nspawn guest** with all
dependencies coming from `/nix/store` — no `/host/lib`, no overlay
mounts, no loader-symlink swap.

## Build

```sh
nix build .#packages.aarch64-linux.cemu --print-build-logs
nix build .#packages.aarch64-linux.cemu-rocknix-style --print-build-logs
nix build .#packages.aarch64-linux.cemu-rocknix-faithful --print-build-logs
nix build .#packages.aarch64-linux.cemu-rocknix-package --print-build-logs
```

First build takes ~10 min on a 4-core aarch64 host (fuji-class). All
subsequent builds are cache hits unless inputs change. Use Fuji or another
aarch64 builder for compile-heavy experiments; do not tie up the Thor SSH
session or the local workstation with a full Cemu rebuild.

## Outputs

| Output | Purpose |
|---|---|
| `.#cemu` | Current known guest Cemu package. This remains the default until runtime evidence proves a candidate is better. |
| `.#cemu-rocknix-style` | Build-parity candidate that keeps the same source/patches but mirrors ROCKNIX `cemu-sa` CMake flags and compiler posture more closely. Diagnostic until live-in-game validation wins. |
| `.#cemu-rocknix-style-classic-sdl` | Same ROCKNIX-style candidate but forces `SDL2_classic` instead of nixpkgs `sdl2-compat`/SDL3. Used to isolate the remaining SDL runtime mismatch. |
| `.#cemu-rocknix-faithful` | Stricter ROCKNIX `cemu-sa` parity candidate: starts from classic SDL2, removes nixpkgs Cubeb so bundled Cubeb is used, disables PIE for the executable link, and asserts runtime data is installed. This remains an eliminated/control candidate after live testing showed slow RPL/HLE. |
| `.#cemu-rocknix-package` | Direct ROCKNIX package replica built from `stdenv.mkDerivation` and `rocknix-package-manifest.nix`, not from `nixpkgs#cemu`. This is the follow-up candidate for host-control live A/B after the faithful override failed. |

## What the default `.#cemu` output does on top of `nixpkgs#cemu`

| Layer | Why |
|---|---|
| Pin to ROCKNIX upstream commit `6f6c1299` | Has `BackendAArch64`; nixpkgs v2.6 doesn't |
| `fetchSubmodules = true` | Need `xbyak_aarch64` (AArch64 JIT helper) |
| `wxwidgets_3_2` → `wxwidgets_3_3` | Newer cemu requires wxWidgets ≥ 3.3 |
| `fmt_9` → `fmt_11` | Newer cemu uses `fmt::format_string::get()` (fmt ≥ 10) |
| Vendored ROCKNIX patches: NEON intrinsics, online/key path layout, IPO disable, OpenSSL/sharpyuv links | Build/runtime correctness on aarch64 + GCC 15 |
| Install `gameProfiles` and `resources` to `$out/share/Cemu` | Matches ROCKNIX `/usr/share/Cemu`; BOTW needs this for `gameProfiles/default/00050000101c9400.ini` and shared Cafe fonts |
| Drop `-mcmodel=large` from imgui | Incompatible with NixOS default `-fPIC` |
| `-Wno-changes-meaning` | GCC 15 errors on `BackendAArch64.cpp` field-name shadowing |
| `hardeningDisable = [ "fortify" ]` | PCH+fortify interaction |
| `meta.platforms = [ x86_64-linux aarch64-linux ]` | Allow eval on aarch64 |

## ROCKNIX-style candidates

`rocknix-style.nix` layers on top of the default Cemu derivation and adds
ROCKNIX host build semantics where they are safe in Nix:

- explicit `ENABLE_VCPKG=OFF`, `ENABLE_SDL=ON`, `ENABLE_CUBEB=ON`,
  `ENABLE_WXWIDGETS=ON`, `ENABLE_FERAL_GAMEMODE=OFF`, `ENABLE_WAYLAND=ON`,
  `ENABLE_OPENGL=ON`, and `ENABLE_VULKAN=ON` CMake flags;
- `-fpch-preprocess` alongside `-Wno-changes-meaning`;
- the ROCKNIX `find_package(cubeb)` removal and `glm::glm` link-name sed hooks;
- no host `/usr` binds and no host Vulkan loader preload.

Known remaining differences are intentional and must be measured rather than
hidden: Nix glibc/toolchain, RPATH/wrapper behavior, nixpkgs SDL2/sdl2-compat
resolution, and the guest Mesa/Vulkan runtime. The package now installs Cemu's
runtime data directories (`gameProfiles` and `resources`) because the host
ROCKNIX Cemu control run showed BOTW reaching 45 FPS while finding
`gameProfiles/default/00050000101c9400.ini`; missing those directories is not a
valid parity test.

`cemu-rocknix-style-classic-sdl` specifically removes the sdl2-compat/SDL3
variable by replacing that input with `SDL2_classic`. If live BOTW performance
or loading changes materially, SDL compatibility becomes the lead suspect; if
it does not, SDL is ruled out alongside Cemu build flags, affinity, and ROM
storage location.

`cemu-rocknix-faithful` is the stricter candidate to test after resource parity
proved necessary but insufficient. It intentionally differs from the softer
ROCKNIX-style output in three fingerprintable ways:

- removes nixpkgs `cubeb` from build inputs after deleting
  `find_package(cubeb)`, forcing Cemu's bundled Cubeb submodule path like
  ROCKNIX `cemu-sa`;
- disables PIE for executable links with `-DCMAKE_EXE_LINKER_FLAGS=-no-pie`
  plus `NIX_LDFLAGS=-no-pie` to test the host-observed ELF `EXEC` posture
  against the Nix `DYN` candidate;
- fails the build if BOTW's default game profile or Cafe shared font is absent
  from `$out/share/Cemu`.

Before interpreting FPS, fingerprint the candidate against host Cemu:

```sh
CANDIDATE_CEMU=/nix/store/...-cemu-rocknix-faithful-*/bin/Cemu \
  /storage/.guest/remote-cemu-build-fingerprint.sh
```

The faithful candidate is considered a failed parity candidate if the real
wrapped binary still dynamically needs `libcubeb.so.0` or fingerprints as ELF
`DYN` without a documented build reason.

## Direct ROCKNIX package replica

`rocknix-package-manifest.nix` is the local parity manifest for the direct
package. It records the ROCKNIX `cemu-sa/package.mk` source commit, required
patches, pre-configure edits, CMake flags, runtime-data/default-settings
assertions, and the expected bundled-Cubeb/no-dynamic-Cubeb posture.

`rocknix-package.nix` consumes that manifest with a direct `stdenv.mkDerivation`.
It intentionally avoids `pkgs.cemu`, `baseCemu`, `overrideAttrs`,
`wrapGAppsHook3`, nixpkgs' imgui replacement, and nixpkgs' inherited Cemu
`preFixup`. It also carries the SM8550 `settings.xml` default that ROCKNIX
installs to `/usr/config/Cemu`, translated to `$out/share/Cemu/config/SM8550/`
so clean guests can seed settings without overwriting existing user state. Since
Cemu discovers Vulkan with `dlopen` rather than a direct dynamic dependency, the
package records its Vulkan-loader library path for `start_cemu_guest.sh` to add
only for that Cemu process. The package exports build evidence under `$out/nix-support/rocknix-cemu-build/` so
`remote-cemu-build-fingerprint.sh` can show CMake, dependency, Cubeb,
runtime-data, and ELF/linkage posture before FPS is interpreted.

Build and import this output from Fuji or another aarch64 builder when Thor is
available again. Thor is only the live validation target; do not run the heavy
Cemu build there.

## Patch provenance

`000-build-fixes.patch`, `002-opt-seeprom-mlc01-keys-dir.patch`, and
`003-disable-cmake-interprocedural-optimization.patch` are copied verbatim from
`projects/ROCKNIX/packages/emulators/standalone/cemu-sa/patches/`.
If those patches are updated upstream in the ROCKNIX cemu-sa package,
keep these copies in sync and update `rocknix-package-manifest.nix` at the same
time.

## Bumping the cemu commit

1. Pick the new commit from `cemu-project/Cemu` master.
2. Update `rev =` in `flake.nix`.
3. Set `hash = "sha256-AAAA...";` to invalidate.
4. `nix build` → nix prints the correct hash; paste it back.
5. Re-test the build; new errors usually mean dep version drift
   (fmt, wxwidgets, imgui) — bump those overrides as needed.
