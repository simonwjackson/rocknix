# ROCKNIX Layer 10b bootable guest rootfs

This directory defines the minimal bootable guest rootfs used to validate Layer 10b on SM8550/Odin2 Portal. The guest is authored as reusable NixOS modules under `modules/` and profiles under `profiles/`; `rocknix-guest.nix` imports the default SSH-capable profile for compatibility with existing build commands.

Layer 10b is only a bootable lifecycle validation layer. The guest rootfs exists to prove that `nixctl guest start` and `nixctl guest stop` work with a real container-style rootfs under `systemd-nspawn --boot --register=no`. Layer 12 enables the guest's locked-down OpenSSH service only when host-side metadata and an operator-provided authorized-keys file are configured. It must not expose guest SSH by default, autostart, graphics, audio, input, ROM/save paths, Steam/FEX state, or host UI sockets.

## Artifact contract

A hardware-Go artifact must be:

- built for `aarch64-linux`
- NixOS/container-style, with `boot.isContainer = true`
- bootable by `systemd-nspawn --boot`
- self-contained for first validation; do not bind host `/nix` or `/storage/.nix-root` as guest `/nix`
- headless and non-network-exposed by default
- free of default passwords, password login, and shipped authorized keys
- imported only under the configured Layer 10 guest root, normally `/storage/machines/rocknix-guest`

## Module layout

- `modules/base.nix` contains the headless container baseline.
- `modules/tools.nix` contains the minimal CLI/tooling set.
- `modules/ssh.nix` contains the locked-down Layer 12 OpenSSH config on port `2222`.
- `profiles/minimal.nix` imports the base/tooling modules without SSH exposure.
- `profiles/ssh.nix` imports the default Layer 10b/12 profile used by `rocknix-guest.nix`.

## Build

From this directory, build the tarball package with Nix:

```sh
nix build .#rootfs
```

The resulting symlink points at a tarball produced by the pinned `nixpkgs` input in `flake.lock`.

Record the artifact checksum before transferring it to the device:

```sh
sha256sum result/tarball/*.tar.*
```

The import/staging command records the artifact name, sha256, import timestamp, and rootfs mode under `/storage/.config/nix-integration/layer10`.

## Non-goals

Do not add these to this Layer 10b guest:

- default guest SSH exposure; Layer 12 must provide host-side opt-in metadata and alternate-port forwarding
- password login, shipped authorized keys, or default credentials
- graphical sessions, Wayland/Sway integration, or `/dev/dri`
- PipeWire, PulseAudio, ALSA passthrough, or audio sockets
- `/dev/input` or controller/touch input passthrough
- ROM, save, Steam, FEX, or browser-profile mounts
- autostart or host boot dependencies

Those are separate layers after bootable start/stop has hardware-Go evidence.
