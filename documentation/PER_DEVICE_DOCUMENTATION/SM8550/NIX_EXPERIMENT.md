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

## Next layer

Layer 5 validates persistent Nix profiles for CLI tools. With Layer 4 in place, `nix profile install <pkg>` deposits binaries into `~/.nix-profile/bin`, which is already on `$PATH` thanks to the profile.d work shipped in Layer 4. Layer 5 is mostly a convention + documentation step rather than new infrastructure.
