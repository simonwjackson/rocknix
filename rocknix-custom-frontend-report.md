# ROCKNIX as a foundation for a custom activity-first frontend

## Summary

ROCKNIX is a good lower-level foundation for a custom handheld frontend because it already provides the hard appliance layers: boot, kernel, firmware, hardware quirks, input, audio, Sway/Wayland, emulator packages, ROM/config/save conventions, and launch orchestration.

The best approach is not to fork or replace all of ROCKNIX. The best seam is to replace EmulationStation as the presentation and decision layer while continuing to use ROCKNIX as the emulator runtime and device integration layer.

The target frontend philosophy is activity-first and progressive-disclosure-first:

- start with the last thing the user played
- then recently played
- then pinned/favorite activities
- then search/library
- only expose systems/platforms/cores as secondary detail

This contrasts with the traditional launcher model that starts as a library browser:

```text
system -> game -> emulator/core -> launch
```

For this device, the better model is closer to:

```text
continue -> recent -> pinned -> search -> library details
```

## Device context

Primary target device used during exploration:

```text
Odin2 Portal / SM8550
ROCKNIX nightly
Sway Wayland compositor
EmulationStation frontend
Persistent writable storage at /storage
Immutable base OS mounted read-only
```

ROCKNIX runtime constraints:

- `/` and `/usr` are immutable at runtime.
- `/storage` is writable and persistent.
- custom scripts belong under `/storage/bin` or `/storage/.config`.
- Sway is already running as the compositor on SM8550.
- EmulationStation is just one service layered on top of Sway.

## Layer model

Think of ROCKNIX as a stack:

```text
ROCKNIX base OS
  kernel
  firmware
  hardware quirks
  audio/input/display setup
  systemd services
  storage mounting
  Sway Wayland compositor
  emulator binaries
  emulator wrapper scripts
  ROM/config/save layout
  launch dispatcher
  ─────────────────────────────
  replaceable layer: EmulationStation frontend
```

The custom frontend should sit at the same layer as EmulationStation, not below it.

## What to keep from ROCKNIX

### 1. Hardware and OS integration

Do not replace:

- kernel
- bootloader
- firmware
- hardware quirks
- display setup
- input setup
- audio stack
- storage mounting
- power/performance helpers

These are exactly the things ROCKNIX is useful for.

### 2. Sway / Wayland compositor

On SM8550, ROCKNIX uses Sway. Relevant service model:

```text
sway.service
essway.service
```

The current UI service is controlled through:

```text
/storage/.config/profile.d/090-ui_service
```

Current value observed:

```sh
UI_SERVICE="sway.service essway.service"
```

This means the display server/compositor and frontend are separable. A replacement frontend can keep `sway.service` and replace only `essway.service`/EmulationStation.

### 3. Emulator installation

Emulators are installed into the immutable system image during the ROCKNIX build. The main device-specific emulator selection is in:

```text
projects/ROCKNIX/packages/virtual/emulators/package.mk
```

For SM8550, this includes standalone emulators such as:

```text
aethersx2-sa
azahar-sa
bigpemu-sa
cemu-sa
dolphin-sa
drastic-sa
gopher64-sa
melonds-sa
rpcs3-sa
steam
vita3k-sa
xemu-sa
```

and many RetroArch/libretro cores.

Runtime binaries and defaults usually live under:

```text
/usr/bin
/usr/lib
/usr/config
/usr/share
```

User state and mutable config live under:

```text
/storage/.config
/storage/roms
/storage/roms/bios
/storage/roms/savestates
```

The custom frontend should use this rather than replacing it.

### 4. Launch dispatcher

The most valuable seam is:

```text
/usr/bin/runemu.sh
```

EmulationStation ultimately calls:

```text
/usr/bin/runemu.sh %ROM% -P%SYSTEM% --core=%CORE% --emulator=%EMULATOR% --controllers="%CONTROLLERSCONFIG%"
```

`runemu.sh` handles many details that a custom frontend should not initially duplicate:

- performance mode
- CPU governor
- big/little core selection
- GPU performance mode
- display refresh-rate changes
- fan profile changes
- MangoHud integration
- Bluetooth toggling
- RetroArch vs standalone emulator dispatch
- emulator-specific startup scripts
- Steam/FEX/gamescope paths
- logs
- cleanup after emulator exit
- save backup hooks

The frontend should choose the ROM/system/emulator/core, then delegate launch to `runemu.sh`.

## What to replace

Replace only the user-facing decision/presentation layer:

```text
EmulationStation
```

Do not start by replacing:

```text
runemu.sh
emulator wrappers
Sway
system services
ROM layout
save layout
```

Those can be peeled back later if needed, but replacing them first increases risk without proving the UI thesis.

## Existing metadata to reuse

### System definitions

System/platform definitions are generated at build time and exposed here:

```text
/usr/config/emulationstation/es_systems.cfg
/storage/.config/emulationstation/es_systems.cfg -> /usr/config/emulationstation/es_systems.cfg
```

These define:

- system name
- full display name
- ROM path
- supported file extensions
- platform/theme metadata
- launch command template
- available emulator/core choices
- default emulator/core

A custom frontend can parse this file to understand what systems exist and how to launch content.

### Game metadata

Game metadata lives in gamelist files such as:

```text
/storage/roms/<system>/gamelist.xml
/storage/.config/modules/gamelist.xml
/storage/roms/ports/gamelist.xml
/storage/roms/moonlight/gamelist.xml
```

Useful fields include:

```xml
<playcount>3</playcount>
<lastplayed>20260426T222125</lastplayed>
```

This is enough to build an activity-first home screen without inventing a new database on day one.

## Recommended frontend architecture

Build a custom frontend that:

```text
reads:
  /usr/config/emulationstation/es_systems.cfg
  /storage/roms/**/gamelist.xml
  /storage/.config/modules/gamelist.xml

stores:
  /storage/.config/<frontend-name>/state.json
  /storage/.config/<frontend-name>/pins.json
  /storage/.config/<frontend-name>/history.json
  /storage/.config/<frontend-name>/settings.json

launches:
  /usr/bin/runemu.sh <rom> -P<system> --core=<core> --emulator=<emulator> --controllers="..."
```

The frontend owns:

- ranking
- recency
- progressive disclosure
- visual hierarchy
- input flow
- pinning/favorites
- search
- optional richer metadata
- optional custom activity model

ROCKNIX owns:

- emulator binaries
- emulator config defaults
- launch wrappers
- performance/device quirks
- system update model
- hardware integration

## Suggested UI model

### Home screen

The home screen should not start with system shelves. It should start with intent.

Recommended priority:

1. Continue / last played
2. Recently played
3. Pinned games/apps
4. Active contexts such as Steam, Moonlight, Ports, Chromium, custom web UI
5. Search
6. Library by system/platform
7. Settings/details

Example home hierarchy:

```text
[Continue]
  Big visual card for the last played game/activity

[Recent]
  5-10 recent activities

[Pinned]
  user-selected games/apps/actions

[Explore]
  search, systems, collections, tools
```

The platform/library view still exists, but it is secondary.

### Progressive disclosure principle

The smallest useful question is:

```text
What do you want to continue?
```

Not:

```text
Which console library do you want to browse?
```

Only reveal system, emulator, core, metadata, paths, and settings after the user asks for detail.

## Implementation phases

### Phase 1: Companion frontend

Goal: prove the UX without replacing EmulationStation.

Model:

```text
Sway + EmulationStation continue as normal
custom frontend launches manually or from Tools
frontend reads gamelists
frontend displays Continue/Recent
frontend can launch a selected game through runemu.sh
```

This can be a web UI in Chromium, a native Wayland app, or a simple prototype app.

This is the safest phase because EmulationStation remains the recovery/default UI.

### Phase 2: Alternative frontend service

Goal: boot into the custom frontend while keeping Sway and ROCKNIX underneath.

Model:

```text
sway.service starts
custom-frontend.service starts
EmulationStation service is disabled/replaced
```

This is probably the sweet spot for a real custom device experience.

Requirements:

- SSH recovery remains enabled
- frontend failure should not break Sway permanently
- easy rollback to EmulationStation
- no changes to boot/kernel/firmware

### Phase 3: Own activity index

Goal: stop thinking in ES-native terms internally while still importing ES data.

Build an index from:

```text
/storage/roms/**
/storage/roms/**/gamelist.xml
/usr/config/emulationstation/es_systems.cfg
```

Then maintain custom state:

```text
/storage/.config/<frontend-name>/activity-index.json
/storage/.config/<frontend-name>/history.json
/storage/.config/<frontend-name>/pins.json
```

This allows better ranking than EmulationStation's platform-first model.

Possible ranking signals:

- last played
- play count
- pinned
- recently added
- installed app/tool status
- explicit user preference
- whether the game has save/resume state
- whether the game is local, streamed, Steam, web, or port

### Phase 4: Selective launch control

Goal: peel back `runemu.sh` only where necessary.

Do not start here.

Only replace parts of `runemu.sh` if the frontend needs behavior ROCKNIX cannot provide, such as richer launch lifecycle reporting, progress states, or foreground/background app management.

Even then, prefer wrapping `runemu.sh` before replacing it.

## Lowest-risk proof of concept

Build a prototype that does only this:

1. Parse `/storage/roms/*/gamelist.xml`.
2. Find the game/activity with the newest `<lastplayed>`.
3. Show one fullscreen Continue card.
4. On select, launch that game using `/usr/bin/runemu.sh`.
5. Return to the frontend after the process exits.

This proves the core product thesis:

```text
activity-first launcher on top of ROCKNIX runtime
```

without requiring a full frontend rewrite.

## Important risks

### Launch command reconstruction

`es_systems.cfg` gives the launch command template, but a custom frontend must correctly choose:

- system/platform
- emulator
- core
- ROM path
- controllers config argument

Initially, use default emulator/core values from the generated ES metadata.

### EmulationStation may update gamelists

If EmulationStation remains installed and used sometimes, both ES and the custom frontend may touch metadata.

Early strategy:

- read ES gamelist files
- write custom state separately
- avoid writing back to ES files until necessary

### Fullscreen/focus behavior

ROCKNIX kiosk Sway config is minimal. Games generally open on the active workspace and fullscreen over the frontend.

If using a custom frontend service, verify:

- launch focus
- return focus after emulator exit
- behavior when emulator crashes
- behavior with Steam/FEX/gamescope

### Device controls

EmulationStation has its own input model. A replacement frontend must provide controller navigation and probably touch support.

Do not underestimate this. The frontend experience will succeed or fail on input feel.

### Recovery

Always keep a way back to EmulationStation.

Recommended rollback strategy:

- leave SSH enabled
- keep an EmulationStation restore script under `/storage/bin`
- do not delete ES config
- do not alter boot/kernel/image files

## Practical recommendation

Start by building a companion prototype using the existing ROCKNIX runtime:

```text
custom frontend reads ES/ROM metadata
custom frontend ranks by activity-first rules
custom frontend launches through runemu.sh
EmulationStation remains available
```

If the activity-first UX feels right, then promote it to a replacement service for EmulationStation while keeping Sway and `runemu.sh`.

The key insight is that ROCKNIX is useful as the lower half of the product. The part to reject is not the whole OS. The part to reject is the library-first frontend framing.
