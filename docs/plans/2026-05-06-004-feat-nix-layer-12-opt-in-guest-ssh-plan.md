---
title: feat: Add Layer 12 opt-in guest SSH service
type: feat
status: implemented-pending-hardware-validation
date: 2026-05-06
origin: docs/plans/2026-05-06-003-feat-nix-layer-10b-bootable-rootfs-plan.md
---

# feat: Add Layer 12 opt-in guest SSH service

## Overview

Layer 12 turns a hardware-validated Layer 10b bootable guest into the first narrowly exposed Nix-managed service: guest SSH on an alternate port. The service is opt-in, key-only, non-autostart by default, and must never interfere with ROCKNIX host SSH on port 22.

This plan intentionally assumes Layer 10b succeeds so the Layer 12 branch and image build can be queued while hardware validation catches up. That assumption is for build pipelining only. Layer 12 is not hardware-Go until Layer 10b is validated first, then the Layer 12 image is installed and tested on top of the same device in order.

## Problem Frame

Layer 10b proves that a real NixOS/container-style guest can be imported, manually started, observed with root-specific nspawn evidence, stopped cleanly, and left disabled across reboot. The next useful vertical slice is a single network service that demonstrates Nix-managed guest services without handing over the host OS.

SSH is the right first service because it is easy to validate with real commands, useful for operator access, and dangerous enough to force the security boundary now. The design must preserve ROCKNIX as the recovery plane: `ssh root@thor` on port 22 remains the host access path, and guest SSH is an explicitly configured side channel on a different port.

## Requirements Trace

- R1. Add a Layer 12 contract for opt-in guest services, with SSH as the only first service.
- R2. Keep Layer 10b lifecycle semantics unchanged: manual `nixctl guest start` / `stop`, no generated autostart, disabled unit by default.
- R3. Expose guest SSH only on an alternate host port, defaulting to `2222`; never use or bind host port `22`.
- R4. Require explicit authorized-key material before enabling guest SSH.
- R5. Disable password authentication, keyboard-interactive authentication, root password login, and all default credentials.
- R6. Preserve host SSH recovery even if the guest service is misconfigured, unavailable, or stopped.
- R7. Store Layer 12 service metadata under `/storage/.config/nix-integration/layer12` and avoid mutating `/usr`, `/flash`, `/boot`, host `/etc`, host SSH config, ROMs, saves, Steam state, or FEX state at runtime.
- R8. Add `nixctl guest service` commands for status, preflight, enable, disable, and remove of the SSH service.
- R9. Add `nix-doctor` reporting for Layer 12 service state, port, key provenance, and guardrail violations.
- R10. Provide repeatable smoke validation that exercises real SSH against the guest service with key-only authentication.
- R11. Keep Layer 12 out of graphics/audio/input/Wayland passthrough, persistent app bridges, remote builders, and general service orchestration.

## Scope Boundaries

- This plan does not replace ROCKNIX host SSH or move recovery access into the guest.
- This plan does not enable guest SSH by default.
- This plan does not allow password login, default passwords, or generated shared credentials.
- This plan does not expose port 22 from the guest.
- This plan does not add guest autostart. Any autostart policy remains a later, separately validated layer.
- This plan does not introduce a general NixOS module management system. It adds one explicit SSH service slice.
- This plan does not add UI, audio, input, Wayland, ROM, save, Steam, or FEX passthrough.
- This plan does not make the guest a remote builder.
- This plan does not require a live network during build-time tests.

### Deferred to Separate Tasks

- Layer 12b: additional opt-in services after SSH proves the service boundary.
- Layer 13: declarative service profiles and rollback.
- Layer 14: remote builder mode, if performance and security reviews approve it.
- Autostart policy and freeze/thaw scheduling for gameplay.
- UI integration for service management.

## Context & Patterns

Relevant existing files:

- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl` owns the operator command surface and Layer 10 guest lifecycle.
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor` reports Nix layer health and should surface Layer 12 guardrails.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/rocknix-guest.nix` defines the guest image; Layer 12 can add SSH in a locked-down, explicitly port-forwarded form.
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer10-guest-lifecycle-contract.md` is the lifecycle boundary Layer 12 must not weaken.
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer11-bridge-contract.md` shows how a later layer records a narrow contract without expanding host ownership.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh` already supports opt-in hardware smoke modes.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` is the right place for hard guardrails: no port 22, no password auth, no autostart.
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md` remains the hardware evidence ledger.

