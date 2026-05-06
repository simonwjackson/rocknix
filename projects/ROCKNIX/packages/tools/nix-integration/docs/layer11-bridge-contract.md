# Layer 11 one-shot bridge contract

Layer 11 exposes selected guest-backed capabilities through opt-in host entrypoints. It builds on Layer 10 proof-mode guest operations and must not weaken the Layer 10 safety boundary. ROCKNIX remains the host OS and owns boot, kernel, firmware, SSH recovery, Sway/EmulationStation, Steam/FEX, image updates, and package-managed services.

The first Layer 11 scope is one-shot bridges only: a host wrapper invokes a fixed guest command through `nixctl guest run`, returns its output, and leaves no guest process running.

## Responsibilities

Layer 11 may:

- report bridge readiness through `nixctl bridge status`, `nixctl bridge preflight`, `nixctl status`, and `nix-doctor`
- install explicit, named bridge wrappers into storage-owned user surfaces
- record bridge metadata under `/storage/.config/nix-integration/layer11`
- run installed bridge commands through Layer 10 one-shot guest execution
- remove only Layer 11-owned wrappers and metadata
- refuse unsafe bridge names, unsafe target paths, and non-owned file conflicts

Layer 11 must not:

- start a guest during boot
- enable or create any systemd service for bridges in the one-shot scope; Layer 11 one-shot bridges must not create a systemd service
- replace ROCKNIX SSH or any other host recovery service
- depend on guest availability for SSH, Sway, EmulationStation, Steam/FEX, update, or recovery
- expose alternate-port guest SSH; Layer 11 one-shot bridges must not expose guest SSH
- run persistent guest daemons or background services
- pass through graphics, audio, `/dev/input`, Wayland/Sway sockets, ROMs, saves, Steam state, FEX state, or browser profiles
- mutate `/usr`, `/flash`, `/boot`, firmware, kernel modules, or package-managed services at runtime
- accept arbitrary shell fragments as bridge definitions

## Default paths

Default Layer 11 metadata root:

```text
/storage/.config/nix-integration/layer11
```

Default bridge target surface:

```text
/storage/bin
```

A bridge named `layer11-nix-version` therefore installs as:

```text
/storage/bin/layer11-nix-version
```

## Bridge definition model

Each installed bridge must have inspectable metadata that records at least:

```text
name=<bridge-name>
target=/storage/bin/<bridge-name>
guest_root=/storage/machines/rocknix-guest
command=<fixed guest argv>
```

The generated wrapper must be simple and auditable. It should call the shipped control surface rather than duplicating nspawn flags:

```text
exec /usr/bin/nixctl guest run <fixed guest argv>
```

The command is fixed at install time. Operators can install a different bridge for a different command; runtime wrapper arguments must not become an arbitrary shell-evaluation surface.

## Ownership and conflict policy

Layer 11 owns only files recorded in its metadata. Installing a bridge must refuse an existing target unless the existing target is already recorded as Layer 11-owned for the same bridge.

Layer 11 cleanup may remove only:

```text
/storage/bin/<owned-bridge-name>
/storage/.config/nix-integration/layer11/<owned-bridge-name>
```

or their fixture-configured equivalents in tests.

Cleanup must not touch host Nix state, Layer 6 state, Layer 8 state, ROMs, saves, Steam/FEX state, or broad `/storage` directories.

## Layer 10 dependency

Layer 11 one-shot bridges depend on Layer 10 being ready for bounded one-shot execution. Bridge preflight must refuse unsupported, invalid, failed, or running guest state. A bridge run must leave Layer 10 with no running guest process.

Persistent services, alternate-port guest SSH, graphical/audio/input bridges, and autostart are blocked until bootable-mode Layer 10 start/stop/resource-bound lifecycle is hardware-validated with a real bootable rootfs.

## Go / No-Go rule

Layer 11 one-shot bridges are Go only if hardware validation proves:

- a bridge installs into `/storage/bin` without mutating `/usr`
- non-owned target conflicts are refused
- the bridge invokes a fixed guest command through `nixctl guest run`
- the bridge returns expected guest output
- no guest process remains after the bridge exits
- `nixctl bridge remove` removes only the owned bridge wrapper and metadata
- `nix-doctor --offline` reports Layer 11 health clearly
- SSH and normal ROCKNIX host operation remain healthy before and after validation

This one-shot scope was hardware-validated on `thor` on 2026-05-06 with build `d5d5aa3b9812562495f2f94ebc88950f9c7d7d40`.

Any autostart, persistent guest service, guest SSH exposure, forbidden passthrough dependency, unsafe cleanup boundary, or residual guest process after a one-shot bridge is a No-Go for Layer 11 until documented and fixed.
