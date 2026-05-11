# Cemu — ROCKNIX package replica for the Layer 14 Nix guest

This flake builds the promoted Cemu path for the ROCKNIX Layer 14 Nix guest.
The only product output is the direct package replica:

```sh
nix build .#packages.aarch64-linux.cemu-rocknix-package --print-build-logs
# or, equivalently:
nix build .#packages.aarch64-linux.default --print-build-logs
```

Use Fuji or another aarch64 builder for compile-heavy work; Thor is the live
validation target, not the builder.

## Why this exists

ROCKNIX host Cemu is built from upstream commit
`6f6c1299e29fa6e1062ae283a035b4ef787cc397` with ROCKNIX `cemu-sa` patches and
runtime layout. The Layer 14 product goal is to run the same emulator capability
from the Nix guest without depending on host `/usr` libraries, host Vulkan loader
preloads, or broad host cache binds.

The winning implementation is a direct `stdenv.mkDerivation` in
`rocknix-package.nix`, driven by `rocknix-package-manifest.nix`. It does **not**
inherit from `pkgs.cemu`, `baseCemu`, `overrideAttrs`, or `wrapGAppsHook3`.
Earlier override-based candidates (`rocknix-style`, `classic-sdl`, and
`faithful`) were retired after the direct package reached host-like BOTW
performance.

## Outputs

| Output | Purpose |
|---|---|
| `.#default` | Alias for the promoted direct ROCKNIX package replica. |
| `.#cemu-rocknix-package` | Direct package replica used for promotion into `/nix/var/nix/profiles/per-user/root/cemu-promoted`. |

## What the package mirrors

`rocknix-package-manifest.nix` records the ROCKNIX `cemu-sa/package.mk` source
commit, source hash, submodule requirement, copied patches, pre-configure edits,
CMake flags, runtime data assertions, and default SM8550 settings.

`rocknix-package.nix` then builds Cemu directly and installs the runtime shape
expected by the guest launcher and direct package entry point:

- Real Cemu binary under `$out/bin/Cemu`.
- Package-owned entry point under `$out/bin/cemu`; it prepends the package's Nix
  Vulkan loader library path and applies the generic SDL screensaver guard before
  execing `$out/bin/Cemu`.
- `gameProfiles` and `resources` under `$out/share/Cemu`, with generic runtime
  data assertions for default game profiles and Cafe shared fonts. BOTW remains a
  validation workload, not a package build assertion.
- SM8550 default settings under `$out/share/Cemu/config/SM8550/settings.xml` for
  the current compatibility adapter; longer-term this belongs in a guest/device
  profile rather than the generic package surface.
- Build evidence under `$out/nix-support/rocknix-cemu-build/`, including CMake
  flags, ELF/linkage evidence, Cubeb evidence, runtime-data checks, wrapper
  metadata, and `vulkan-loader-lib-path` for Cemu's `dlopen`-based Vulkan loader
  discovery.

## Runtime decision

The promoted path is **Nix Cemu + Nix Vulkan loader + Nix Mesa/Freedreno**.
Same-session BOTW validation showed parity with host Cemu once both launchers
used the same profile and big-core affinity. ROCKNIX Mesa passthrough remains a
diagnostic wrapper for graphics-stack investigations, not the product path.

## Patch provenance

These files are copied verbatim from
`projects/ROCKNIX/packages/emulators/standalone/cemu-sa/patches/`:

- `000-build-fixes.patch`
- `002-opt-seeprom-mlc01-keys-dir.patch`
- `003-disable-cmake-interprocedural-optimization.patch`

If the host `cemu-sa` package changes, update the copied patch and the manifest
in the same commit. Static checks compare the patch copies against the host
package to prevent silent drift.

## Bumping the Cemu commit

1. Update `rev` and `hash` in `rocknix-package-manifest.nix`.
2. Keep `fetchSubmodules = true` unless upstream no longer needs bundled
   submodules.
3. Build on Fuji/aarch64.
4. Import the closure into Thor, run `remote-cemu-build-fingerprint.sh`, then run
   a live same-session host-vs-promoted validation before promotion.
