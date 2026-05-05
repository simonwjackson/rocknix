# Nix experiment on SM8550 ROCKNIX

This document tracks the layered Nix experiment for Odin2 Portal / SM8550.

ROCKNIX remains the base OS. Nix is an additive storage/user-space layer. Do not use Nix to mutate `/usr`, boot files, kernels, firmware, or ROCKNIX-provided services.

## Current supported layer: Layer 3 persistent `/nix` mountpoint

Layer 1 turns the manual `nix-portable` proof-of-concept into a repeatable storage-only toolbox. Layer 2 makes that toolbox useful for practical project and debugging shells. Layer 3 adds optional image-level support for a real `/nix` path backed by persistent storage.

Usable outcome:

- `/storage/bin/nix`
- `/storage/bin/nix-shell`
- `/storage/bin/nix-run`
- `/storage/bin/nix-dev-shell`
- `/storage/bin/nix-doctor`
- install, repair, status, and remove workflows
- storage-only dev shells for CLI and language-runtime tools
- optional `/nix` bind mount backed by `/storage/.nix-root`

Runtime model:

- `nix-portable` binary: `/storage/apps/nix-portable/nix-portable`
- wrapper state: `/storage/apps/nix-portable/`
- user-facing wrappers: `/storage/bin/`
- `NP_RUNTIME=proot`
- `NP_LOCATION=/storage`

`proot` is intentional. On this device, the default nix-portable namespace path failed with a `/proc/self/setgroups` permission error, while `NP_RUNTIME=proot` successfully ran `nix run nixpkgs#hello`.

## Optional image package

Developer images can include the optional `nix-integration` package by building with:

```sh
NIX_INTEGRATION_SUPPORT=yes
```

The package installs only the small control scripts, profile defaults, systemd units, and an empty `/nix` mountpoint into the image. It does not place the nix-portable binary or any Nix store in the read-only system image. Mutable Nix state is still created under `/storage` at runtime.

When the package is present, use:

```sh
nix-portable-install install
```

Without the package, copy or run the scripts from a build tree.

When the package is enabled, these units prepare and mount the persistent `/nix` layer:

- `nix-storage-setup.service`
- `nix.mount`

The bind mount source is `/storage/.nix-root`; the mount target is `/nix`.

## Standalone bootstrap

For a device that does not include the optional image package, copy the standalone bootstrap script to the device and run it:

```sh
scp nix-on-rocknix-bootstrap.sh root@DEVICE_IP:/storage/
ssh root@DEVICE_IP /storage/nix-on-rocknix-bootstrap.sh install
```

It installs or repairs the storage-only wrappers and doctor command without rebuilding ROCKNIX.

## Install or repair Layer 1/2

From a build tree or copied package scripts on the device:

```sh
projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-portable-install install
```

Repair is intentionally the same operation with a clearer name:

```sh
projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-portable-install repair
```

If the optional package is included in the image, the shorter form is available:

```sh
nix-portable-install repair
```

The installer downloads the pinned `DavHau/nix-portable` aarch64 release and verifies its sha256 before activating it.

Pinned artifact:

- version: `v012`
- asset: `nix-portable-aarch64`
- sha256: `af41d8defdb9fa17ee361220ee05a0c758d3e6231384a3f969a314f9133744ea`

## Validate Layer 1

Run:

```sh
/storage/bin/nix --version
/storage/bin/nix run nixpkgs#hello
/storage/bin/nix-doctor
```

Expected smoke output from the hello package:

```text
Hello, world!
```

For offline checks after the first install:

```sh
/storage/bin/nix-doctor --offline
```

For a metadata-only check that does not execute Nix:

```sh
/storage/bin/nix-doctor --offline --no-smoke
```

## Use Layer 2 dev shells

Layer 2 supports both direct `nix shell` and a convenience wrapper:

```sh
/storage/bin/nix shell nixpkgs#jq --command jq --version
/storage/bin/nix-dev-shell nixpkgs#ripgrep --command rg --version
```

For an interactive shell containing multiple tools:

```sh
/storage/bin/nix shell nixpkgs#jq nixpkgs#ripgrep nixpkgs#fd
```

For a language runtime smoke test:

```sh
/storage/bin/nix-dev-shell nixpkgs#python3 --command python3 --version
```

Run a dev-shell health check with:

```sh
/storage/bin/nix-doctor --dev-shell-smoke
```

The default dev-shell smoke uses `nixpkgs#jq`. Override it if needed:

```sh
NIX_DEV_SHELL_SMOKE_PACKAGE=nixpkgs#python3 \
NIX_DEV_SHELL_SMOKE_COMMAND='python3 --version' \
/storage/bin/nix-doctor --dev-shell-smoke
```

`proot` can make shell startup slower than normal Nix. Treat slow first launches and large downloads as expected Layer 2 behavior; treat repeatable package resolution failures as real compatibility problems.

## Validate Layer 3 `/nix`

Layer 3 requires a custom image built with `NIX_INTEGRATION_SUPPORT=yes`. After boot, validate the mountpoint:

```sh
systemctl status nix-storage-setup.service
systemctl status nix.mount
findmnt /nix
```

Expected shape:

```text
/storage/.nix-root on /nix type none (... bind ...)
```

Persistence smoke test:

```sh
touch /nix/.rocknix-nix-test
reboot
ls -l /nix/.rocknix-nix-test
rm -f /nix/.rocknix-nix-test
```

If `nix.mount` fails, ROCKNIX should still boot to the normal UI. Disable the layer by disabling the units or rebuilding without `NIX_INTEGRATION_SUPPORT=yes`.

The portable `nix-portable` wrappers remain the fallback even when `/nix` exists.

## Remove Layer 1/2

```sh
projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-portable-install remove
```

This removes:

- `/storage/bin/nix`
- `/storage/bin/nix-shell`
- `/storage/bin/nix-run`
- `/storage/bin/nix-dev-shell`
- `/storage/bin/nix-doctor`
- `/storage/apps/nix-portable/`

It does not remove unrelated storage data such as SSH config, Chromium experiments, Steam data, ROMs, or user-created scripts.

## Stopping rule for Layer 1/2/3

Stop at Layer 1, 2, or 3 if any of these are true:

- `nix-doctor` cannot pass after repair.
- `nix run nixpkgs#hello` cannot run reliably after reboot.
- a small dev shell such as `nixpkgs#jq` cannot run reliably after repair.
- `/nix` cannot be mounted from `/storage/.nix-root` without blocking boot or UI startup.
- the storage-backed nix-portable state interferes with SSH, Sway, EmulationStation, Steam/FEX, or the existing Chromium launcher.
- storage usage becomes unacceptable and cannot be recovered with normal Nix garbage collection or removal.

## Layer 4: standard single-user Nix on real `/nix`

Layer 4 installs real, root-owned, single-user Nix directly into `/nix` (the storage-backed bind mount established by Layer 3). After install, `nix run`, `nix-shell`, and `nix build` execute against the real `/nix/store` without `nix-portable` or `proot` in the loop. The portable wrappers under `/storage/bin/` remain available for explicit fallback.

### Prerequisites

- Layer 3 active: `/nix` bind-mounted from `/storage/.nix-root` (verify with `mount | grep ' /nix '`)
- Network reachability to `releases.nixos.org` and `cache.nixos.org`
- At least 1 GB free on `/storage`

### Install

```sh
nixctl install
```

This downloads the pinned Nix tarball (Nix 2.34.7 by default), verifies its sha256, runs the upstream installer in single-user mode with overrides for ROCKNIX's read-only `/etc` and busybox `cp`, writes `~/.config/nix/nix.conf` (which on this device is `/storage/.config/nix/nix.conf` since `HOME=/storage`), and probes whether the kernel sandbox works. Both `sandbox = true` and `sandbox = false` are valid outcomes; the installer records which was selected.

First run: ~30-60 seconds depending on cache state. Subsequent re-runs at the same pinned version are no-ops.

