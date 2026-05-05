---
title: Manually launch Steam games on ROCKNIX ARM64 without Steam GamepadUI
date: 2026-05-04
last_updated: 2026-05-05
category: best-practices
module: ROCKNIX Steam ARM64 manual game launching
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - Launching a Steam/Proton game manually on ROCKNIX ARM64 from SSH or the desktop Sway session.
  - Keeping Steam desktop UI available while avoiding Steam GamepadUI takeover.
  - Debugging Gamescope, Proton, FEX, Box64, or Steam Runtime launch behavior on SM8550 handhelds.
tags: [rocknix, steam, proton, proton-ge, gamescope, arm64, sway, balatro]
---

# Manually launch Steam games on ROCKNIX ARM64 without Steam GamepadUI

## Context

On ROCKNIX ARM64 handhelds such as AYN Thor/SM8550, the stock Steam launcher path can launch Steam games reliably, but it does so by taking over the display with DRM Gamescope and Steam GamepadUI:

```text
Gamescope owns the display
└── Steam GamepadUI
    └── Steam Runtime / Proton / FEX or Box64
        └── Game.exe
```

That is reliable for Balatro, but it shows Steam's Deck/GamepadUI shell. The goal was to keep Steam desktop mode running under Sway and manually launch Balatro with the Steam Runtime/Proton stack, ideally with Steam UI hidden or in the background.

The working result was a nested Gamescope SDL/X11 path launched from the active Sway session, with Steam desktop UI running in the background as a stabilizing context:

```text
Sway desktop
├── Steam desktop UI running in background (`steamwebhelper ... -uimode=7`)
└── Gamescope SDL/X11 fullscreen window titled "Balatro"
    └── Gamescope internal compositor + Xwayland :1
        └── SteamLinuxRuntime_sniper
            └── Proton compatibility tool (Proton 10.0 or GE-Proton10-34)
                └── Balatro.exe
```

After cold boot, trying to remove the Steam desktop context caused the runtime/Proton child to shut down before a visible Balatro window survived. The stable path is to stop EmulationStation/`essway`, start Steam desktop UI in the background, then launch the nested Gamescope/Runtime/Proton command.

## Guidance

### 1. Start from a working Steam desktop session

Steam desktop mode on ROCKNIX ARM64 should run under Sway, not the stock GamepadUI wrapper. The desktop UI may require the ARM64 manifest fix documented in the related note below. A known-good desktop Steam shape is:

```bash
/storage/.local/share/Steam/steamrtarm64/steam \
  -nofriendsui \
  -nochatui \
  -noverifyfiles \
  -nobootstrapupdate \
  -skipinitialbootstrap \
  -norepairfiles
```

A healthy desktop session shows `steamwebhelper` in desktop mode:

```text
steamwebhelper ... -buildid=1777412796 ... -uimode=7 ...
```

If EmulationStation is covering the desktop, stop `essway` and keep the already-running `sway` session. Avoid restarting Sway while a Gamescope/Proton experiment is wedged; a prior frozen run left Sway in uninterruptible sleep and required reboot.

```bash
systemctl stop essway
systemctl start sway  # only if sway is not already active
```

### 2. Launch from Sway, not a raw SSH display context

Launching nested graphical programs directly from SSH often attaches them to the wrong environment or produces no visible window. Use `swaymsg exec` or a script that re-launches itself into the active Sway session.

Minimum environment for Sway-launched commands:

```bash
export XDG_RUNTIME_DIR=/var/run/0-runtime-dir
export SWAYSOCK=$(ls /var/run/0-runtime-dir/sway-ipc.*.sock | head -1)
export DISPLAY=:0.0
export WAYLAND_DISPLAY=wayland-1
export DBUS_SESSION_BUS_ADDRESS=unix:path=/var/run/0-runtime-dir/bus
```

From SSH, this pattern hands the command to Sway:

```bash
swaymsg -s "$SWAYSOCK" exec "/storage/bin/start_balatro_gamescope_runtime_proton.sh"
```

### 3. Use SteamLinuxRuntime_sniper around Proton on ARM64

Running Proton directly was not enough on Thor:

```bash
/storage/games-internal/roms/steam/steamapps/common/Proton\ 10.0/proton \
  waitforexitandrun \
  /storage/games-internal/roms/steam/steamapps/common/Balatro/Balatro.exe
```

That failed with Wine loader errors such as:

```text
wine: could not load ntdll.so: Cannot dlopen(.../files/lib/wine/ntdll.so)
```

The working manual launch keeps Steam's runtime wrapper in the command:

```bash
/storage/games-internal/roms/steam/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point \
  --verb=waitforexitandrun \
  -- \
  /storage/games-internal/roms/steam/steamapps/common/Proton\ 10.0/proton \
    waitforexitandrun \
    /storage/games-internal/roms/steam/steamapps/common/Balatro/Balatro.exe
```

This produces the same important runtime layer Steam uses internally:

```text
SteamLinuxRuntime_sniper/_v2-entry-point
└── pressure-vessel-wrap / Box64/FEX path
    └── Proton / GE-Proton compatibility tool
        └── Wine
            └── Balatro.exe
```

### 4. Select Proton by the actual `version` file, not by directory name

Manual launchers should treat the compatibility tool path as an explicit per-game setting. On Thor, `/storage/bin/start_balatro.sh` supports this with `BALATRO_PROTON`:

```bash
BALATRO_PROTON="/storage/games-internal/roms/steam/steamapps/common/Proton 10.0/proton" \
  /storage/bin/start_balatro.sh
```

Do not trust the directory name alone. Earlier, `Proton 11.0 (ARM64)` was only a compatibility-tool placeholder symlink to Proton 10.0. That fake symlink was later removed after real Proton 11 and GE-Proton were installed:

```text
Proton 11.0 (ARM64) -> /storage/games-internal/roms/steam/steamapps/common/Proton 10.0
version: 1769167055 proton-10.0-4
```

After installing real Proton 11, the path and version were:

```text
/storage/games-internal/roms/steam/steamapps/common/Proton 11.0/proton
version: 1777025816 proton-11.0-1-beta2
```

That real Proton 11 beta could start the stack and upgrade the prefix, but after a clean reboot Balatro did not reach a running `Balatro.exe` process and appeared to stall around Wine device initialization:

```text
ntsync: up and running
winedevice.exe ... Proton 11.0/files/lib/wine/x86_64-unix/wine
```

GE-Proton10-34 was installable as a separate compatibility tool and did launch Balatro:

```bash
mkdir -p /storage/downloads /storage/games-internal/roms/steam/compatibilitytools.d
cd /storage/downloads
curl -L --fail -O \
  https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-34/GE-Proton10-34.tar.gz
curl -L --fail -O \
  https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-34/GE-Proton10-34.sha512sum
sha512sum -c GE-Proton10-34.sha512sum
tar -xzf GE-Proton10-34.tar.gz \
  -C /storage/games-internal/roms/steam/compatibilitytools.d

BALATRO_PROTON="/storage/games-internal/roms/steam/compatibilitytools.d/GE-Proton10-34/proton" \
  /storage/bin/start_balatro.sh
```

Verified GE-Proton version and process shape:

```text
version: 1774238111 GE-Proton10-34
gamescope ... GE-Proton10-34/proton waitforexitandrun ... Balatro.exe
Balatro.exe ... GE-Proton10-34/files/bin/wine64 ... Balatro.exe
AppID 2379780 state changed : Fully Installed,App Running
```

GE-Proton warned while reusing the same Balatro prefix after Proton 10/11 experiments:

```text
Proton: Upgrading prefix from 10.1000-105 to GE-Proton10-34
Proton: Prefix has an invalid version?! You may want to back up user files and delete this prefix.
```

For quick experiments this was acceptable, but for repeatable testing use a backup or a separate `STEAM_COMPAT_DATA_PATH` per compatibility tool so prefix upgrades do not churn the known-good Balatro prefix.

### 5. Disable Xalia with Proton's real knob

Proton 10 did not honor the earlier guessed variables `PROTON_DISABLE_XALIA=1` or `XALIA_DISABLE=1`. The effective switch is:

```bash
export PROTON_USE_XALIA=0
```

Without it, Balatro could start and then exit with:

```text
System.Exception: x11 not available
  at Xalia.Sdl.SplitOverlayBox.CreateWindows()
```

Keep this in the manual launch environment:

```bash
export PROTON_USE_XALIA=0
export XALIA_SUPPORTED_ONLY=0
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/storage/games-internal/roms/steam
export STEAM_COMPAT_DATA_PATH=/storage/games-internal/roms/steam/steamapps/compatdata/2379780
export SteamAppId=2379780
export SteamGameId=2379780
export STEAM_COMPAT_APP_ID=2379780
export PROTON_LOG=1
export PROTON_LOG_DIR=/storage
export WINEDEBUG=-all
```

