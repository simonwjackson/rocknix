# ROCKNIX Layer 10b bootable guest rootfs

This directory defines the minimal bootable guest rootfs used to validate Layer 10b on SM8550/Odin2 Portal.

Layer 10b is only a bootable lifecycle validation layer. The guest rootfs exists to prove that `nixctl guest start` and `nixctl guest stop` work with a real container-style rootfs under `systemd-nspawn --boot --register=no`. It is not a service layer and must not expose guest SSH, autostart, graphics, audio, input, ROM/save paths, Steam/FEX state, or host UI sockets.

## Artifact contract

A hardware-Go artifact must be:

- built for `aarch64-linux`
- NixOS/container-style, with `boot.isContainer = true`
- bootable by `systemd-nspawn --boot`
- self-contained for first validation; do not bind host `/nix` or `/storage/.nix-root` as guest `/nix`
- headless and non-network-exposed by default
- free of default passwords, password login, and remote-login services
- imported only under the configured Layer 10 guest root, normally `/storage/machines/rocknix-guest`

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

- `services.openssh.enable = true`
- password login or default credentials
- graphical sessions, Wayland/Sway integration, or `/dev/dri`
- PipeWire, PulseAudio, ALSA passthrough, or audio sockets
- `/dev/input` or controller/touch input passthrough
- ROM, save, Steam, FEX, or browser-profile mounts
- autostart or host boot dependencies

Those are separate layers after bootable start/stop has hardware-Go evidence.