### Validate

```sh
nixctl status
nix-doctor --offline
```

Expected from `status`: `installed: yes`, version line, sandbox setting, and a `Layer 3 mount: mounted` line. From `nix-doctor`: a block of `OK` lines including `Layer 4 detected`, `real nix --version`, sandbox parsing, and `${HOME}/.nix-profile -> ...`.

A happy-path smoke:

```sh
hash -r  # so $PATH picks up the new nix binary in this shell
nix --version
nix run nixpkgs#hello
```

The first `nix run nixpkgs#hello` against a cold cache fetches a small closure from `cache.nixos.org` (~10 seconds depending on link speed). Subsequent runs are sub-second.

A dev-shell happy-path:

```sh
nix shell nixpkgs#jq --command jq --version
```

### Upgrade

To bump within the pinned version (rare; usually a no-op):

```sh
NIX_FORCE=1 nixctl install
```

To install a different version, you must export the matching sha256:

```sh
NIX_TARBALL_SHA256=<sha-of-target-version> nixctl upgrade --version 2.35.0
```

The tarball's sha256 can be computed from a download:

```sh
curl -fL https://releases.nixos.org/nix/nix-2.35.0/nix-2.35.0-aarch64-linux.tar.xz \
  | sha256sum
```

### Uninstall

```sh
nixctl uninstall          # interactive (prompts y/N)
nixctl uninstall --yes    # non-interactive
```

Uninstall removes:

- `/nix/store/*`, `/nix/var/*` (recreates empty Layer 3 substrate)
- `~/.config/nix/`
- `~/.nix-defexpr`, `~/.nix-profile`, `~/.nix-channels`

It does **not** touch:

- the Layer 3 bind mount itself (still active)
- `/storage/apps/nix-portable/` or `/storage/bin/nix*` (Layer 1/2 wrappers)
- ROCKNIX system files, configs, or unrelated `/storage` data

### Sandbox notes

If the install probe fails, `nix.conf` will have `sandbox = false`. This is documented in the install output. Some derivations may behave differently under `sandbox = false` (less reproducibility, more access to host filesystem). To retry the probe later (e.g., after a kernel/config change):

```sh
echo 'sandbox = true' >> ~/.config/nix/nix.conf  # try the toggle manually
nix build --expr 'derivation { name = "probe"; system = "aarch64-linux"; builder = "/bin/sh"; args = ["-c" "echo > $out"]; }' --no-link --print-out-paths
```

If the build succeeds, sandbox works; you can leave the setting at `true`. If it fails, revert.

### Troubleshooting

**`which nix` resolves to `/storage/bin/nix` (portable) instead of real nix.** The PATH change in profile.d/998-nix-integration.conf only takes effect on a fresh login shell. Run `hash -r` in your current shell, or open a new SSH session.

**`nix run` complains about missing `nixpkgs`.** You did not register a nixpkgs channel (intentional — Layer 4 install skips channel registration). Use flake URIs (`nixpkgs#hello`) or add a channel manually with `nix-channel --add https://channels.nixos.org/nixpkgs-unstable nixpkgs && nix-channel --update`.

