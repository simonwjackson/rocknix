---
title: handoff: Nix on ROCKNIX layers 3+
type: handoff
status: active
date: 2026-04-28
---

# Handoff: Nix on ROCKNIX layers 3+

This document is written so another LLM or developer can continue the Nix-on-ROCKNIX work without the prior chat history.

## One-sentence summary

ROCKNIX is an immutable handheld Linux distribution; we have working storage-only Nix via `nix-portable`, and the next work is to validate and extend a real persistent `/nix` layer without letting Nix take over ROCKNIX boot, kernel, firmware, updates, or default UI.

## Device and runtime context

Primary test device:

- Device family: `SM8550`
- Product: Odin2 Portal
- SSH target used during this work: `root@192.168.1.104`
- Observed running build: ROCKNIX nightly `20260426`
- Runtime root filesystem: read-only squashfs
- Persistent writable partition: `/storage`
- Root user's home on device: `/storage`
- Default UI must remain EmulationStation/Sway; do not replace it during Nix work.

Important ROCKNIX runtime paths:

- `/storage/bin` is on PATH via ROCKNIX profile setup.
- `/storage/.config/profile.d` is sourced by interactive shells.
- `/storage/.config/system.d` is where ROCKNIX's patched systemd reads persistent user units.
- `/usr` and `/` should be treated as immutable at runtime.

## Current repository branch and commits

Branch:

```text
feat/nix-integration-layers
```

Relevant commits currently on the branch:

```text
adb3f6ca0b feat(nix): add standalone rocknix bootstrap
e2c1ce0ba2 feat(nix): add persistent nix mount layer
892bb3a0f8 feat(nix): package optional integration tooling
a824b2c2b6 feat(nix): support portable dev shells
dec1514468 feat(nix): add portable toolbox layer
```

Known unrelated working-tree item:

```text
AGENTS.md
```

Do not assume that file is part of the Nix work.

## What is already implemented

### Layer 1: portable Nix toolbox

Implemented and validated.

Provides storage-local wrappers:

```text
/storage/bin/nix
/storage/bin/nix-shell
/storage/bin/nix-run
/storage/bin/nix-doctor
```

Uses:

```text
NP_RUNTIME=proot
NP_LOCATION=/storage
/storage/apps/nix-portable/nix-portable
```

Reason for `proot`: the default `nix-portable` namespace mode failed on ROCKNIX with a `/proc/self/setgroups` permission error; `proot` works.

### Layer 2: portable dev shells

Implemented and validated.

Adds:

```text
/storage/bin/nix-dev-shell
/storage/bin/nix-doctor --dev-shell-smoke
```

Validated on-device after reboot with:

```sh
/storage/bin/nix-dev-shell nixpkgs#python3 --command python3 --version
```

Observed result:

```text
Python 3.13.12
```

Also validated:

```sh
/storage/bin/nix-doctor --dev-shell-smoke
```

Observed successful result included:

```text
OK: nix smoke command succeeded: nix (Nix) 2.20.6
OK: dev shell smoke command succeeded: jq-1.8.1
OK: can reach https://cache.nixos.org
nix-doctor: passed with 0 warning(s)
```

### Standalone bootstrap

Implemented:

```text
nix-on-rocknix-bootstrap.sh
```

Purpose: one-file installer/repair script for storage-only Nix on ROCKNIX, useful on devices that do not yet include the optional image package.

It supports:

```sh
./nix-on-rocknix-bootstrap.sh install
./nix-on-rocknix-bootstrap.sh repair
./nix-on-rocknix-bootstrap.sh doctor
./nix-on-rocknix-bootstrap.sh status
./nix-on-rocknix-bootstrap.sh remove
```

It was copied to the test device as:

```text
/storage/nix-on-rocknix-bootstrap.sh
```

It was also copied to another machine at:

```text
zao:~/code/sandbox/nix-on-rocknix/nix-on-rocknix-bootstrap.sh
```

### Layer 3: persistent `/nix` package support