### 6. Wrap the runtime/Proton command in nested Gamescope SDL/X11 for a visible window

Direct Steam Runtime + Proton without Gamescope started Balatro briefly, but Sway never saw a visible Balatro/Wine window and the game exited. After cold boot, Steam Runtime + Proton inside Gamescope also exited early when Steam desktop UI was not running. The working visible path was nested Gamescope with the SDL backend forced to X11, launched after Steam desktop UI was initialized in the background:

```bash
BALATRO_GAMESCOPE_BACKEND=sdl \
BALATRO_SDL_VIDEODRIVER=x11 \
/storage/bin/start_balatro_gamescope_runtime_proton.sh
```

The equivalent raw command shape is:

```bash
export SDL_VIDEODRIVER=x11
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/storage/games-internal/roms/steam
export STEAM_COMPAT_DATA_PATH=/storage/games-internal/roms/steam/steamapps/compatdata/2379780
export SteamAppId=2379780
export SteamGameId=2379780
export STEAM_COMPAT_APP_ID=2379780
export PROTON_LOG=1
export PROTON_LOG_DIR=/storage
export PROTON_USE_XALIA=0
export XALIA_SUPPORTED_ONLY=0
export WINEDEBUG=-all

RUNTIME="/storage/games-internal/roms/steam/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point"
PROTON="/storage/games-internal/roms/steam/steamapps/common/Proton 10.0/proton"
GAME="/storage/games-internal/roms/steam/steamapps/common/Balatro/Balatro.exe"

gamescope \
  --backend sdl \
  -W 1920 \
  -H 1080 \
  -w 1920 \
  -h 1080 \
  -r 120 \
  --xwayland-count 1 \
  --force-windows-fullscreen \
  -f \
  -b \
  -- \
  "$RUNTIME" \
    --verb=waitforexitandrun \
    -- \
    "$PROTON" \
      waitforexitandrun \
      "$GAME"
```

Use landscape dimensions for nested Gamescope under Sway. Reusing the DRM/portrait dimensions (`-W 1080 -H 1920`) made Balatro appear around 1:1 scale inside the fullscreen window on Thor's 1920x1080 Sway output.

After launch, Sway should see a visible Xwayland window like:

```text
name='Balatro' class='gamescope' title='Balatro' visible=True
```

Fullscreen it with:

```bash
export XDG_RUNTIME_DIR=/var/run/0-runtime-dir
SWAYSOCK=$(ls /var/run/0-runtime-dir/sway-ipc.*.sock | head -1)

swaymsg -s "$SWAYSOCK" \
  '[title="Balatro" class="gamescope"] focus, fullscreen enable'
```

The verified final state after the landscape update was:

```text
name='Balatro'
class='gamescope'
title='Balatro'
focused=True
visible=True
fullscreen=1
rect={'x': 0, 'y': 0, 'width': 1920, 'height': 1080}
```

## Why This Matters

Manual Steam launching on ROCKNIX ARM64 is not equivalent to desktop Linux x86_64 Steam launching. Several hidden layers matter:

- **Seat/display ownership**: raw SSH is not the active graphical session. DRM Gamescope fails from SSH without the ROCKNIX lifecycle because it cannot open the seat.
- **Steam Runtime**: Proton needs SteamLinuxRuntime/pressure-vessel on this ARM64 stack. Plain `proton waitforexitandrun Game.exe` can fail before Wine loads correctly.
- **Translation layer**: the working stack runs through Box64/FEX-style x86 support. Warnings about wrong ELF class for libraries can be noise if the game continues running.
- **Compatibility tool identity**: directory names and Steam labels can hide symlinks. Check `version` before concluding that a Proton 11 or GE-Proton test actually used that build.
- **Prefix churn**: switching Proton 10, Proton 11, and GE-Proton against the same `compatdata/2379780` prefix can trigger prefix upgrades or invalid-version warnings. Back up or isolate prefixes before broad compatibility testing.
- **Xalia**: Proton 10 enables Xalia by default in this environment; for Balatro, it can crash with `x11 not available` unless `PROTON_USE_XALIA=0` is set.
- **Gamescope backend choice**: `--backend sdl` alone may run audio without a mapped Sway window. For this device/session, `SDL_VIDEODRIVER=x11` made the nested Gamescope window visible to Sway.

