# Layer 14 guest launchers

Shell scripts that run inside the Layer 14 Nix guest (systemd-nspawn).
They invoke nix-built emulators with proper env, settings.xml mutation,
and CPU/GPU governor tuning -- without falling back to host binaries
or gamescope wrappers.

## Files

| Script | What it launches |
|---|---|
| `start_cemu_guest.sh` | Generic cemu launcher (replaces `/usr/bin/start_cemu.sh` on the host). Sets up XDG paths so cemu shares config + saves with host's cemu, then execs the nix-built cemu in fullscreen with the requested ROM. |
| `botw-540p-30-guest.sh` | BOTW at 960x540 / 30 FPS. Mutates `settings.xml` to a conservative profile, tunes CPU caps via `/sys`, calls `start_cemu_guest.sh`. Roughly equivalent to host's `botw-540p-fsr.sh` minus gamescope (cemu fullscreens to sway natively). |

## Differences from the host scripts in `/storage/bin/`

The host scripts in `/storage/bin/botw-*.sh` rely on:

- **gamescope** as a wrapper for FSR upscaling.
  In the guest, gamescope nested-in-sway crashes (xkb config + C++ exception).
  Cemu has its own `-f` fullscreen mode that talks straight to sway, so we drop the wrapper.
- **mangohud** for HUD overlay.
  Mangohud needs lib coupling we have not nix-built yet; deferred.
- **`/usr/bin/start_cemu.sh`** which sources `/etc/profile`, calls
  ROCKNIX-specific helpers (`set_kill`), and runs host's `/usr/bin/cemu`.
  Replaced by `start_cemu_guest.sh` which does the bits cemu actually needs.
- **python3** for `settings.xml` mutation.
  No python in the guest by default; we use sed instead.

CPU/GPU governor writes still target `/sys/devices/system/cpu/cpufreq/`
and `/sys/class/devfreq/`. Both are bound `rw` into the guest by the
nspawn drop-in. Tested working from inside the guest.

## Hard-coded cemu store path

`start_cemu_guest.sh` references the nix-built cemu by its full
`/nix/store/<hash>-cemu-2.999.0/bin/Cemu` path. Update this whenever
the cemu flake is rebuilt with input changes; otherwise the launcher
breaks. The flake's README has the full bump procedure.

A future improvement: read the cemu path from a `nix profile` or a
symlink under `/storage/.guest/profile/bin/Cemu` so the launcher does
not need editing on each cemu rebuild.

## Required nspawn binds

The guest must have these bind-mounts in its drop-in (already added
in `99-tty-binding.conf` as of 2026-05-09):

```
--bind=/storage/.config/Cemu:/storage/.config/Cemu
--bind=/storage/.config/MangoHud:/storage/.config/MangoHud
--bind=/storage/roms/bios:/storage/roms/bios
--bind=/storage/roms             # already present
--bind=/sys/devices/system/cpu/cpufreq   # already present
--bind=/sys/class/devfreq                # already present
```

## Validation status (2026-05-09)

`botw-540p-30-guest.sh` validated end-to-end on AYN Thor:

- Cemu nix build: `wl4g8jjlw6pck4sh4ayah9pdl03z8brp-cemu-2.999.0`
- Window title progressed: "Loading..." → "Cemu 2.999 - FPS: 28.00 [Vulkan] [Generic] [TitleId: 00050000-101c9400] Breath of the Wild [US v208]"
- Cemu CPU: 290% (multi-core PPC recompiler busy)
- All BOTW patches applied; FPS++ graphic pack at 30 FPS active
- No host-binary fallback used at any point