Code is implemented in the repo, but not yet fully validated on-device because it requires a custom ROCKNIX image.

Implemented files:

```text
projects/ROCKNIX/packages/tools/nix-integration/package.mk
projects/ROCKNIX/packages/tools/nix-integration/profile.d/085-nix-integration.conf
projects/ROCKNIX/packages/tools/nix-integration/system.d/nix-storage-setup.service
projects/ROCKNIX/packages/tools/nix-integration/system.d/nix.mount
projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-portable-install
projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-portable-run
projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Build option added:

```text
NIX_INTEGRATION_SUPPORT="${NIX_INTEGRATION_SUPPORT:-no}"
```

in:

```text
projects/ROCKNIX/options
```

Optional package inclusion added in:

```text
projects/ROCKNIX/packages/virtual/image/package.mk
```

Layer 3 intended mount model:

```text
/storage/.nix-root  -> bind mount -> /nix
```

The image package creates an empty `/nix` mountpoint in the immutable image and enables:

```text
nix-storage-setup.service
nix.mount
```

Important note: setting `NIX_INTEGRATION_SUPPORT=yes` inside an SSH session on the device does nothing for Layer 3. That variable must be set while building the ROCKNIX image.

## Known validation so far

Repo-level checks pass:

```sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Expected output:

```text
nix-integration static checks passed
nix-integration runtime smoke passed
```

A full package metadata/build validation was attempted locally but the local harness lacked build dependencies:

```text
bash ./scripts/pkgjson: ***** Please install gcc - run scripts/checkdeps *****
```

Device check confirmed ROCKNIX provides the commands used by the Layer 3 systemd unit:

```text
/bin/mkdir -> busybox
/bin/chmod -> busybox
/usr/bin/mkdir -> busybox
/usr/bin/chmod -> busybox
```

The local host did not have `/bin/mkdir` or `/bin/chmod`, so `systemd-analyze verify` on the host produced irrelevant command-path warnings. Do not treat those host warnings as device failures.

## Hard constraints

Do not:

- turn ROCKNIX into NixOS
- let Nix own boot, kernel, firmware, hardware quirks, or updates
- mutate `/usr` or boot files from runtime scripts
- replace EmulationStation/Sway at boot while validating Nix layers
- treat graphical Nix package success as proof that all graphical Nix packages work
- run untrusted flakes as root during validation

Do:

- keep rollback simple at each layer
- keep `/storage` data safe
- preserve SSH as the recovery path
- keep the storage-only `nix-portable` layer as fallback until standard Nix is proven
- validate one layer at a time with an observable user/operator outcome

## Layer 3 validation plan

Layer 3 is currently the immediate next unvalidated milestone.

### Goal

Prove that a custom ROCKNIX image can boot with `/nix` bind-mounted from persistent storage and that this does not break SSH, Sway, EmulationStation, Steam/FEX, Chromium, or the Layer 1/2 Nix fallback.

### Build requirement

Build a custom SM8550 image with:

```sh
NIX_INTEGRATION_SUPPORT=yes make SM8550
```

If the build system requires explicit project/device variables instead of the make target, use the repository's existing SM8550 build conventions.

### Boot requirement

Boot the resulting image on the Odin2 Portal / SM8550.

Do not copy large Steam/game payloads as part of this validation. Keep the test focused on boot, storage, units, and `/nix` persistence.

### Validate units exist

On the device:

```sh
ls -ld /nix
systemctl status nix-storage-setup.service
systemctl status nix.mount
```

Pass criteria:

- `/nix` exists
- both units are known to systemd
- failures, if any, are isolated to Nix and do not block normal UI/SSH

### Validate `/nix` mount

`findmnt` is not guaranteed to exist on ROCKNIX. Prefer:

```sh
mount | grep ' /nix '
cat /proc/mounts | grep ' /nix '
```

Expected shape:

```text
/storage/.nix-root /nix none ... bind ...
```

### Validate storage backing

