# Nix experiment on SM8550 ROCKNIX

This document tracks the custom-image Nix path for Odin2 Portal / SM8550.

ROCKNIX remains the base OS. Nix is an additive storage/user-space layer. Do not use Nix to mutate `/usr`, boot files, kernels, firmware, ROCKNIX-provided services, ROMs, saves, Steam/FEX state, or other base OS ownership boundaries.

## Supported baseline: custom image + persistent `/nix`

The custom image is the starting point. It ships only the small host integration pieces needed for real Nix:

- `/usr/bin/nixctl`
- `/usr/bin/nix-doctor`
- `/usr/bin/nix-layer-activate`
- `/etc/profile.d/998-nix-integration.conf` for Layer 4/5 PATH ordering
- `/nix` mountpoint
- `nix-storage-setup.service`
- `nix.mount`

It does **not** ship nix-portable, proot wrappers, or standalone bootstrap tooling. Older `/storage/bin/nix*` portable wrappers are legacy state and should be removed by `nixctl install` or manually deleted.

The persistent mount is:

```text
/storage/.nix-root -> /nix
```

Build the image with:

```sh
NIX_INTEGRATION_SUPPORT=yes
```

After boot, validate the substrate:

```sh
systemctl status nix-storage-setup.service
systemctl status nix.mount
findmnt /nix || mount | grep ' /nix '
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

## Layer 4: standard single-user Nix on real `/nix`

Layer 4 installs real, root-owned, single-user Nix directly into `/nix` (the storage-backed bind mount established by Layer 3). After install, `nix run`, `nix-shell`, and `nix build` execute against the real `/nix/store`. There is no nix-portable fallback in the image-first path.

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
- `/usr/bin/nixctl`, `/usr/bin/nix-doctor`, or `/usr/bin/nix-layer-activate`
- ROCKNIX system files, configs, or unrelated `/storage` data

### Sandbox notes

If the install probe fails, `nix.conf` will have `sandbox = false`. This is documented in the install output. Some derivations may behave differently under `sandbox = false` (less reproducibility, more access to host filesystem). To retry the probe later (e.g., after a kernel/config change):

```sh
echo 'sandbox = true' >> ~/.config/nix/nix.conf  # try the toggle manually
nix build --expr 'derivation { name = "probe"; system = "aarch64-linux"; builder = "/bin/sh"; args = ["-c" "echo > $out"]; }' --no-link --print-out-paths
```

If the build succeeds, sandbox works; you can leave the setting at `true`. If it fails, revert.

### Troubleshooting

**`which nix` resolves to `/storage/bin/nix` instead of real nix.** That is stale legacy state from older portable experiments. Run `nixctl install` to remove the ambiguous wrapper, then open a fresh shell or run `hash -r`.

**`nix run` complains about missing `nixpkgs`.** You did not register a nixpkgs channel (intentional — Layer 4 install skips channel registration). Use flake URIs (`nixpkgs#hello`) or add a channel manually with `nix-channel --add https://channels.nixos.org/nixpkgs-unstable nixpkgs && nix-channel --update`.

