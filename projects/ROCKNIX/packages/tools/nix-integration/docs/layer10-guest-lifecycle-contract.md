# Layer 10 guest lifecycle contract

Layer 10 turns the Layer 9 `systemd-nspawn` proof into managed guest operations. It is still an opt-in sidecar workload. ROCKNIX remains the host OS and owns boot, kernel, firmware, SSH recovery, Sway/EmulationStation, Steam/FEX, image updates, and package-managed services.

Layer 10 extends Layer 9. It does not weaken the Layer 9 safety boundary.

## Responsibilities

Layer 10 may:

- report lifecycle readiness through `nixctl guest status`, `nixctl guest preflight`, `nixctl status`, and `nix-doctor`
- stage or register guest rootfs state under `/storage/machines/rocknix-guest`
- record lifecycle metadata under `/storage/.config/nix-integration/layer10`
- run bounded one-shot commands in proof-mode roots
- start and stop bootable guest roots manually
- create or manage a disabled storage-local guest unit for bootable roots
- apply conservative resource controls to long-running guests when supported
- clean up guest-owned state after explicit confirmation or an equivalent non-interactive `--yes`

Layer 10 must not:

- start the guest during boot
- enable `systemd-nspawn@.service`, `rocknix-guest.service`, or any guest unit by default
- add ordering from SSH, Sway, EmulationStation, Steam/FEX, update, or recovery services to the guest
- depend on `machinectl` or `systemd-machined`
- replace ROCKNIX SSH or any other host recovery service
- mutate `/usr`, `/flash`, `/boot`, firmware, kernel modules, or package-managed services at runtime
- manage ROMs, saves, Steam/FEX state, browser profiles, or broad dotfile trees
- pass through graphics, audio, input, or host UI sockets by default

## Guest rootfs modes

Layer 10 distinguishes rootfs shape before choosing operations:

| Mode | Meaning | Allowed default operations |
|---|---|---|
| `absent` | No guest root exists at the configured path | `status`, `preflight`, `init`, `cleanup` no-op |
| `proof` | Minimal rootfs such as the Layer 9 nix+bash closure | `status`, `preflight`, `run`, `shell`, `cleanup` |
| `bootable` | Container-style rootfs with an init/systemd entry point | `status`, `preflight`, `start`, `stop`, `run`/`shell` when safe, `cleanup` |
| `invalid` | Path exists but is not a supported rootfs | `status`, `preflight`, guarded `cleanup` only |

A proof-mode root must not be advertised as a long-running booted guest. `nixctl guest start` must refuse proof-mode roots with a clear message and direct the operator to `nixctl guest run` or `nixctl guest shell`.

## Default paths

Default guest root:

```text
/storage/machines/rocknix-guest
```

Default Layer 10 metadata:

```text
/storage/.config/nix-integration/layer10
```

All Layer 10 mutable state must remain below those guest-owned roots unless the operator explicitly configures a fixture path for tests.

## nspawn invocation boundary

ROCKNIX builds systemd with `machined=false`. Layer 10 therefore uses standalone nspawn and must include:

```text
--register=no
```

Layer 10 must not require `machinectl`, machined registration, `org.freedesktop.machine1`, or `nss-mymachines`.

## Unit and autostart policy

Long-running bootable guests may use a storage-local unit so systemd can track and stop the process. Any such unit must be disabled by default and must not create a boot dependency.

Layer 10 must not call `systemctl enable` for guest units in normal operations. A reboot after Layer 10 installation or validation must return to host-only state unless an operator manually starts the guest again.

## Resource policy

Long-running bootable guests should be conservative by default:

- low CPU weight or equivalent when supported
- low I/O weight or equivalent when supported
- memory and task caps when supported
- explicit status/preflight warnings when a configured resource control cannot be enforced

Resource controls are safety rails, not permission to run the guest during gameplay. Manual start/stop and no autostart remain the primary safety boundary.

## Forbidden passthrough surfaces

Layer 10 must not bind or expose these by default:

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

Guest-backed apps, service bridges, alternate-port guest SSH, graphics, audio, and input are Layer 11+ work.

## Cleanup boundary

`nixctl guest cleanup` may remove only:

```text
/storage/machines/rocknix-guest
/storage/.config/nix-integration/layer10
```

or their fixture-configured equivalents in tests.

Cleanup must refuse unsafe roots such as `/`, `/storage`, `/nix`, `/usr`, `/flash`, `/boot`, ROM directories, save directories, Steam/FEX state, and host Nix config/state roots.

Cleanup must not touch:

```text
/storage/.nix-root
/storage/.nix-profile
/storage/.config/nix
/storage/.config/nix-daemon
/storage/.config/nix-integration/layer6
/storage/.config/nix-integration/layer8
```

## Failure and fallback meaning

For Layer 10, fallback means:

1. ROCKNIX still boots and runs normally.
2. SSH remains available for recovery.
3. Host Layers 4 and 8 remain usable or recoverable according to their own contracts.
4. Guest state can be stopped and removed without touching host Nix state.
5. A failed guest command, start, stop, or cleanup attempt is reported through `nixctl guest` and `nix-doctor` without affecting boot.

Fallback does **not** mean lower host layers provide equivalent guest lifecycle capability.

## Go / No-Go rule

Layer 10 is Go only if hardware validation proves:

- default boot has no running guest and no enabled guest unit
- proof-mode `nixctl guest run` or `nixctl guest shell` works with `--register=no`
- bootable-mode `nixctl guest start` refuses non-bootable roots and starts only a bootable root
- `nixctl guest stop` leaves no guest process behind
- `nixctl guest cleanup` removes only guest-owned state
- `nix-doctor --offline` reports lifecycle health clearly
- SSH, Sway, EmulationStation, Steam/FEX, host updates, Layer 4, and Layer 8 remain healthy before and after validation

Any autostart, host service takeover, forbidden passthrough dependency, unsafe cleanup boundary, or guest process left running after stop is a No-Go for Layer 10 until documented and fixed.
