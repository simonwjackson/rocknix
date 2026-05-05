---
title: Fix Steam desktop UI infinite spinner on ROCKNIX ARM64 by recreating the missing client manifest
date: 2026-05-04
category: runtime-errors
module: ROCKNIX Steam ARM64 desktop UI
problem_type: runtime_error
component: tooling
symptoms:
  - Steam desktop UI opens under Sway but stays on an infinite spinner.
  - steamwebhelper starts with buildid=0.
  - Steam logs report "Client version: no bootstrapper found".
  - Steam leaves steamdeck_stable and attempts the missing steam_client_linuxarm64 update channel, which returns HTTP 404.
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [rocknix, steam, arm64, steam-desktop-ui, steamwebhelper, manifest, sway, ports]
---

# Fix Steam desktop UI infinite spinner on ROCKNIX ARM64

## Problem

On ROCKNIX ARM64, standard Steam desktop UI can be launched under the normal Sway display session by stopping EmulationStation and running `steamrtarm64/steam` without `-gamepadui`. The window may appear, but it can remain stuck on an infinite spinner and fail to act as a useful launcher.

This showed up while trying to expose Steam's desktop interface on an AYN Thor/SM8550 device as an alternative to the known-good Gamescope/GamepadUI launch path for Balatro.

## Symptoms

- Steam desktop UI opened, but stayed on an infinite spinner.
- `steamwebhelper` launched in desktop mode (`-uimode=7`) with a zero build id:

  ```text
  steamwebhelper ... -buildid=0 ... -uimode=7 ...
  ```

- Steam logs showed:

  ```text
  Client version: no bootstrapper found
  Client beta changed from 'steamdeck_stable' to ''
  Downloading manifest: https://client-update.fastly.steamstatic.com/steam_client_linuxarm64
  Download failed: http error 404
  DownloadManifest - exhausted list of download hosts
  ```

- Launching with `-steamdeck -steamos3` but without `-gamepadui` still produced desktop mode (`-uimode=7`) but did not fix the missing build metadata.
- Prewarming with ROCKNIX's normal ARM64 bootstrap command (`steam -steamdeck -exitsteam`) verified the install but did not keep the desktop launch from starting as build `0`.

## What Didn't Work

- **Starting desktop Steam directly from Sway**:

  ```bash
  /storage/.local/share/Steam/steamrtarm64/steam \
    -nofriendsui -nochatui \
    -noverifyfiles -nobootstrapupdate \
    -skipinitialbootstrap -norepairfiles
  ```

  This produced desktop UI, but `steamwebhelper` came up with `-buildid=0` and the UI spinner persisted.

- **Relying only on the beta file**:

  ```bash
  printf "steamdeck_stable\n" >/storage/games-internal/roms/steam/package/beta
  ```

  Steam initially reported the beta, but later cleared/changed it and fell into the generic `steam_client_linuxarm64` update path.

- **Adding Steam Deck flags without GamepadUI**:

  ```bash
  steam -steamdeck -steamos3 -nofriendsui -nochatui ...
  ```

  This still used desktop mode (`-uimode=7`), but the webhelper could still start with build metadata missing.

- **Forwarding `steam://rungameid/2379780` to an already-running desktop client**:

  The command was accepted and forwarded, but Balatro did not transition to `App Running` from the desktop UI session. The reliable game launch path remained the Gamescope/GamepadUI flow.

## Solution

Create the missing native ARM64 Steam client manifest before starting desktop Steam. The important file is:

```text
/storage/games-internal/roms/steam/package/steam_client_steamdeck_stable_linuxarm64.manifest
```

It must contain a `version` matching the installed native ARM64 Steam client build. Derive that version from the installed-file list rather than hardcoding it:

```bash
STEAM_ROOT=/storage/games-internal/roms/steam

STEAM_CLIENT_VERSION=$(awk -F"[,;]" \
  'NR == 1 && $3 ~ /^[0-9]+$/ { print $3; exit }' \
  "$STEAM_ROOT/package/steam_client_steamdeck_stable_linuxarm64.installed" \
  2>/dev/null || true)

if [ -z "$STEAM_CLIENT_VERSION" ]; then
  STEAM_CLIENT_VERSION=$(awk -F'"' \
    '/"version"/ { print $4; exit }' \
    "$STEAM_ROOT/package/steam_client_steamdeck_stable_ubuntu12.manifest" \
    2>/dev/null || true)
fi

if [ -n "$STEAM_CLIENT_VERSION" ]; then
  cat >"$STEAM_ROOT/package/steam_client_steamdeck_stable_linuxarm64.manifest" <<EOF
"linuxarm64"
{
	"version"		"$STEAM_CLIENT_VERSION"
}
EOF
fi
```