```sh
ls -ld /storage/.nix-root
ls -ld /storage/.nix-root/store
ls -ld /storage/.nix-root/var/nix
```

Expected: directories exist and are owned by root with normal searchable directory permissions.

### Validate persistence

```sh
touch /nix/.rocknix-nix-test
reboot
```

Reconnect:

```sh
ls -l /nix/.rocknix-nix-test
rm -f /nix/.rocknix-nix-test
```

Pass criteria: the file survives reboot.

### Validate Layer 1/2 fallback still works

```sh
/storage/bin/nix-doctor --dev-shell-smoke
/storage/bin/nix-dev-shell nixpkgs#python3 --command python3 --version
```

Pass criteria: both succeed after Layer 3 image boot.

### Rollback for Layer 3

Safe rollback options:

1. Boot an image without `NIX_INTEGRATION_SUPPORT=yes`.
2. Disable the units if they are present:

   ```sh
   systemctl disable nix.mount
   systemctl disable nix-storage-setup.service
   reboot
   ```

3. Keep `/storage/.nix-root` until sure nothing needed remains there. Delete only when intentionally reclaiming storage:

   ```sh
   rm -rf /storage/.nix-root
   ```

Layer 3 should be rejected or redesigned if a failed `/nix` mount blocks boot, SSH, storage mounting, Sway, or EmulationStation.

## Layer 4 plan: standard single-user/root Nix

Layer 4 should only start after Layer 3 is validated on a custom image.

### Goal

Run standard Nix directly against real `/nix`, without `nix-portable` or `proot`.

### Why this matters

Layer 2 works, but `proot` is slower and less compatible than real Nix. Layer 4 answers whether ROCKNIX can host normal Nix behavior while ROCKNIX still owns the base OS.

### Initial approach

Create a `nixctl` script as the front door for reporting and switching active Nix layers.

Planned path:

```text
projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl
```

Minimum `nixctl` commands:

```sh
nixctl status
nixctl doctor
nixctl active-layer
nixctl use-portable
nixctl use-standard
```

Do not make standard Nix replace the portable layer automatically. The portable layer must remain a fallback.

### Standard Nix install/evaluation strategy

Do not assume the official installer works unchanged on ROCKNIX. Validate carefully.

Questions to resolve during Layer 4:

- Does the official Nix installer support root/single-user mode cleanly on ROCKNIX?
- Does it require tools missing from the ROCKNIX image?
- Does it assume writable `/etc`, `/usr`, or non-root user homes?
- Does it require sandboxing features unavailable on the device?
- Does it require certificates, DNS tools, shells, or coreutils not present in ROCKNIX?

Expected likely configuration:

- sandbox disabled if unsupported
- substituter: `https://cache.nixos.org`
- trusted public key: standard Nix cache key
- profile path under `/storage` because root home is `/storage`

### Layer 4 validation commands

After standard Nix is installed:

```sh
nix --version
nix eval --expr '1 + 1'
nix run nixpkgs#hello
```

Pass criteria:

- commands do not invoke `/storage/apps/nix-portable/nix-portable`
- commands use real `/nix`
- Nix can download or use cached packages
- ROCKNIX boot/UI/SSH remain unchanged

### Layer 4 failure handling

If standard Nix fails:

- record the exact error
- record whether `/nix` remains healthy
- restore portable wrappers as default
- do not continue to profiles, user environment, apps, or daemon

Stop if standard Nix requires invasive base OS mutation.

## Layer 5 plan: persistent Nix profiles for CLI tools

Layer 5 depends on Layer 4.

### Goal

Install CLI tools once and use them from normal SSH shells after reboot.

Example desired commands:

```sh
nix profile install nixpkgs#ripgrep nixpkgs#fd nixpkgs#jq
rg --version
fd --version
jq --version
```

### Key design issue

ROCKNIX already exposes `/storage/bin` on PATH. Nix profiles typically expose binaries through profile-specific `bin` directories. The integration needs to decide how to expose profile binaries without breaking existing `/storage/bin` scripts.

Likely approach:

- add a profile snippet in `profile.d/085-nix-integration.conf`
- prefer explicit Nix profile PATH entries after critical ROCKNIX paths unless a stronger reason exists
- have `nixctl status` report command-name conflicts

### Conflict examples

Potential conflicts:

- `jq` already exists in ROCKNIX image
- `python`, `git`, `grep`, or other tools may differ from ROCKNIX versions

Do not silently hide ROCKNIX-critical commands.

### Validation

```sh
nix profile install nixpkgs#ripgrep
exec sh -l
rg --version
reboot
rg --version
```

Pass criteria:

- profile tool persists across reboot
- existing `/storage/bin` custom scripts still work
- command precedence is documented

## Layer 6: Nix-managed user environment

Layer 6 is implemented and hardware-validated. It depends on Layer 5.

### Goal

Let Nix manage a narrow set of user-space files under `/storage` without taking ownership of the ROCKNIX base OS.

Allowed managed surfaces:

```text
/storage/bin
/storage/.config/profile.d
/storage/.config/autostart
/storage/.config/system.d only for explicitly opt-in user units
```

Forbidden managed surfaces:

```text
/usr
/flash
/boot
kernel modules
firmware
ROCKNIX package-managed system services
EmulationStation default startup
```

### Required safety model

Implement ownership tracking before activation.

Suggested metadata path:

```text
/storage/.config/nix-integration/owned-files
/storage/.config/nix-integration/backups/
/storage/.config/nix-integration/state
```

Activation must:

- refuse to overwrite user-created files by default
- back up files it replaces
- record every file it owns
- support rollback after partial failure

Implemented script:

```text
projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-layer-activate
```

Implemented front-door and diagnostics:

```text
nixctl user-env status|preflight|activate|deactivate|rollback
nixctl status
nix-doctor --offline
```

Initial supported surfaces are intentionally narrower than the sketch:

```text
/storage/bin
/storage/.config/profile.d
```

Autostart and systemd activation remain deferred until wrapper/profile activation remains boring.

### Validation

Validated on `thor` with `LAYER6_SMOKE=1`:

- activated one managed wrapper and one managed profile snippet
- verified the wrapper ran from a fresh profile-sourced shell
- verified `nixctl status` and `nix-doctor --offline` reported active Layer 6 state
- verified a non-owned conflict target was refused and preserved
- deactivated the managed files cleanly
- prepared reboot persistence, rebooted, verified the managed wrapper after reboot, and cleaned up

Layer 6 state after cleanup:

```text
state: inactive
managed files: 0
```

## Layer 7 plan: Nix-managed apps and UI experiments

Layer 7 can begin after Layer 5, but it is safer after Layer 6.

### Existing evidence

A Nix-launched Chromium test was run from SSH and reportedly worked well on-screen.

The script used on the device:

```text
/storage/chromium.sh
```

It launches Chromium through Layer 2 with Wayland flags and a storage-local profile. This is evidence that some Nix graphical apps can work under ROCKNIX Wayland/Sway, but it is not proof that all graphical apps work.

### Goal

Launch useful Nix-managed applications manually without replacing EmulationStation.

Initial candidates:

- Chromium or browser-like UI experiments
- custom web UI dependencies
- lightweight Wayland apps
- development servers or local tools with a browser frontend

### Rules

- manual launch first
- no boot replacement
- no default UI replacement
- app-specific failures are not base Nix-layer failures
- test GPU, input, touch, audio, and fullscreen separately

### Initial implementation shape

The first Layer 7 control-plane slice adds a browser-like launcher fixture under:

```text
projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/layer7-apps/browser/
```

The fixture is activated through Layer 6 and manages only:

```text
/storage/bin/rocknix-layer7-browser
/storage/.config/profile.d/999-rocknix-layer7-browser
```

Readiness checks require the selected app binary to resolve from the Nix profile or store. A same-named binary from `/usr`, `/bin`, or unrelated `/storage/bin` is not accepted as Layer 7-ready.

