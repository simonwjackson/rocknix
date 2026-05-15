# SM8550 guest seed install notes

SM8550 builds use a thin ROCKNIX host and a NixOS guest root under `/storage/machines/rocknix-guest`.
The guest rootfs seed is too large for the 2GB `/flash/SYSTEM` partition, so it is not embedded in `SYSTEM`.

## Offline seed location

Stage the matching seed on the host storage partition:

```sh
mkdir -p /storage/.guest/seed
cp rocknix-guest-rootfs-<device>-<rev>.tar.zst /storage/.guest/seed/
```

The host image ships `/usr/lib/rocknix-guest-substrate/guest-rootfs-seed.manifest` with the expected filename, SHA256, revision, and device compatible string. `rocknix-guest-root-ensure` reads `/proc/device-tree/compatible`, selects the matching seed, verifies SHA256, then extracts it into `/storage/machines/rocknix-guest` only when that root is missing or empty.

## Odin2Portal vs Thor

Do not reuse a seed across SM8550 variants:

- Odin2Portal / sobo uses compatible `ayn,odin2portal`.
- Thor / bandai uses compatible `ayn,thor` and needs a Thor seed before testing this flow there.

A mismatched seed fails closed before extraction.

## Update tar flow

SM8550 update tarballs carry the seed outside `SYSTEM` under `target/seed/`. During update, initramfs stages it into `/storage/.guest/seed/` before writing the new `SYSTEM` to `/flash`.

## Full image flow

Full images remain host-only. After flashing, copy the matching seed to `/storage/.guest/seed/` before expecting the guest to boot from an empty `/storage`.

If the seed is missing or corrupt, host SSH/recovery should remain available, but `rocknix-guest.service` will not start.

## Explicit reseed

Normal updates do not overwrite an existing valid guest root. To force a clean reseed from a staged seed, stop the guest and create:

```sh
touch /flash/rocknix.reseed-guest
reboot
```

On success, the old root is retained as `/storage/machines/rocknix-guest.previous` and the reseed flag is cleared.
