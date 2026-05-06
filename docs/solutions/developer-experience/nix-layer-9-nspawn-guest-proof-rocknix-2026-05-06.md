---
title: ROCKNIX Layer 9 systemd-nspawn guest proof
date: 2026-05-06
last_updated: 2026-05-06
category: developer-experience
module: ROCKNIX nix-integration
problem_type: developer_experience
component: tooling
severity: medium
applies_when:
  - Proving a storage-backed guest can run under systemd-nspawn on ROCKNIX
  - ROCKNIX must remain the host OS and own boot, UI, firmware, and updates
  - Layer 9 diagnostics report nspawn availability and a staged guest rootfs
resolution_type: tooling_addition
related_components:
  - nixctl
  - nix-doctor
  - systemd-nspawn
  - SM8550
  - Nix
tags: [rocknix, nix, layer-9, nspawn, systemd, sm8550]
---

# ROCKNIX Layer 9 systemd-nspawn guest proof

## Context

Layer 8 proved host-side `nix-daemon` can run safely when the image supplies build identities and daemon units. Layer 9 asks a different question: can ROCKNIX keep owning the host while a storage-backed guest runs under `systemd-nspawn` for NixOS-like/userland experiments?

The answer on `thor` is yes for the bounded proof: a Layer 9-enabled image can preserve `/usr/bin/systemd-nspawn`, diagnostics can detect the capability, and a staged guest rootfs can run a one-shot Nix proof without leaving a guest process or enabled unit behind.

## Guidance

Preserve `systemd-nspawn` in the ROCKNIX systemd package override, not the global systemd package:

```text
projects/ROCKNIX/packages/sysutils/systemd/package.mk
```

The initial patch accidentally changed `packages/sysutils/systemd/package.mk`. The image still booted and host Nix remained healthy, but `/usr/bin/systemd-nspawn` was missing because ROCKNIX uses its project override. This is a safe failure mode — the host remains usable — but it costs a full CI build and device update cycle.

Because ROCKNIX builds systemd with `machined=false`, standalone nspawn must avoid machined registration:

```text
systemd-nspawn --register=no --directory=/storage/machines/rocknix-guest ...
```

Without `--register=no`, the proof fails with:

```text
Failed to register machine: The name org.freedesktop.machine1 was not provided by any .service files
```

Before building a validation image, make static checks assert the exact project override and runtime flag:

```text
projects/ROCKNIX/packages/sysutils/systemd/package.mk contains NIX_NSPAWN_SUPPORT
projects/ROCKNIX/packages/sysutils/systemd/package.mk conditionally removes systemd-nspawn
nix-integration-runtime-smoke.sh invokes systemd-nspawn with --register=no
```

## Why This Matters

Layer 9 should not widen the host blast radius. The successful shape is a manually started proof that uses storage-local guest state, leaves no boot dependency, and does not require GPU/audio/input passthrough.

Fallback is also now precise: if the guest fails, the host remains normal and Layers 4/8 remain usable or recoverable. Lower layers do not provide equivalent NixOS-guest functionality; they provide host recovery and cleanup boundaries.

## Examples

Corrected image validation:

```text
run_id=25399423558
BUILD_ID=a148296ab771a85a5fbadb6d11e07d37379ad0ae
OS_VERSION=20260506
BUILD_BRANCH=feat/nix-layer-9-nspawn-guest-proof
ABL precheck: abl_a MATCH, abl_b MATCH (no flash)
/usr/bin/systemd-nspawn --version -> systemd 255 (255.8)
systemd-nspawn@rocknix-guest.service -> disabled
nix-doctor --offline -> passed; Layer 9 available; Layers 4/8 healthy
```

Guest rootfs staging used existing on-device Nix closures for a bounded proof:

```text
/storage/machines/rocknix-guest/bin/sh -> /nix/store/...-bash.../bin/bash
/storage/machines/rocknix-guest/usr/bin/nix -> /nix/store/...-nix-2.34.7/bin/nix
```

Opt-in smoke:

```text
LAYER9_SMOKE=1 \
LAYER9_GUEST_ROOT=/storage/machines/rocknix-guest \
LAYER9_TIMEOUT=45 \
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Observed proof:

```text
[layer9-smoke] pre-flight: Layer 9 nspawn diagnostics
[layer9-smoke] start: bounded systemd-nspawn guest proof command
/etc/localtime does not point into /usr/share/zoneinfo/, not updating container timezone.
layer9-guest-proof
nix (Nix) 2.34.7
[layer9-smoke] cleanup: verify no guest process or enabled guest unit remains
[layer9-smoke] diagnostics: post-proof host Layer 9 status remains readable
nix-integration Layer 9 smoke passed
```

Post-proof status:

```text
Layer 9 (nspawn guest proof) status
------------------------------------
  state:      proof-ready
  eligible:   available: nspawn guest proof prerequisites present
  nspawn:     /usr/bin/systemd-nspawn
  guest root: /storage/machines/rocknix-guest
  running:    no
  fallback:   host Layers 4/8 remain the recovery path; guest cleanup must not touch host Nix state
```

## When to Apply

- Use this pattern for bounded, manual nspawn proof work on ROCKNIX.
- Keep `--register=no` unless machined is deliberately added back to the image.
- Do not add autostart, lifecycle commands, graphical passthrough, audio passthrough, or input passthrough in Layer 9.
- Move to a separate Layer 10 plan before adding `nixctl guest` lifecycle, resource limits, freeze/thaw policy, or a persistent disabled unit.

## Prevention

- Patch project overrides first when ROCKNIX has one. For systemd on this branch, the active file is `projects/ROCKNIX/packages/sysutils/systemd/package.mk`, not the global `packages/sysutils/systemd/package.mk`.
- Let static checks name project-specific package paths so the wrong-file patch fails locally before CI.
- Treat `machined=false` as part of the nspawn contract. Standalone proof commands should include `--register=no`; `machinectl` and machined registration are not available.
- Validate image support before staging guests: `/usr/bin/systemd-nspawn --version`, disabled `systemd-nspawn@rocknix-guest.service`, no nspawn processes, and `nix-doctor --offline` Layer 9 status.
- Keep guest proof state removable: `/storage/machines/rocknix-guest` can be deleted without touching host `/nix`, profiles, Layer 6, or Layer 8.

## Related

- `docs/plans/2026-05-05-005-feat-nix-layer-9-nspawn-guest-proof-plan.md`
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer9-nspawn-guest-contract.md`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- `docs/solutions/developer-experience/nix-layer-8-daemon-mode-rocknix-2026-05-05.md`