Layer 7 status and diagnostics are reported by:

```text
nixctl status
nix-doctor --offline
```

Default runtime smoke checks activation/status/doctor behavior in temporary directories without launching graphics. Hardware validation is opt-in:

```sh
LAYER7_SMOKE=1 projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

### Validation

Layer 7 was validated on `thor` with `nixpkgs#chromium` installed through the standard user profile.

Observed evidence:

```text
LAYER7_SMOKE=1 .../nix-integration-runtime-smoke.sh -> passed
Sway window: about:blank - Chromium, app_id=chromium-browser
binary: /storage/.nix-profile/bin/chromium -> /nix/store/.../bin/chromium
Crashpad database: /storage/.config/nix-apps/layer7/browser/chromium/Crash Reports
LAYER7_REBOOT_VERIFY=verify -> passed
Layer 6 state after cleanup: inactive, managed files: 0
```

For future candidate apps:

```sh
# install the selected app with standard nix profile
# activate the Layer 7 launcher bundle through nixctl user-env
# launch manually over SSH/Sway
# observe on device screen
# exit app
# confirm EmulationStation/Sway recovers or was unaffected
```

Also test relaunch after reboot.

## Layer 8 plan: experimental daemon mode

Layer 8 is intentionally late.

### Goal

Determine whether `nix-daemon` can run safely on ROCKNIX.

### Why late

Daemon mode adds risk:

- systemd socket/service ordering
- build users/groups
- permissions
- more persistent state
- possible conflict with ROCKNIX's trimmed user model
- possible interaction with FEX/Steam and systemd-binfmt

### Do not start until

- Layer 4 standard single-user/root Nix works
- Layer 5 profiles work
- there is a clear reason daemon mode is needed

### Required files if implemented

```text
projects/ROCKNIX/packages/tools/nix-integration/system.d/nix-daemon.service
projects/ROCKNIX/packages/tools/nix-integration/system.d/nix-daemon.socket
```

Potential package changes:

- add build users/groups only if ROCKNIX passwd/group handling supports this safely
- order daemon after `/nix` mount
- keep daemon opt-in

### Validation

```sh
systemctl status nix-daemon.socket
systemctl status nix-daemon.service
nix --version
nix run nixpkgs#hello
```

Pass criteria:

- client talks to daemon
- daemon starts only after `/nix` is mounted
- failure does not block boot, SSH, Sway, EmulationStation, Steam/FEX, or Chromium

### Current validation result

Layer 8 control-plane work landed in `docs/plans/2026-05-05-004-feat-nix-layer-8-daemon-mode-plan.md`: diagnostics, image-time identity gate, opt-in units, lifecycle controls, and opt-in smoke/reboot validation.

On `thor`, the current image reached a No-Go preflight gate:

```text
nix-daemon exists: /nix/var/nix/profiles/default/bin/nix-daemon
nixbld group: missing
build-users-group: empty single-user/root fallback
Layer 8 state: inactive
LAYER8_SMOKE=1: stopped at preflight
```

Decision: keep the Layer 8 repo controls, but do not activate daemon mode on current SM8550 images. Full daemon validation requires an image built with `NIX_DAEMON_SUPPORT=yes` and non-conflicting `nixbld` identities.

## Proposed future layers after Layer 8

These are directional only. They are not implemented and not validated. Each should get its own plan before execution. They preserve the same invariant: ROCKNIX remains the host OS and owns boot, kernel, firmware, default UI startup, Steam/FEX integration, and image updates.

- **Layer 9: NixOS/nspawn guest proof**
  - Goal: run a storage-backed NixOS-ish guest under `systemd-nspawn` with its own `nix-daemon`.
  - Boundary: manual start only; no boot autostart; no host service ownership.
  - Stop rule: any impact on SSH, Sway, EmulationStation, Steam/FEX, host updates, or recovery.

- **Layer 10: managed guest operations**
  - Goal: `nixctl guest status/start/stop/shell/update/rollback`, resource controls, health checks.
  - Boundary: guest must be easy to stop, delete, throttle, and keep idle during gameplay.