**Real nix install partially failed and left state on disk.** Run `nixctl uninstall --yes` to clear it. If even uninstall fails, the nuclear option is `rm -rf /storage/.nix-root && reboot` (the next boot recreates the empty bind mount via Layer 3's services). Both options are documented as recovery paths in `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`.

### Stopping rule for Layer 4

Stop at Layer 4 (do not pursue Layer 5+) if any of these hold:

- The install path cannot complete cleanly on a fresh device after a reasonable number of retries.
- `nix --version` does not consistently resolve to real Nix (PATH ordering broken).
- Real Nix cannot fetch a small package from `cache.nixos.org` reliably.
- The install or uninstall cycle leaves orphaned state under `/storage` that reboot does not clear.

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

`nixctl status` includes a `Layer 5 (persistent profile) status` block with the profile link, profile `bin` path, profile entries, and command-conflict report. `nix-doctor` warns when a profile-installed user command shadows a lower-precedence command.

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

No Layer 8 state was left under `/storage/.config/nix-integration/layer8`. The Layer 8 safety gate worked as designed for this image.

A second SM8550 image was built from `feat/nix-layer-8-daemon-mode` with `NIX_DAEMON_SUPPORT=yes` and applied to `thor`. After the update:

```text
nixbld + nixbld1..10 present
nix-daemon.socket / nix-daemon.service shipped (disabled by default)
/storage/.config/nix-daemon/nix.conf -> build-users-group = nixbld, sandbox = true
```

Daemon enable + client proof:

```text
nixctl daemon preflight -> passed
nixctl daemon enable    -> socket enabled and active
NIX_REMOTE=daemon nix store ping -> Store URL: daemon, Version: 2.34.7, Trusted: 1
NIX_REMOTE=daemon nix run nixpkgs#hello -> Hello, world!
```

Reboot persistence:

```text
LAYER8_SMOKE=1 LAYER8_REBOOT_VERIFY=prepare ... -> Layer 8 smoke prepared
reboot                                          -> SSH back in ~30s
nix-daemon.socket after reboot                  -> enabled, active
LAYER8_SMOKE=1 LAYER8_REBOOT_VERIFY=verify  ... -> Layer 8 reboot smoke passed
cleanup after verify                            -> daemon disabled, state removed, socket file removed
```

Layer 4 single-user/root Nix remained available as the fallback after disable. SSH, Sway, EmulationStation, Steam/FEX integration, and Chromium/Layer 7 launch behavior were unaffected.

Keep/reject decision: Layer 8 stays in the repo as an opt-in capability. Activate it only on images built with `NIX_DAEMON_SUPPORT=yes`. Default ROCKNIX images continue to use Layer 4 single-user/root Nix.

## Proposed future layers after Layer 8

Layer 9 now has an implementation plan and guest contract:

- Plan: `docs/plans/2026-05-05-005-feat-nix-layer-9-nspawn-guest-proof-plan.md`
- Contract: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer9-nspawn-guest-contract.md`

The Layer 9 boundary is intentionally narrow: preserve `systemd-nspawn` in an opt-in image, stage a guest under `/storage/machines/rocknix-guest`, start it manually for proof, and stop/delete it without affecting host Nix. Fallback means ROCKNIX still boots, SSH remains available, and Layers 4/8 remain usable or recoverable; it does not mean lower layers provide the same NixOS guest capability.

Opt-in hardware smoke shape after a Layer 9-enabled image and pre-staged guest rootfs are present:

```text
LAYER9_SMOKE=1 \
LAYER9_GUEST_ROOT=/storage/machines/rocknix-guest \
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

The smoke is intentionally bounded: it requires an executable `systemd-nspawn`, refuses a missing/non-proof-ready rootfs before starting anything, runs a one-shot guest proof command with `timeout`, verifies no enabled guest unit exists, and fails if a guest process remains after cleanup.

Layer 9 image validation on `thor` found one packaging mistake before the Go image:

```text
run_id=25382377134
BUILD_ID=d68be718902cc45f5fda334c92a45b3be176574e
result: booted, host healthy, but /usr/bin/systemd-nspawn missing
root cause: patched packages/sysutils/systemd/package.mk, but ROCKNIX uses projects/ROCKNIX/packages/sysutils/systemd/package.mk
```

After moving the gate to the ROCKNIX systemd override, the corrected image passed the Layer 9 image-support check:

```text
run_id=25399423558
BUILD_ID=a148296ab771a85a5fbadb6d11e07d37379ad0ae
OS_VERSION=20260506
BUILD_BRANCH=feat/nix-layer-9-nspawn-guest-proof
ABL precheck: abl_a MATCH, abl_b MATCH (no flash)
/usr/bin/systemd-nspawn --version -> systemd 255 (255.8)
/usr/lib/systemd/system/systemd-nspawn@.service -> present
systemctl is-enabled systemd-nspawn@rocknix-guest.service -> disabled
nixctl status -> Layer 9 state: available; guest root missing as expected
nix-doctor --offline -> passed; Layer 9 available; Layers 4/8 healthy
```

Layer 9 manual guest proof then passed with a staged storage-local rootfs assembled from existing on-device Nix closures:

```text
/storage/machines/rocknix-guest/bin/sh -> /nix/store/...-bash.../bin/bash
/storage/machines/rocknix-guest/usr/bin/nix -> /nix/store/...-nix-2.34.7/bin/nix
```

The first nspawn attempt failed as expected for ROCKNIX's trimmed systemd because `machined=false`:

```text
Failed to register machine: The name org.freedesktop.machine1 was not provided by any .service files
```

The smoke path now runs nspawn with `--register=no`. Final proof:

```text
[layer9-smoke] pre-flight: Layer 9 nspawn diagnostics
[layer9-smoke] start: bounded systemd-nspawn guest proof command
layer9-guest-proof
nix (Nix) 2.34.7
[layer9-smoke] cleanup: verify no guest process or enabled guest unit remains
[layer9-smoke] diagnostics: post-proof host Layer 9 status remains readable
nix-integration Layer 9 smoke passed
```

Post-proof status:

```text
Layer 9 state: proof-ready
Layer 9 eligible: available: nspawn guest proof prerequisites present
running: no
fallback: host Layers 4/8 remain the recovery path; guest cleanup must not touch host Nix state
```

Keep/reject decision: Layer 9 is Go for the bounded manual proof. Proceed to Layer 10 only with a separate plan for lifecycle commands, resource controls, freeze/thaw policy, and explicit no-autostart behavior.

Layer 10 now has an implementation plan and lifecycle contract:

- Plan: `docs/plans/2026-05-06-001-feat-nix-layer-10-managed-guest-operations-plan.md`
- Contract: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer10-guest-lifecycle-contract.md`

The Layer 10 boundary separates proof roots from bootable roots. The Layer 9 minimal nix+bash rootfs supports bounded `nixctl guest run` / `nixctl guest shell` style operations, but `nixctl guest start` must refuse it as non-bootable. Long-running guest start/stop is only for a bootable container-style rootfs, remains manual, uses standalone `systemd-nspawn --register=no`, and must not enable a unit by default.

Implemented Layer 10 command surface on the feature branch:

```text
nixctl guest status
nixctl guest preflight
nixctl guest init --proof
nixctl guest import --bootable <artifact>
nixctl guest run <command>
nixctl guest shell
nixctl guest start
nixctl guest stop
nixctl guest cleanup --yes
```

Proof-mode roots support `init --proof`, `run`, `shell`, and `cleanup`. Bootable roots support manual `start`/`stop` through a disabled storage-local unit with conservative defaults:

```text
CPUWeight=1
IOWeight=1
MemoryMax=1G
TasksMax=512
ExecStart=/usr/bin/systemd-nspawn --boot --register=no --directory=/storage/machines/rocknix-guest
```

Layer 10 opt-in hardware smoke modes. Layer 10b-enabled images also package this helper at `/usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh` so hardware validation does not depend on a repo checkout on the device.

```text
LAYER10_SMOKE=proof \
LAYER10_GUEST_ROOT=/storage/machines/rocknix-guest \
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh

LAYER10_SMOKE=bootable \
LAYER10_GUEST_ROOT=/storage/machines/rocknix-guest \
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Current validation status: Layer 10 proof mode is hardware-Go on `thor` as of 2026-05-06.

Validation evidence:

```text
GitHub Actions run: 25422077554
Artifact: ROCKNIX-update-SM8550-20260506
Installed BUILD_ID: d202bf1e14cd3a63bd10d2d447fb3e887533e657
Installed BUILD_BRANCH: feat/nix-layer-10-managed-guest-operations
ABL precheck: abl_a MATCH, abl_b MATCH (no bootloader flash)
Default boot: no running Layer 10 guest, no generated guest unit, autostart disabled
Proof command: nixctl guest run /usr/bin/nix --version -> nix (Nix) 2.34.7
Proof root start guard: nixctl guest start refused proof root as non-bootable
Stale running-state regression: state=running without unit/process evidence reports state: failed
Post-proof status: Layer 10 restored to proof-ready, running: no
```

Bootable-mode `nixctl guest start` / `stop` is implemented but not hardware-Go. Layer 10b adds the missing bootable rootfs path: a pinned NixOS/container-style aarch64 guest source under `projects/ROCKNIX/packages/tools/nix-integration/guest`, `nixctl guest import --bootable <artifact>` with sha256/provenance metadata, root-specific live nspawn evidence for `running`, and a packaged `LAYER10_SMOKE=bootable` helper that refuses to start without provenance. Hardware-Go still requires a rebuilt SM8550 image, a real imported bootable artifact, successful manual start/stop, no enabled unit after reboot, no residual guest process, and healthy host SSH/UI/Nix state. Do not treat proof-mode validation, fixture tests, or import success alone as evidence for long-running guest services, guest SSH, autostart, graphics/audio/input passthrough, or service supervision.

Layer 12 is implemented as the first opt-in guest service layer after Layer 10b: key-only guest SSH on an alternate host port, defaulting to `2222`. Layer 12 must not replace host SSH, bind port `22`, enable password authentication, ship default credentials, autostart the guest, or expose other services. Build pipelining may produce a Layer 12 image before Layer 10b hardware validation completes, but validation and Go/No-Go decisions must remain ordered: Layer 10b first, then Layer 12 on top.

Layer 13 adds declarative modules on top of the validated Layer 10/12 surfaces. Guest modules are real NixOS modules imported into the bootable guest rootfs. ROCKNIX host modules are storage-scoped modules that compile to existing Layer 6/11/12 activation artifacts and must not mutate host system paths. Layer 13 may be batched into the same image build as Layer 10/12 fixes, but Go evidence is still ordered: Layer 10b, then Layer 12, then module workflows.

Layer 12 operator flow after Layer 10b import:

```text
nixctl guest service status
nixctl guest service enable ssh --port 2222 --authorized-keys /storage/.ssh/authorized_keys
nixctl guest start
ssh -p 2222 root@thor /usr/bin/nix --version
nixctl guest stop
```

Layer 12 hardware smoke helper:

```text
LAYER12_SMOKE=ssh \
LAYER12_AUTHORIZED_KEYS=/storage/.ssh/authorized_keys \
LAYER12_SSH_IDENTITY=/storage/.ssh/id_ed25519 \
/usr/lib/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Layer 12 remains pending hardware validation until the Layer 10b image is validated first, then the Layer 12 image proves key-only SSH, clean stop, no port 22 binding, no autostart after reboot, and host SSH continuity.

A narrow Layer 11 live prototype was also performed: a temporary `/storage/bin/layer11-proof` host bridge invoked `nixctl guest run /usr/bin/nix --version`, returned `nix (Nix) 2.34.7`, left Layer 10 at `running: no`, and was deleted. This proves the one-shot bridge shape only; it is not a Go for persistent Layer 11 services.

Layer 11 one-shot bridge implementation is tracked separately:

- Plan: `docs/plans/2026-05-06-002-feat-nix-layer-11-one-shot-guest-bridges-plan.md`
- Contract: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer11-bridge-contract.md`

The first Layer 11 scope may install opt-in wrappers under `/storage/bin` that call fixed proof-mode guest commands through `nixctl guest run` and remove only Layer 11-owned wrapper/metadata state. It must refuse non-owned file conflicts and must leave Layer 10 at `running: no` after each bridge invocation.

Implemented Layer 11 command surface on the feature branch:

```text
nixctl bridge status
nixctl bridge preflight <name>
nixctl bridge install <name> -- <guest-command...>
nixctl bridge run <name>
nixctl bridge remove <name>
```

Layer 11 opt-in hardware smoke mode:

```text
LAYER11_SMOKE=1 \
LAYER11_GUEST_ROOT=/storage/machines/rocknix-guest \
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Current Layer 11 validation status: one-shot bridges are hardware-Go on `thor` as of 2026-05-06.

Validation evidence:

```text
GitHub Actions run: 25447891714
Artifact: ROCKNIX-update-SM8550-20260506
Installed BUILD_ID: d5d5aa3b9812562495f2f94ebc88950f9c7d7d40
Installed BUILD_BRANCH: feat/nix-layer-11-one-shot-guest-bridges
ABL precheck: abl_a MATCH, abl_b MATCH (no bootloader flash)
Default bridge state: bridges: 0, eligible: available
Bridge installed: /storage/bin/layer11-nix-version
Bridge command: /usr/bin/nix --version
Bridge output: nix (Nix) 2.34.7
Post-run Layer 10 status: proof-ready, running: no
nix-doctor --offline: passed with expected pre-existing warnings
Bridge cleanup: wrapper and metadata removed; bridges: 0
Packaged smoke script: not installed in image; manual bridge sequence is the hardware evidence
```

Layer 11 Go applies only to one-shot proof-mode bridges. Persistent services, alternate-port guest SSH, autostart, graphics/audio/input passthrough, and bootable-guest-dependent bridges remain blocked until Layer 10 bootable lifecycle validation passes.

Layer 10 still does not own host SSH, Sway, EmulationStation, Steam/FEX, update, ROM/save state, GPU, audio, or input. Those remain ROCKNIX-owned or later bridge-layer work.

The layer roadmap below records the current boundary. Layers 9, 10 proof mode, and 11 one-shot bridges are implemented and hardware-validated on SM8550; Layer 10b bootable rootfs validation is implemented in-repo and awaits rebuilt-image hardware validation, and Layers 12+ still require separate planning and device validation before Go. ROCKNIX remains the host OS in every case and continues to own boot, kernel, firmware, default UI startup, Steam/FEX integration, and image updates.

- **Layer 9: NixOS/nspawn guest proof.** Run a storage-backed NixOS-ish guest under `systemd-nspawn` with its own `nix-daemon`. Manual start only; no boot autostart; stop rule on any impact to SSH, Sway, EmulationStation, Steam/FEX, host updates, or recovery.
- **Layer 10: managed guest operations.** `nixctl guest status/preflight/init --proof/run/shell/start/stop/cleanup`, resource controls, health checks. Proof mode is hardware-Go; bootable start/stop exists but is not hardware-Go without Layer 10b evidence. Guest must remain easy to stop, delete, throttle, and keep idle during gameplay.
- **Layer 10b: bootable guest rootfs validation.** Implemented in-repo for bootable artifact source, safe import/provenance, stricter root-specific liveness, and packaged bootable smoke. Hardware-Go is pending rebuilt-image validation on `thor` with a real NixOS/container-style rootfs artifact.
- **Layer 11: guest-backed app/service bridges.** Go on `thor` for opt-in one-shot host bridges that call selected proof-mode guest commands and leave no guest running. Persistent services, alternate-port guest SSH, graphics/audio/input, and autostart remain later work after Layer 10b bootable lifecycle is hardware-validated.
- **Layer 12: declarative host/guest profiles.** Reproducible profiles describing packages, guest services, bridges, launchers, and resource limits. Never manage ROMs, saves, Steam/FEX state, boot, firmware, or base packages through them.
- **Layer 13: curated capability catalog.** Hardware-validated, smoke-tested workflows exposed as `nixctl catalog enable <name>`. Not arbitrary internet flakes as root.

Full NixOS on SM8550 is not on the layered path unless a future planning pass deliberately reopens hardware ownership. The blocker is not Nix viability; it is reproducing ROCKNIX's device enablement (Qualcomm boot/update flow, kernel/firmware, GPU/display, controllers/audio, FEX/Steam stack) without losing handheld reliability.