**Real nix install partially failed and left state on disk.** Run `nixctl uninstall --yes` to clear it. If even uninstall fails, the nuclear option is `rm -rf /storage/.nix-root && reboot` (the next boot recreates the empty bind mount via Layer 3's services). Both options are documented as recovery paths in `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`.

**Layer 1/2 wrappers stop working after Layer 4 install.** This should not happen — Layer 4 does not modify `/storage/bin/`. If `/storage/bin/nix` is broken, run `nix-portable-install repair` to rewrite the wrappers.

### Stopping rule for Layer 4

Stop at Layer 4 (do not pursue Layer 5+) if any of these hold:

- The install path cannot complete cleanly on a fresh device after a reasonable number of retries.
- `nix --version` does not consistently resolve to real Nix (PATH ordering broken).
- Real Nix cannot fetch a small package from `cache.nixos.org` reliably.
- The install or uninstall cycle leaves orphaned state under `/storage` that reboot does not clear.
- A workflow that previously worked under Layer 1/2 (portable) regresses under Layer 4 with no clear path to fix.

## Layer 5: persistent Nix profiles for CLI tools

Layer 5 makes real Nix useful as a persistent SSH/admin toolbox. With Layer 4 installed, the root profile link is:

```sh
/storage/.nix-profile -> /nix/var/nix/profiles/per-user/root/profile
```

`/etc/profile.d/998-nix-integration.conf` puts `/storage/.nix-profile/bin` first on `$PATH`, ahead of the Layer 4 real-Nix profile, `/storage/bin`, and ROCKNIX system paths. On the validated SM8550 build, plain `nix profile` commands operate on that same profile link, so installed CLI tools are available in fresh SSH sessions and persist across reboot.

### Install profile tools

Start with low-risk CLI tools whose command names are unlikely to be critical ROCKNIX runtime commands:

```sh
nix profile install nixpkgs#ripgrep nixpkgs#fd nixpkgs#bat
. /etc/profile   # or open a fresh SSH session
rg --version
fd --version
bat --version
```

A minimal smoke package:

```sh
nix profile install nixpkgs#hello
hello
```

### Inspect profile state

```sh
nix profile list
nixctl status
nix-doctor --offline
```

`nixctl status` includes a `Layer 5 (persistent profile) status` block with the profile link, profile `bin` path, profile entries, and command-conflict report. `nix-doctor` treats the expected Nix toolchain shadowing of `/storage/bin/nix*` as healthy, but warns when a profile-installed user command shadows a lower-precedence command.

### Remove or update tools

```sh
nix profile remove ripgrep
nix profile upgrade ripgrep
```

Use the names shown by `nix profile list`. Removing a profile entry creates a new generation; old generations can still keep store paths alive until deleted.

### Garbage collection and disk cleanup

Profiles are GC roots. To remove old generations and collect unreferenced store paths:

```sh
nix profile history
nix profile wipe-history --older-than 30d
nix store gc
```

For a more aggressive cleanup across profiles:

```sh
nix-collect-garbage -d
```

Do not run automatic GC from ROCKNIX boot scripts in this layer; cleanup is an explicit operator action.

### Command conflicts

Profile-installed tools intentionally have highest precedence. This lets you override an SSH/admin tool with a Nix-managed version, but it can also shadow ROCKNIX commands:

```sh
nix profile install nixpkgs#jq
nixctl status
nix-doctor --offline
```

If `jq` already exists lower on `$PATH`, status/doctor report the conflict. This is a warning, not a failure; remove the profile entry if the override is not intended.

Avoid replacing critical shell/runtime commands (`sh`, `busybox`, `systemctl`, core boot utilities) through the profile unless you are deliberately testing over SSH and have a recovery path.

### Layer 5 validation on thor

Validated on `thor` after the Layer 4 image update:

- `nix profile install nixpkgs#hello` created `/storage/.nix-profile/bin/hello`.
- A fresh profile-sourced shell resolved and ran `hello` from the Nix profile.
- `nixctl status` reported the Layer 5 profile block and no unexpected conflicts.
- `nix-doctor --offline` passed with only the expected offline warning.
- Reboot persistence passed: after reboot, `hello` remained on `$PATH` from `/storage/.nix-profile/bin`.
- Cleanup with `nix profile remove hello` returned the profile to the baseline Nix-only entry.

### Uninstall interaction

`nixctl uninstall --yes` is a Layer 4 reset. It removes `/nix/store/*`, `/nix/var/*`, `~/.config/nix/`, and `~/.nix-profile`, so it also removes Layer 5 profile tools. This is intentional: Layer 5 lives on the real `/nix` substrate.

### Stopping rule for Layer 5

Stop at Layer 5 (do not pursue Layer 6+) if any of these hold:

- Plain `nix profile install nixpkgs#hello` does not put the binary under `/storage/.nix-profile/bin`.
- Profile tools do not persist across reboot.
- `nixctl status` or `nix-doctor --offline` cannot distinguish healthy profile state from broken profile state.
- Command shadowing causes ROCKNIX UI, SSH, game runtime, or existing `/storage/bin` recovery tools to regress.
- Store/profile growth cannot be recovered with documented remove/history/GC commands.

## Layer 6: managed user environment under storage

Layer 6 extends beyond profile-installed binaries into a small, reversible file activation model for storage-local user environment files. It does not install packages, replace Home Manager, or manage ROCKNIX system services. Standard `nix profile` remains the package interface; Layer 6 only activates declared files such as wrappers and profile snippets.

Initial supported surfaces:

```text
/storage/bin/<name>
/storage/.config/profile.d/<name>
```

Deferred surfaces:

```text
/storage/.config/autostart.sh
/storage/.config/system.d/<unit>
```

Forbidden surfaces include `/usr`, `/flash`, `/boot`, kernel modules, firmware, ROCKNIX package-managed services, EmulationStation/Sway default startup, ROMs, saves, Steam/FEX state, and browser profiles.

### Activation model

A Layer 6 bundle contains a simple manifest and payload files. The manifest declares the surface, target name, source path inside the bundle, and file mode:

```text
# surface|name|source|mode
bin|rocknix-layer6-smoke|files/bin/rocknix-layer6-smoke|0755
profile.d|999-rocknix-layer6-smoke|files/profile.d/999-rocknix-layer6-smoke|0644
```

Activate manually:

```sh
nixctl user-env preflight /path/to/layer6-bundle
nixctl user-env activate /path/to/layer6-bundle
nixctl status
nix-doctor --offline
```

Deactivate:

```sh
nixctl user-env deactivate
```

Rollback an interrupted activation:

```sh
nixctl user-env rollback
```

State and ownership metadata live under:

```text
/storage/.config/nix-integration/layer6/
```

Layer 6 refuses to overwrite non-owned files by default. Owned files are recorded with checksums and source paths so `nix-doctor` can detect missing targets, external edits, partial activation, and active files whose backing store paths disappeared.

### Validate Layer 6

Default static/runtime checks exercise the activation engine against temporary directories. Hardware validation is opt-in because it writes to real storage surfaces:

```sh
LAYER6_SMOKE=1 projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Optional reboot persistence:

```sh
LAYER6_SMOKE=1 LAYER6_REBOOT_VERIFY=prepare projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
reboot
LAYER6_SMOKE=1 LAYER6_REBOOT_VERIFY=verify projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

`nixctl uninstall --yes` refuses to remove Layer 4 real Nix while Layer 6 is active. Deactivate Layer 6 first so wrappers or snippets that may reference `/nix/store` paths are cleaned up through their ownership metadata.

### Stopping rule for Layer 6

Stop at Layer 6 (do not pursue Layer 7+) if any of these hold:

- Activation cannot refuse non-owned file conflicts reliably.
- Deactivation removes or modifies files not recorded as Layer 6-owned.
- Partial activation cannot roll back or leave a clear doctor-visible failure state.
- Active Layer 6 files survive a Layer 4 reset in a broken state.
- Managed profile snippets or wrappers regress SSH, EmulationStation/Sway, game runtime, or existing `/storage/bin` recovery scripts.

## Layer 7: Nix-managed apps and UI experiments

Layer 7 uses the Layer 4/5 real Nix profile and Layer 6 activation engine to validate manually launched apps or UI dependencies under ROCKNIX Sway. It does not replace EmulationStation, add autostart/systemd integration, or manage broad app state.

Initial contract:

- package install remains standard `nix profile install <package>`
- persistent launchers/snippets are activated through Layer 6 only
- allowed surfaces remain `/storage/bin/<launcher>` and `/storage/.config/profile.d/<snippet>`
- app experiment state/config/cache must live under `/storage/.local/share/nix-apps/layer7/<app>`, `/storage/.config/nix-apps/layer7/<app>`, or `/storage/.cache/nix-apps/layer7/<app>`
- launchers must prove their selected app binary resolves from the Nix profile/store, not `/usr`, `/bin`, or an unrelated `/storage/bin` script

The first fixture is a browser-like launcher bundle:

```text
projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/layer7-apps/browser/
```

It installs these Layer 6-managed files when activated:

```text
/storage/bin/rocknix-layer7-browser
/storage/.config/profile.d/999-rocknix-layer7-browser
```

The default expected app binary is `chromium`, installed through the user Nix profile. The browser launcher includes Chromium's `--no-sandbox` flag because ROCKNIX Nix experiments run as root, and sets `CHROME_CONFIG_HOME` plus `XDG_CONFIG_HOME`/`XDG_CACHE_HOME` to Layer 7 experiment roots so helpers such as Crashpad do not write to the default browser config path. Override during tests or future app experiments with:

```sh
NIX_LAYER7_APP_BIN=<binary> nixctl status
NIX_LAYER7_APP_BIN=<binary> nix-doctor --offline
ROCKNIX_LAYER7_BROWSER_APP=<binary> rocknix-layer7-browser --check
```

### Validate Layer 7

Default static/runtime checks exercise Layer 7 against temporary directories. They do not launch graphical apps:

```sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Hardware validation is opt-in because it writes to real storage surfaces and depends on a profile-installed graphical app:

```sh
nix profile install nixpkgs#chromium
LAYER7_SMOKE=1 projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Optional reboot persistence:

```sh
LAYER7_SMOKE=1 LAYER7_REBOOT_VERIFY=prepare projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
reboot
LAYER7_SMOKE=1 LAYER7_REBOOT_VERIFY=verify projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

The hardware smoke validates launcher activation, Nix-backed binary readiness, `nixctl status`, and `nix-doctor`. Actual visual confirmation remains operator-observed: launch the browser from the active Sway session, verify a visible window, input, exit behavior, and recovery, then document package-specific findings separately from base Nix layer health.

Validated on `thor` with `nixpkgs#chromium`:

```text
LAYER7_SMOKE=1 -> passed
manual Sway launch -> visible "about:blank - Chromium" window, app_id=chromium-browser
binary origin -> /storage/.nix-profile/bin/chromium -> /nix/store/.../bin/chromium
state -> /storage/.local/share/nix-apps/layer7/browser
config/crashpad -> /storage/.config/nix-apps/layer7/browser/chromium/Crash Reports
cache -> /storage/.cache/nix-apps/layer7/browser
LAYER7_REBOOT_VERIFY=verify -> passed
cleanup -> Layer 6 inactive, managed files 0
```

The profile-installed Chromium package remains managed by standard `nix profile`; the Layer 7 smoke only activates/deactivates the storage-local launcher files.

### Stopping rule for Layer 7

Stop at Layer 7 or switch candidates if any of these hold:

- The app requires mutating `/usr`, `/flash`, `/boot`, firmware, kernel modules, ROCKNIX services, ROMs, saves, Steam/FEX state, or existing browser profiles.
- The launcher cannot prove a Nix profile/store-backed binary origin.
- Graphical launch strands SSH, Sway, EmulationStation, Steam/FEX, or recovery.
- App state grows without a clear cleanup path.
- Layer 6 cannot deactivate the launcher cleanly.
- Package-specific Wayland/GPU/audio/input failures dominate and no useful candidate remains.

## Layer 8: experimental daemon mode

Layer 8 remains experimental daemon mode. Do not start it unless single-user/root Nix, persistent profiles, managed activation, and app/UI experiments produce a clear reason to accept daemon complexity.

The first Layer 8 implementation step is diagnostic-only. `nixctl status` reports a Layer 8 section without enabling any service:

```text
Layer 8 (experimental daemon) status
--------------------------------------
  state:      inactive
  eligible:   unsupported: <specific missing prerequisite>
  daemon:     /nix/var/nix/profiles/default/bin/nix-daemon
  socket:     <unit path or missing>
  service:    <unit path or missing>
  sock path:  /nix/var/nix/daemon-socket/socket
  build grp:  <configured build-users-group>
  fallback:   Layer 4 single-user/root Nix remains primary unless daemon is explicitly enabled
```

`nix-doctor --offline` now performs the same feasibility check. Missing daemon prerequisites are warnings while Layer 8 is inactive, because Layers 4-7 are the supported path. If Layer 8 metadata says daemon mode is active, missing daemon binary, units, mount, or build-user configuration becomes a failure with rollback guidance.

Initial stop gates:

- `/nix` must be mounted from storage.
- Layer 4 real Nix must be installed.
- `nix-daemon` must exist in the Nix profile.
- `nix-daemon.socket` and `nix-daemon.service` must be present.
- `build-users-group` must not be the empty single-user/root fallback value.
- The configured build group must exist in `/etc/group`.

Until those gates pass, keep using Layer 4 single-user/root Nix, Layer 5 profiles, Layer 6 activation, and Layer 7 app launchers.

Layer 8 build identities are image-time only. The `nix-integration` package declares an opt-in `NIX_DAEMON_SUPPORT=yes` gate that can add a `nixbld` group and numbered `nixbld*` users through ROCKNIX's existing `add_group`/`add_user` build helpers. Runtime scripts must not invent users or groups under `/storage`. If the image cannot provide non-conflicting daemon build identities, daemon mode should remain unsupported or be explicitly rejected.

The package may ship `nix-daemon.socket` and `nix-daemon.service`, but it must not enable them by default. The units are ordered after `nix.mount`, require `/nix` to be a mount point, and point daemon config at `/storage/.config/nix-daemon` rather than `/etc/nix`. Lifecycle control is explicit through:

```sh
nixctl daemon status
nixctl daemon preflight
nixctl daemon enable
nixctl daemon disable
nixctl daemon rollback
```

`enable` must pass preflight first. `disable` and `rollback` stop daemon units when systemd is available, remove Layer 8 activation metadata under `/storage/.config/nix-integration/layer8`, and leave `/nix` plus Layer 4/5 profile state intact.

Default static/runtime checks do not start the daemon:

```sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Hardware daemon validation is opt-in:

```sh
LAYER8_SMOKE=1 projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Optional reboot persistence:

```sh
LAYER8_SMOKE=1 LAYER8_REBOOT_VERIFY=prepare projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
reboot
LAYER8_SMOKE=1 LAYER8_REBOOT_VERIFY=verify projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

The Layer 8 smoke proves daemon preflight, socket enablement, `NIX_REMOTE=daemon` client communication, a trivial `nixpkgs#hello` run, status/doctor reporting, and cleanup/disable unless `LAYER8_KEEP=1` is set.

Validation on `thor` with the current image reached the Layer 8 safety gate:

```text
nix (Nix) 2.34.7
nix-daemon (Nix) 2.34.7
/etc/group: no nixbld group
/storage/.config/nix/nix.conf: build-users-group = <empty>
```

With Layer 8 units supplied from the test tree, `nixctl daemon status` reported:

```text
state:      inactive
eligible:   unsupported: build-users-group is empty (single-user/root config)
daemon:     /nix/var/nix/profiles/default/bin/nix-daemon
socket:     .../nix-daemon.socket
service:    .../nix-daemon.service
fallback:   Layer 4 single-user/root Nix remains primary unless daemon is explicitly enabled
```

`nix-doctor --offline` passed with Layer 8 warnings because daemon mode was inactive. `LAYER8_SMOKE=1` stopped at preflight as expected:

```text
[layer8-smoke] pre-flight: Layer 8 daemon prerequisites
FAIL: Layer 8 daemon preflight failed
```

No Layer 8 state was left under `/storage/.config/nix-integration/layer8`. Current keep/reject decision: keep the Layer 8 diagnostics, units, and lifecycle controls in the repo, but No-Go daemon activation on current SM8550 images. Full daemon validation requires an image built with `NIX_DAEMON_SUPPORT=yes` and non-conflicting `nixbld` identities.