- **Layer 11: guest-backed app/service bridges**
  - Goal: opt-in host launchers, ports entries, or socket bridges that call selected guest services/apps.
  - Boundary: ROCKNIX must remain usable with guest stopped; bridges are reversible.

- **Layer 12: declarative host/guest profiles**
  - Goal: reproducible profiles declaring packages, guest services, bridges, launchers, resource limits.
  - Boundary: profiles manage Nix/guest/user-space only; never ROMs, saves, Steam/FEX state, boot, firmware, or base packages.

- **Layer 13: curated capability catalog**
  - Goal: `nixctl catalog enable dev-toolbox` and similar; hardware-validated workflows.
  - Boundary: catalog items must be curated, smoke-tested, and hardware-scoped; not arbitrary internet flakes as root.

Full NixOS replacement remains outside this layered path unless a later requirements/planning pass deliberately reopens hardware ownership. The blocker is not whether Nix can run; it is whether NixOS can safely replace ROCKNIX's device enablement, boot/update flow, graphics/input/audio stack, and Steam/FEX behavior.

## Cross-layer tooling to add

The remaining layers need a single status/control tool.

Recommended script:

```text
projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl
```

Minimum useful output:

```sh
nixctl status
```

Should report:

- active layer: portable, real-store, profile, user-env, app, daemon
- whether `/nix` exists
- whether `/nix` is mounted
- backing path for `/nix`
- whether portable fallback exists
- standard Nix path/version if installed
- profile PATH status
- daemon status if present
- rollback hints for partial installs

This tool should eventually replace scattered manual checks.

## Build-system notes

ROCKNIX build system is complex. It builds a full OS image, not an app.

Important files:

```text
projects/ROCKNIX/options
projects/ROCKNIX/packages/virtual/image/package.mk
projects/ROCKNIX/packages/tools/nix-integration/package.mk
scripts/install
config/functions
```

Systemd units placed in a package `system.d/` directory are copied to:

```text
/usr/lib/systemd/system
```

`enable_service <unit>` creates wanted symlinks based on the unit's `WantedBy=`.

The optional package is gated by:

```text
NIX_INTEGRATION_SUPPORT=yes
```

Do not expect runtime environment variables on the device to affect image contents.

## Known rough edges and future cleanup

### Standalone bootstrap duplication

`nix-on-rocknix-bootstrap.sh` embeds its own copies of runner and doctor logic. That can drift from the package scripts.

Before wide distribution, either:

- make the standalone bootstrap generate from the package scripts, or
- declare the standalone bootstrap as the source of truth for storage-only installs and sync package scripts from it.

### Hardcoded aarch64

Current bootstrap defaults to:

```text
nix-portable-aarch64
```

This is correct for SM8550 but not generic.

Future improvement: derive asset from `uname -m`.

### Pinned nix-portable

Current default:

```text
DavHau/nix-portable v012
af41d8defdb9fa17ee361220ee05a0c758d3e6231384a3f969a314f9133744ea
```

This is intentional for reproducibility and checksum verification. Do not switch to unpinned `latest` by default. Allow explicit overrides for testing newer releases.

### `proot` performance

Layer 1/2 use `proot`, which is slower. This is acceptable for storage-only validation. Layer 4 is where performance-sensitive standard Nix should be evaluated.

### `findmnt` missing

Do not rely on `findmnt` being installed. Use:

```sh
mount | grep ' /nix '
cat /proc/mounts | grep ' /nix '
```

## Recommended next actions

1. Build a custom SM8550 image with `NIX_INTEGRATION_SUPPORT=yes`.
2. Boot it on the device.
3. Validate Layer 3 using the commands in this document.
4. If Layer 3 passes, implement `nixctl status` before attempting standard Nix.
5. Attempt Layer 4 standard single-user/root Nix using `/nix` while preserving the portable fallback.
6. Do not attempt daemon mode until Layer 4 and Layer 5 are useful and stable.
