# Layer 14 guest launchers

Shell scripts that run inside the Layer 14 Nix guest (systemd-nspawn).
They invoke nix-built emulators with proper env, settings.xml mutation,
and CPU/GPU governor tuning -- without falling back to host binaries
or gamescope wrappers.

## Files

| Script | Role |
|---|---|
| `start_cemu_guest.sh` | Generic cemu launcher. Replaces `/usr/bin/start_cemu.sh` for use inside the guest. Sets up XDG paths so the nix-built cemu shares config + saves with host's cemu, then execs cemu in fullscreen with the requested ROM. |
| `botw-guest.sh <profile>` | Parametric BOTW launcher. One profile per resolution / FPS combo. Mutates `settings.xml` via sed, tunes CPU/GPU sysfs, calls `start_cemu_guest.sh`, then blocks until cemu exits. Replaces all 11 host `/storage/bin/botw-*.sh` scripts. |
| `games-launcher.sh` | Touch-friendly fuzzel menu pinned to DSI-1 (Thor's bottom panel). Loops forever -- when the chosen launcher exits, the menu reopens. Bound to `Mod+G` and auto-started by the dev-env sway profile. |

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
  Nested gamescope under sway crashes (xkb config + C++ exception). Cemu's `-f` already fullscreens to sway, so we drop the wrapper. Cemu's own resolution graphic-pack option still controls internal render res.
- **mangohud** for HUD overlay.
  Deferred until packaged as nix.
- **`/usr/bin/start_cemu.sh`** with `set_kill`, `/etc/profile`, etc.
  Replaced by `start_cemu_guest.sh`.
- **python3** for `settings.xml` mutation.
  Replaced by sed.

CPU/GPU sysfs writes still target `/sys/devices/system/cpu/cpufreq/`
and `/sys/class/devfreq/`, both bind-mounted into the guest by the
nspawn drop-in. Failures on read-only sysfs paths are non-fatal -- the
host's defaults remain in effect.

## Cemu store path coupling

`start_cemu_guest.sh` references the nix-built cemu by its full
`/nix/store/<hash>-cemu-2.999.0/bin/Cemu` path. Update on every
flake rebuild that changes inputs.

Future improvement: read it from a `nix profile` symlink under
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