Then start Steam desktop UI under Sway, not Gamescope, and stop EmulationStation so the Steam window is visible:

```bash
systemctl stop essway 2>/dev/null || true
systemctl start sway 2>/dev/null || true

HOME=/storage \
USER=root \
XDG_RUNTIME_DIR=/var/run/0-runtime-dir \
DBUS_SESSION_BUS_ADDRESS=unix:path=/var/run/0-runtime-dir/bus \
DISPLAY=:0.0 \
WAYLAND_DISPLAY=wayland-1 \
SDL_VIDEODRIVER=x11 \
SDL_AUDIODRIVER=pulseaudio \
LD_LIBRARY_PATH=/storage/.local/share/Steam/lib/aarch64-linux-gnu/ \
/storage/.local/share/Steam/steamrtarm64/steam \
  -nofriendsui \
  -nochatui \
  -noverifyfiles \
  -nobootstrapupdate \
  -skipinitialbootstrap \
  -norepairfiles
```

The fix was persisted in the helper script:

```text
/storage/bin/start_steam_desktop_ui.sh
```

and exposed through the Ports launcher:

```text
/storage/roms/ports/Steam Desktop UI.sh
```

## Why This Works

The native ARM64 Steam install had an installed-file list:

```text
steam_client_steamdeck_stable_linuxarm64.installed
```

but did not have the matching manifest:

```text
steam_client_steamdeck_stable_linuxarm64.manifest
```

Without the manifest, the Steam process could not associate the running native ARM64 client with a non-zero installed version. That made `steamwebhelper` start as:

```text
-buildid=0
```

The desktop shell then behaved like an incomplete or unversioned client: it reported no bootstrapper, switched away from `steamdeck_stable`, and tried the generic `steam_client_linuxarm64` update channel. That channel is not available for this ROCKNIX/Steam Deck ARM64 client path, so it returned HTTP 404 and the UI stayed in a spinner/update state.

After the manifest was recreated, `steamwebhelper` launched with the real build id:

```text
-buildid=1777412796
```

and the desktop UI could finish loading. The version should be derived at launch because Steam updates may change the installed build number.

## Prevention

- Recreate the `steam_client_steamdeck_stable_linuxarm64.manifest` immediately before launching desktop Steam; Steam may clear or rewrite package metadata during startup or update checks.
- Derive the version from `steam_client_steamdeck_stable_linuxarm64.installed` instead of hardcoding a build id.
- Treat desktop Steam on ROCKNIX ARM64 as an experimental utility path, not the primary game launcher. In this session, the known-good Balatro launch path still required Gamescope/GamepadUI:

  ```bash
  /usr/bin/runemu.sh "/storage/.local/share/applications/Balatro.desktop" \
    -Psteam --core=steam --emulator=steam --controllers=""
  ```

- Keep the desktop launcher conservative: do not kill an active Steam game; only restart stale Steam/webhelper/Gamescope processes when no game is running.
- Keep logs for future diagnosis:

  ```text
  /storage/steam-desktop-ui.log
  /storage/steam-desktop-ui-port.log
  /storage/games-internal/roms/steam/logs/bootstrap_log.txt
  /storage/games-internal/roms/steam/logs/webhelper.txt
  ```

## Related Issues

- `docs/solutions/best-practices/rocknix-sm8550-power-profiling-2026-05-04.md` — related Steam/Balatro work on the same ROCKNIX SM8550 device, focused on battery and sysfs power caps rather than Steam UI startup.
- ROCKNIX's `/usr/bin/start_steam.sh` is useful prior art: it shows the split between ARM64 desktop mode (`GAMESCOPE=0`) and Gamescope/GamepadUI mode, and runs `steam -steamdeck -exitsteam` before the desktop path.
