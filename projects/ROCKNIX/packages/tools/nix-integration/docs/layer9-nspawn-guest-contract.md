# Layer 9 nspawn guest contract

Layer 9 proves a manually started NixOS-style userspace can run under `systemd-nspawn` on ROCKNIX. It is a proof layer, not a managed guest platform. ROCKNIX remains the host OS and owns boot, kernel, firmware, Sway/EmulationStation, Steam/FEX, image updates, and recovery.

## Responsibilities

Layer 9 may:

- preserve `/usr/bin/systemd-nspawn` in images built with `NIX_NSPAWN_SUPPORT=yes`
- stage a guest rootfs under `/storage/machines/rocknix-guest`
- start the guest manually for opt-in hardware validation
- bind only the minimal host files needed for the proof, preferably read-only
- report readiness through `nixctl status` and `nix-doctor`
- record logs and a Go/No-Go decision after hardware validation

Layer 9 must not:

- start the guest during boot
- enable `systemd-nspawn@.service` or any guest service by default
- add `nixctl guest` lifecycle commands; those belong to Layer 10
- replace ROCKNIX system services, Sway, EmulationStation, Steam/FEX, or update flow
- mutate `/usr`, `/flash`, `/boot`, firmware, kernel modules, or package-managed services at runtime
- manage ROMs, saves, Steam/FEX state, browser profiles, or broad dotfile trees
- pass through graphics, audio, input, or host UI sockets by default

## Guest root

The default guest root is:

```text
/storage/machines/rocknix-guest
```

All mutable guest state for Layer 9 lives below that tree, except optional diagnostic metadata under:

```text
/storage/.config/nix-integration/layer9
```

A guest root must be removable without touching host Nix state. Removing the guest root must not require deleting:

```text
/storage/.nix-root
/storage/.nix-profile
/storage/.config/nix
/storage/.config/nix-daemon
/storage/.config/nix-integration/layer6
/storage/.config/nix-integration/layer8
```

## Default bind policy

Layer 9 starts with the smallest useful host surface. Default binds may include only read-only host metadata needed to make a CLI proof usable, for example:

```text
/etc/resolv.conf -> guest resolver configuration (read-only, if needed)
```

The first proof should prefer a guest-local Nix store inside `/storage/machines/rocknix-guest`. Binding the host store or `/storage/.nix-root` into the guest is a later variant that must be documented separately because it couples host and guest rollback.

## Forbidden passthrough surfaces

Layer 9 must not bind or expose these by default:

- `/dev/dri` or other GPU/display devices
- PipeWire, PulseAudio, ALSA, or audio sockets/devices
- `/dev/input` or controller/touch/input devices
- host Wayland/Sway sockets
- EmulationStation, Sway, or autostart paths
- ROM directories
- save directories
- Steam state
- FEX state
- browser profiles
- `/usr`, `/flash`, `/boot`, kernel modules, or firmware trees
- package-managed ROCKNIX system services

Graphical/audio/input passthrough is Layer 11+ app/service bridge work, not Layer 9 proof work.

## Start and stop boundary

Layer 9 validation is manual and opt-in. It may start `systemd-nspawn` directly for a bounded proof, then stop it before declaring success.

Layer 9 must not leave behind:

- an enabled guest unit
- a boot dependency on the guest
- a required host service ordering edge from ROCKNIX UI/recovery services to the guest
- a running guest after a smoke script reports success or failure

## Failure and fallback meaning

For Layer 9, fallback means:

1. ROCKNIX still boots and runs normally.
2. SSH remains available for recovery.
3. Host Layers 4 and 8 remain usable or recoverable according to their own contracts.
4. Guest state can be stopped and removed without touching host Nix state.

Fallback does **not** mean lower host layers provide the same NixOS guest capability. If nspawn or the guest rootfs fails, the Layer 9 proof is unavailable; the fallback is the known host Nix stack plus cleanup, not feature equivalence.

## Go / No-Go rule

Layer 9 is Go only if hardware validation proves:

- `systemd-nspawn` is present on a Layer 9-enabled image
- no guest starts automatically at boot
- a staged guest root under `/storage/machines/rocknix-guest` can be started manually
- the guest reaches a useful proof state, such as a booted login or trivial Nix command/daemon proof
- the guest stops cleanly
- no host regression appears in SSH, Sway, EmulationStation, Steam/FEX, Layer 4, or Layer 8

Any host-impacting regression, unclear cleanup boundary, required forbidden passthrough, or guest process left running after failure is a No-Go for Layer 9 until documented and fixed.
