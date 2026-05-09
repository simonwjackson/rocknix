# cemu (Wii U emulator) — aarch64 nix flake

Native aarch64-linux build of cemu for the Layer 14 Nix guest.

## Why this exists

`nixpkgs#cemu` is `x86_64-linux` only — it pins to cemu v2.6, which
predates the upstream `BackendAArch64` JIT backend.

ROCKNIX (the host system) builds cemu from upstream commit
`6f6c1299e29fa6e1062ae283a035b4ef787cc397` (2026-04-22), which has
the AArch64 backend. We re-use the same commit and ROCKNIX's vendored
patches, layered on top of `nixpkgs#cemu`'s derivation.

This means cemu can run **inside the Layer 14 nspawn guest** with all
dependencies coming from `/nix/store` — no `/host/lib`, no overlay
mounts, no loader-symlink swap.

## Build

```sh
nix build .#packages.aarch64-linux.cemu --print-build-logs
```

First build takes ~10 min on a 4-core aarch64 host (fuji-class). All
subsequent builds are cache hits unless inputs change.

## What this flake does on top of `nixpkgs#cemu`

| Layer | Why |
|---|---|
| Pin to ROCKNIX upstream commit `6f6c1299` | Has `BackendAArch64`; nixpkgs v2.6 doesn't |
| `fetchSubmodules = true` | Need `xbyak_aarch64` (AArch64 JIT helper) |
| `wxwidgets_3_2` → `wxwidgets_3_3` | Newer cemu requires wxWidgets ≥ 3.3 |
| `fmt_9` → `fmt_11` | Newer cemu uses `fmt::format_string::get()` (fmt ≥ 10) |
| Vendored ROCKNIX patches: NEON intrinsics, IPO disable, OpenSSL/sharpyuv links | Build correctness on aarch64 + GCC 15 |
| Drop `-mcmodel=large` from imgui | Incompatible with NixOS default `-fPIC` |
| `-Wno-changes-meaning` | GCC 15 errors on `BackendAArch64.cpp` field-name shadowing |
| `hardeningDisable = [ "fortify" ]` | PCH+fortify interaction |
| `meta.platforms = [ x86_64-linux aarch64-linux ]` | Allow eval on aarch64 |

## Patch provenance

`000-build-fixes.patch` and `003-disable-cmake-interprocedural-optimization.patch`
are copied verbatim from
`projects/ROCKNIX/packages/emulators/standalone/cemu-sa/patches/`.
If those patches are updated upstream in the ROCKNIX cemu-sa package,
keep these copies in sync.

## Bumping the cemu commit

1. Pick the new commit from `cemu-project/Cemu` master.
2. Update `rev =` in `flake.nix`.
3. Set `hash = "sha256-AAAA...";` to invalidate.
4. `nix build` → nix prints the correct hash; paste it back.
5. Re-test the build; new errors usually mean dep version drift
   (fmt, wxwidgets, imgui) — bump those overrides as needed.
