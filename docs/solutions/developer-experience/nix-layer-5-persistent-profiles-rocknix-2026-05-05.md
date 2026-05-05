---
title: ROCKNIX Layer 5 persistent Nix profiles for CLI tools
last_updated: 2026-05-05
date: 2026-05-05
category: developer-experience
module: ROCKNIX nix-integration
problem_type: developer_experience
component: tooling
severity: low
applies_when:
  - Layer 4 real Nix is installed on ROCKNIX and CLI tools should persist across SSH sessions
  - Adding diagnostics around Nix profile command precedence or profile health
  - Validating profile-installed tools across reboot on storage-backed /nix
resolution_type: tooling_addition
related_components:
  - nixctl
  - nix-doctor
  - profile.d
  - nix profile
  - SM8550
validated_on:
  device: thor
  os_version: "20260505"
  branch: feat/nix-layer-4-real-store
  nix_version: "2.34.7"
tags: [rocknix, nix, profile, layer-5, sm8550, cli-tools]
---

# ROCKNIX Layer 5 persistent Nix profiles for CLI tools

## Context

Layer 4 made standard single-user Nix work on ROCKNIX, but day-to-day SSH workflows still needed one-off `nix shell` commands unless tools were installed into a persistent profile. Layer 5 validates that standard `nix profile` commands can install CLI tools once, expose them from `${HOME}/.nix-profile/bin`, and preserve them across reboot without changing ROCKNIX boot, UI, or game paths.

## Guidance

Use standard Nix profile commands as the user-facing interface:

```sh
nix profile install nixpkgs#ripgrep
rg --version
nix profile remove ripgrep
```

Do not add a parallel `nixctl profile install` wrapper. `nixctl` remains the lifecycle/status front door and `nix-doctor` remains the health checker.

The shell contract is:

```text
/storage/.nix-profile/bin                  # Layer 5 profile tools
/nix/var/nix/profiles/default/bin          # Layer 4 real Nix
/storage/bin                               # Layer 1/2 portable wrappers + user scripts
/usr/bin:/usr/sbin                         # ROCKNIX base tools
```

`/etc/profile.d/998-nix-integration.conf` must sort after ROCKNIX's `098-busybox`, which resets `PATH`. The filename is part of the contract, not cosmetic.

## Why This Matters

Persistent Nix profiles are the first layer where ROCKNIX gains normal, durable SSH tooling without turning Nix into the base OS. The tradeoff is command precedence: profile tools are intentionally first on `$PATH`, so diagnostics must make shadowing visible without blocking intentional overrides.

## Examples

### Diagnostics added

`nixctl status` now reports:

- `${HOME}/.nix-profile` symlink target
- profile `bin` path
- `nix profile list` entries when real Nix is installed
- profile command conflicts with lower-precedence paths

`nix-doctor --offline` now checks:

- Layer 5 profile symlink health
- profile `bin` existence
- `nix profile list` success
- command shadowing warnings
- storage pressure warning threshold

Expected Nix toolchain shadowing of `/storage/bin/nix*` is intentionally allowlisted. User CLI shadowing, such as a Nix-profile `jq` ahead of `/usr/bin/jq`, remains a warning.

### Hardware validation on thor

Validated on `thor` with ROCKNIX `20260505`, branch `feat/nix-layer-4-real-store`, Nix `2.34.7`.

Install/use/remove smoke:

```sh
LAYER5_SMOKE=1 projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Observed result:

```text
[layer5-smoke] install: nix profile install nixpkgs#hello
[layer5-smoke] verify: binary exists via profile link and fresh profile-sourced shell
[layer5-smoke] diagnostics: nixctl status and nix-doctor report Layer 5 state
[layer5-smoke] cleanup: nix profile remove hello
nix-integration Layer 5 smoke passed
```

Reboot persistence smoke:

```sh
LAYER5_SMOKE=1 LAYER5_REBOOT_VERIFY=prepare projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
reboot
LAYER5_SMOKE=1 LAYER5_REBOOT_VERIFY=verify projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
nix profile remove hello
```

Observed result after reboot:

```text
[layer5-smoke] reboot verify: checking existing profile binary after reboot
nix-integration Layer 5 reboot smoke passed
```

Final doctor result with updated scripts:

```text
OK: Layer 5 profile link: /storage/.nix-profile -> /nix/var/nix/profiles/per-user/root/profile
OK: Layer 5 profile bin exists: /storage/.nix-profile/bin
OK: nix profile list succeeded
OK: Layer 5 profile command conflicts: none detected
nix-doctor: passed with 1 warning(s)
```

The remaining warning is the expected `--offline` network-skip warning.

### Cleanup and recovery

Remove profile tools by name from `nix profile list`:

```sh
nix profile list
nix profile remove hello
```

Delete old generations and collect unreachable store paths explicitly:

```sh
nix profile history
nix profile wipe-history --older-than 30d
nix store gc
```

or, more aggressively:

```sh
nix-collect-garbage -d
```

A full Layer 4 reset also removes Layer 5 tools:

```sh
nixctl uninstall --yes
```

This removes `/nix/store/*`, `/nix/var/*`, `~/.config/nix/`, and `~/.nix-profile`, leaving the Layer 3 bind mount and Layer 1/2 portable wrappers intact.

## When to Apply

- Profile-installed commands intentionally have highest precedence. This is useful for SSH/admin tooling but can shadow ROCKNIX commands.
- Treat `nixctl status` and `nix-doctor --offline` conflict output as the source of truth before installing conflict-prone tools such as `jq`, `python`, `git`, or `grep`.
- Do not use Layer 5 to replace boot/runtime-critical shell utilities unless you are deliberately testing over SSH and have a reflash/recovery path.
- `/tmp` is cleared on reboot, so copied test trees under `/tmp` must be restored before running post-reboot verification scripts.

## Related

- `docs/plans/2026-05-05-001-feat-nix-layer-5-persistent-profiles-plan.md`
- `docs/plans/2026-05-04-001-feat-nix-layer-4-real-store-plan.md`
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
