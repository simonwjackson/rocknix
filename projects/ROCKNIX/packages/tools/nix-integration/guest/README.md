# rocknix-nix-guest

NixOS guest flake and guest-side launch adapters for ROCKNIX SM8550/Thor main-space experiments.

This in-tree mirror tracks the public [`rocknix-nix-guest`](https://github.com/simonwjackson/rocknix-nix-guest) repo, which is the guest/runtime counterpart to [`nix-sm8550`](https://github.com/simonwjackson/nix-sm8550):

- `rocknix-nix-guest` owns the NixOS container guest, profiles, session policy, and ROCKNIX `/storage` compatibility adapters;
- `nix-sm8550` owns package derivations such as Cemu;
- ROCKNIX remains the base OS, boot/recovery plane, and host-side nspawn importer/launcher.

## Layout

- `flake.nix` exposes aarch64 NixOS guest configurations and rootfs packages.
- `rocknix-guest.nix` is the stable default Layer 10b/12 SSH-capable guest import.
- `modules/` contains reusable NixOS modules for the container baseline, SSH, display, audio, network, tooling, and lid policy.
- `profiles/` composes modules into `minimal`, `ssh`, `main-space`, and `dev-env` profiles.
- `launchers/` contains guest/host helper scripts used by the Layer 14 main-space Cemu validation path.
- ROCKNIX's `nix-integration-static-checks.sh` enforces the in-tree mirror boundary until the host integration consumes the external repo directly.

## Flake outputs

Configurations:

```sh
nix flake show --all-systems .
```

Expected NixOS configurations:

- `nixosConfigurations.rocknix-guest`
- `nixosConfigurations.rocknix-guest-main-space`
- `nixosConfigurations.rocknix-guest-dev-env`

Rootfs package outputs are exposed for `x86_64-linux` and `aarch64-linux` hosts:

```sh
nix build .#rootfs
sha256sum result/tarball/*.tar.*
```

The tarball is imported by ROCKNIX host tooling under the configured Layer 10 guest root, normally `/storage/machines/rocknix-guest`.

Layer 12 SSH remains opt-in: the guest listens on the alternate SSH port only for the SSH-capable profile, and authorized keys are supplied by host-side metadata/binds rather than shipped in the artifact.

## Runtime boundaries

The guest artifact must remain:

- container-style (`boot.isContainer = true`), built for `aarch64-linux`;
- free of default passwords, shipped authorized keys, or password login;
- explicit about host binds and `/storage` compatibility state;
- independent from ROCKNIX `/usr`, `/flash`, `/boot`, and host `/etc` mutation;
- free of broad `/storage/.cache` binds;
- free of package derivations that belong in `nix-sm8550`.

Layer 14 main-space intentionally adds Sway, Mesa/Freedreno, PipeWire, NetworkManager, and Cemu launch adapters. The minimal/SSH profile remains the small lifecycle/SSH validation baseline.

## Cemu boundary

`rocknix-guest-main-space` consumes Cemu from the public package repo:

```nix
nix-sm8550.url = "github:simonwjackson/nix-sm8550";
environment.systemPackages = [ nix-sm8550.packages.${targetSystem}.cemu ];
```

`launchers/start_cemu_guest.sh` defaults to `/run/current-system/sw/bin/cemu` and may fall back to a promoted profile for live rollback. It delegates ROCKNIX `/storage` layout compatibility to `cemu-storage-adapter.sh`; Vulkan loader setup stays in the package wrapper from `nix-sm8550`.

## Validation

Run ROCKNIX structural checks from the repository root:

```sh
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh
```

Evaluate and dry-run the main-space closure:

```sh
nix flake show --all-systems --no-write-lock-file .
nix build --dry-run --no-write-lock-file .#nixosConfigurations.rocknix-guest-main-space.config.system.build.toplevel
```

## Relationship to ROCKNIX

This directory is a temporary in-tree mirror used by ROCKNIX build/install scripts. The public source of truth is `github:simonwjackson/rocknix-nix-guest`; future cleanup should make ROCKNIX fetch/consume that repo directly instead of carrying the mirror.