The nested SDL/X11 path has more overhead than DRM Gamescope because it adds another compositor and Xwayland layer. For Balatro, the overhead is likely negligible; for heavier games, prefer the native ROCKNIX DRM Gamescope lifecycle if GamepadUI is acceptable.

## When to Apply

- You want to launch a Steam/Proton game manually while keeping Steam desktop mode open under Sway.
- You need to avoid Steam GamepadUI but still use Steam's ARM64 runtime/proton compatibility stack.
- A direct Proton command starts and exits without a visible window.
- Nested Gamescope with Wayland or default SDL gives audio but no visible Sway window.
- You are debugging from SSH and need the command to run inside the active device desktop session.

## Examples

### Verified: GE-Proton10-34 as an ARM64 compatibility-tool experiment

GE-Proton10-34 is not necessary for Balatro when Proton 10.0 works, but it was a useful proof that GE-Proton's ARM64/aarch64 support can run under the same Steam desktop + Sway + Gamescope SDL/X11 pattern on Thor:

```bash
BALATRO_PROTON="/storage/games-internal/roms/steam/compatibilitytools.d/GE-Proton10-34/proton" \
BALATRO_GAME_WIDTH=854 \
BALATRO_GAME_HEIGHT=480 \
BALATRO_GAMESCOPE_SCALER=fit \
BALATRO_GAMESCOPE_FILTER=fsr \
BALATRO_GAMESCOPE_SHARPNESS=5 \
/storage/bin/start_balatro.sh
```

Expected signals:

```text
PROTON_VERSION=1774238111 GE-Proton10-34
ProtonFixes ... All checks successful
Balatro.exe ... GE-Proton10-34/files/bin/wine64 ... Balatro.exe
AppID 2379780 state changed : Fully Installed,App Running
```

Box64 may emit wrong-ELF-class and `winegstreamer.so` symbol warnings. Treat those as suspicious but not fatal if `Balatro.exe` remains alive and the game is visible.

### Partial/failed: real Proton 11 beta2 on Balatro

Real Proton 11 was installed at:

```text
/storage/games-internal/roms/steam/steamapps/common/Proton 11.0/proton
version: 1777025816 proton-11.0-1-beta2
```

It could start the stack and upgrade the prefix, but after reboot it did not produce a stable `Balatro.exe` process. The observed stuck shape was:

```text
gamescope ... Proton 11.0/proton waitforexitandrun ... Balatro.exe
winedevice.exe ... Proton 11.0/files/lib/wine/x86_64-unix/wine
ntsync: up and running
```

For Balatro on this Thor build, keep Proton 10.0 or GE-Proton10-34 as the working manual-launch options until Proton 11 is retested with a clean prefix.

### Known-good stock ROCKNIX path: reliable but shows GamepadUI

```bash
/usr/bin/runemu.sh "/storage/.local/share/applications/Balatro.desktop" \
  -Psteam --core=steam --emulator=steam --controllers=""
```

The underlying shape includes GamepadUI:

```text
gamescope --backend drm ... -- \
  /storage/.local/share/Steam/steamrtarm64/steam \
    -steamdeck -steamos3 -gamepadui \
    -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles \
    steam://rungameid/2379780 \
    -silent
```

This reliably transitions Steam to:

```text
AppID 2379780 state changed : Fully Installed,App Running
```

but the user sees Steam GamepadUI during launch.

### Failed: raw DRM Gamescope over SSH

```bash
gamescope --backend drm -- ...
```

Fails because the SSH process does not own the graphical seat:

```text
No backend was able to open a seat
Failed to initialize Wayland session
Failed to create backend.
```

Use ROCKNIX's lifecycle (`systemd-run --scope`, stop Sway, start DRM Gamescope, restore `essway`) for direct DRM takeover.

### Failed: Steam desktop URL launch

From desktop Steam, these did not reliably launch Balatro on this ARM64 build:

```bash
/storage/.local/share/Steam/steamrtarm64/steam -applaunch 2379780
/storage/.local/share/Steam/steamrtarm64/steam steam://rungameid/2379780
```

Desktop Steam stayed usable after the ARM64 manifest fix, but `rungameid` did not consistently transition Balatro to a visible running game.

### Failed: direct Proton without Steam Runtime