Institutional learnings to preserve:

- `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`: service status must use live evidence, not metadata alone.
- `docs/solutions/developer-experience/nix-layer-9-nspawn-guest-proof-rocknix-2026-05-06.md`: use `systemd-nspawn --register=no`; do not rely on machined.
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`: always precheck ABL slots before SM8550 update reboot.

## Key Technical Decisions

| Decision | Rationale |
|---|---|
| Make Layer 12 SSH key-only and opt-in | Network exposure is a higher-risk boundary than Layer 10b lifecycle; default-off keeps host recovery safe. |
| Bind guest SSH to host port `2222` by default | Preserves host SSH on port `22` as the recovery plane and makes validation explicit with `ssh -p 2222`. |
| Refuse port `22` in `nixctl` and static checks | A later typo must not accidentally replace or shadow host SSH. |
| Require user-provided authorized keys | Avoids default credentials and keeps identity material outside the image. |
| Keep service metadata in Layer 12 state | Layer 6/11 ownership ideas apply: record what this layer owns and refuse unsafe conflicts. |
| Start with one named service, not a generic service manager | SSH validates the vertical slice without prematurely designing a broad orchestration framework. |
| Use real SSH smoke tests | The contract is network access; validation must use an actual SSH client connection, not config inspection only. |

## Proposed Command Surface

Layer 12 extends `nixctl` with a narrowly scoped service group:

```text
nixctl guest service status
nixctl guest service preflight ssh
nixctl guest service enable ssh --port 2222 --authorized-keys /storage/.ssh/authorized_keys
nixctl guest service disable ssh
nixctl guest service remove ssh --yes
```

Expected operator flow after Layer 10b import:

```text
nixctl guest service enable ssh --port 2222 --authorized-keys /storage/.ssh/authorized_keys
nixctl guest start
ssh -p 2222 root@thor /usr/bin/nix --version
nixctl guest stop
```

## State Model

Layer 12 service state should be explicit rather than a bag of booleans:

| State | Meaning |
|---|---|
| `unconfigured` | No Layer 12 service metadata exists. |
| `configured` | SSH metadata exists, keys are present, guest may be stopped. |
| `ready` | Guest rootfs and SSH config pass preflight. |
| `running` | Guest is running and SSH responds on the configured alternate port. |
| `failed` | Metadata exists but a guardrail or live check failed. |

State conversion happens at the shell seam: command exits, files, ports, and processes become one of these named states before rendering status.

## Implementation Units

### Unit 1: Layer 12 contract and docs

Files:

- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer12-guest-ssh-contract.md`
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- `docs/plans/2026-05-06-004-feat-nix-layer-12-opt-in-guest-ssh-plan.md`

Work:

- Document SSH as the only Layer 12 service.
- Declare no port 22, no password auth, no default credentials, no autostart, and no host SSH takeover.
- Define Go/No-Go evidence and rollback expectations.

Tests / validation:

- Static text checks for the contract path and forbidden/required terms.

### Unit 2: Guest SSH configuration source

Files:

- `projects/ROCKNIX/packages/tools/nix-integration/guest/rocknix-guest.nix`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/README.md`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

Work:

- Add OpenSSH to the guest configuration in a locked-down form.
- Keep password and keyboard-interactive authentication disabled.
- Keep root locked; root login only via authorized keys if explicitly mounted/provisioned.
- Ensure the guest image itself does not ship reusable credentials or keys.

Tests / validation:

- Assert guest config disables password auth.
- Assert no default `authorized_keys` content is shipped.
- Assert no port `22` host binding appears in generated host-side service code.

### Unit 3: Layer 12 metadata and `nixctl guest service` commands

Files:

- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

Work:

- Add state directory `/storage/.config/nix-integration/layer12`.
- Implement `guest service status`, `preflight ssh`, `enable ssh`, `disable ssh`, and `remove ssh --yes`.
- Validate authorized-key path safety and existence.
- Refuse port 22, privileged surprises, missing keys, and unsafe state paths.
- Record metadata: service name, port, authorized-key source, checksum, enabled time, guest root provenance reference.

Tests / validation:

- Enable fails without keys.
- Enable fails on port 22.
- Enable writes metadata for port 2222.
- Disable preserves metadata enough for diagnostics or explicitly records disabled state.
- Remove requires `--yes` and only deletes Layer 12-owned state.

### Unit 4: Host-to-guest port exposure and lifecycle integration

Files:

- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

Work:

- Extend Layer 10 unit generation only when Layer 12 SSH metadata is configured.
- Add conservative nspawn network/port forwarding needed for host port 2222 to reach guest SSH.
- Keep unit disabled and manually started.
- Ensure stop removes live exposure by stopping the guest.

Tests / validation:

- Generated unit contains no port 22 binding.
- Generated unit includes the configured alternate port only when SSH is configured.
- Start refuses configured SSH if preflight fails.
- Stop leaves no guest nspawn process and no responding SSH port.

### Unit 5: `nix-doctor` Layer 12 reporting

Files:

- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

Work:

- Report Layer 12 state, configured service, port, key checksum, and guardrail warnings.
- Treat port 22, missing keys, password auth indicators, or missing Layer 10b provenance as failures for Layer 12 readiness.

Tests / validation:

- Doctor reports `unconfigured` cleanly.
- Doctor reports configured SSH metadata.
- Doctor fails/warns on unsafe port, missing keys, or missing bootable provenance.

### Unit 6: Hardware smoke and device documentation

Files:

- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- `projects/ROCKNIX/packages/tools/nix-integration/package.mk`
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`

Work:

- Add `LAYER12_SMOKE=ssh` hardware mode.
- Smoke should require Layer 10b bootable provenance, configured keys, and host SSH reachability assumptions.
- Validate real `ssh -p 2222` to the guest and then cleanly stop.
- Record Go/No-Go evidence after installing on `thor`.

Tests / validation:

- Smoke refuses to run without Layer 10b provenance.
- Smoke refuses to run without key material.
- Smoke records start, SSH command output, stop, no residual guest process, and host SSH continuity.

## Hardware Validation Order

Even though the Layer 12 branch may be built before Layer 10b is manually validated, installation and Go/No-Go decisions must stay ordered:

1. Install Layer 10b image on `thor`.
2. Run ABL precheck before rebooting into updater.
3. Import real bootable rootfs.
4. Validate `nixctl guest start` / `stop` and reboot no-autostart.
5. Only after Layer 10b is Go, install the Layer 12 image.
6. Re-run host health checks.
7. Configure guest SSH with explicit authorized keys on port 2222.
8. Validate `ssh -p 2222 root@thor /usr/bin/nix --version`.
9. Stop guest and verify port 2222 is closed or unreachable.
10. Reboot and verify no guest autostart and host SSH on port 22 remains healthy.

## Success Criteria

Layer 12 is hardware-Go when all are true:

- Layer 10b was validated first on the same device lineage.
- Guest SSH is not enabled by default after image install.
- `nixctl guest service enable ssh --port 2222 --authorized-keys ...` succeeds with explicit keys.
- Port 22 is never bound or modified by Layer 12.
- Password authentication is unavailable.
- `ssh -p 2222 root@thor /usr/bin/nix --version` returns the guest Nix version.
- `nixctl guest stop` removes the live SSH exposure.
- Reboot does not autostart the guest or guest SSH.
- Host `ssh root@thor` remains the recovery path throughout.
- `nix-doctor` reports Layer 12 healthy or unconfigured with clear diagnostics.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Guest SSH shadows host SSH | Refuse port 22 in command validation, static checks, and doctor. |
| Password login sneaks in through NixOS defaults | Explicitly disable password and keyboard-interactive auth; add static checks. |
| Bad guest config breaks recovery | Host SSH remains untouched; guest remains manual and disabled. |
| Port remains open after stop | Smoke validates stop plus no live process/port evidence. |
| Layer 12 masks Layer 10b failures | Validation order requires Layer 10b Go before Layer 12 Go. |
| Service scope balloons | Contract limits first slice to SSH only. |

## Rollback

- `nixctl guest service disable ssh` should stop exposing SSH on the next guest start while preserving diagnostics.
- `nixctl guest service remove ssh --yes` should delete only Layer 12-owned metadata.
- `nixctl guest stop` remains the immediate live rollback for service exposure.
- Host recovery remains `ssh root@thor` on port 22.
- Full rollback remains reinstalling the previous ROCKNIX image or booting the prior slot per existing SM8550 update procedures.
