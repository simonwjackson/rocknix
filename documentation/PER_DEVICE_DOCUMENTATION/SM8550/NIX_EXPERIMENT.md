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

## Next layer

Layer 4 validates standard single-user/root Nix directly on the real `/nix` store, without nix-portable virtualization. Do not attempt daemon mode until standard single-user Nix has a clear pass/fail result.