```bash
"/storage/games-internal/roms/steam/steamapps/common/Proton 10.0/proton" \
  waitforexitandrun \
  "/storage/games-internal/roms/steam/steamapps/common/Balatro/Balatro.exe"
```

Representative failure:

```text
wine: could not load ntdll.so
```

### Failed: dropping Steam desktop context after cold boot

After reboot, the following path was tried with EmulationStation stopped and no Steam desktop UI running:

```text
Sway
└── Gamescope SDL/X11
    └── SteamLinuxRuntime_sniper
        └── Proton 10.0
            └── Balatro.exe
```

Gamescope initialized, but the primary child shut down before a stable visible game window remained:

```text
launch: Primary child shut down!
terminate called without an active exception
Gamescope+Runtime+Proton command exited: 134
```

Starting Steam desktop UI first restored the stable launch path. This suggests desktop Steam initializes or keeps alive Steam/FEX/runtime/session state that the manual Runtime+Proton command relies on, even though Steam GamepadUI is not used.

### Partial: Steam Runtime + Proton without Gamescope

This got farther after adding the runtime and `PROTON_USE_XALIA=0`:

```bash
SteamLinuxRuntime_sniper/_v2-entry-point -- Proton 10.0/proton waitforexitandrun Balatro.exe
```

It could briefly show:

```text
AppID 2379780 state changed : Fully Installed,App Running
Balatro.exe
```

but Sway never mapped a visible Balatro window and the process exited after a few seconds.

### Failed/partial: nested Gamescope backend variants

Observed backend behavior:

| Backend | Result |
|---|---|
| `--backend wayland` | Aborted during Gamescope input/window setup in earlier tests. |
| `--backend sdl` with `SDL_VIDEODRIVER` unset | Game/audio could run, but no Sway-managed Gamescope window appeared. |
| `--backend sdl` with `SDL_VIDEODRIVER=wayland` | Still no visible Sway window in this session. |
| `--backend sdl` with `SDL_VIDEODRIVER=x11` | Working: Sway mapped a `class=gamescope`, `title=Balatro` window that could be focused and fullscreened. Use landscape `-W 1920 -H 1080 -w 1920 -h 1080` under Sway. |

Representative nested Wayland failure:

```text
xdg_backend: Couldn't create Wayland input objects.
xdg_backend: Failed to initialize input thread
SDL_Vulkan_CreateSurface failed: VK_KHR_xlib_surface extension is not enabled
terminate called without an active exception
```

### Useful diagnostics

Check whether the game and runtime are alive:

```bash
ps -A -o pid,stat,comm,args | \
  grep -Ei 'gamescope|Balatro.exe|SteamLinuxRuntime|Proton 10.0|Proton 11.0|GE-Proton|pressure-vessel|steamrtarm64/steam|steamwebhelper' | \
  grep -v grep
```

Check Steam's app state:

```bash
grep "AppID 2379780 state changed" \
  /storage/games-internal/roms/steam/logs/content_log.txt | tail -20
```

Check the manual launch log:

```bash
tail -200 /storage/balatro-gamescope-runtime-proton.log
```

Inspect Sway windows:

```bash
export XDG_RUNTIME_DIR=/var/run/0-runtime-dir
SWAYSOCK=$(ls /var/run/0-runtime-dir/sway-ipc.*.sock | head -1)
swaymsg -s "$SWAYSOCK" -t get_tree
```

## Related

- `/storage/bin/start_balatro.sh` — current canonical Thor Balatro launcher script. It self-relaunches inside Sway, accepts `BALATRO_PROTON`, uses `PROTON_USE_XALIA=0`, forces Gamescope SDL/X11, and supports Gamescope resolution/FSR overrides.
- `/storage/games-internal/roms/steam/compatibilitytools.d/GE-Proton10-34` — installed GE-Proton compatibility tool verified with Balatro on Thor.
- `/storage/bin/start_steam_desktop_ui.sh` — background Steam desktop context launcher; recreates the ARM64 manifest before startup.
- `docs/solutions/runtime-errors/steam-desktop-ui-arm64-manifest-spinner-rocknix-2026-05-04.md` — prerequisite fix for making Steam desktop UI usable under Sway on ROCKNIX ARM64.
- `docs/solutions/best-practices/rocknix-sm8550-power-profiling-2026-05-04.md` — power and battery tuning for the same Thor/SM8550 Steam/Balatro workload.
