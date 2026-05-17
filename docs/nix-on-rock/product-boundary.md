# Nix-on-ROCK Product Boundary

Nix-on-ROCK is the SM8550 product lane that uses a thin ROCKNIX-derived host to boot, update, recover, and supervise a NixOS main-space guest.

ROCKNIX remains an upstream substrate source. It is valuable for boot machinery, package recipes, kernel and device integration, and distribution build tooling, but upstream ROCKNIX branch state is not the product authority for Nix-on-ROCK.

## Nix-on-ROCK owns

- SM8550 thin-host behavior and default boot into `rocknix-main-space.target`.
- Nix guest lifecycle through `rocknix-guest.service` and supporting substrate helpers.
- The visible storage contract rooted at `/storage/nix-on-rock`.
- Offline guest rootfs seed staging, verification, and extraction.
- Recovery posture for the Nix guest path, including host SSH-first recovery.
- Operator guidance for supported SM8550 installs, updates, reseeds, and smoke evidence.
- Product-lane build evidence and acceptance vocabulary.

## ROCKNIX supplies

- The inherited Linux distribution build system.
- Bootloader, kernel, firmware, package, and image assembly machinery.
- Base device/platform support that Nix-on-ROCK imports intentionally.
- Cache and artifact patterns that can speed up builds without deciding product health.

## Compatibility contracts to preserve

These names remain stable during the breakaway because they are operator-facing, wire-format, or deep build-system contracts:

- `/flash/rocknix.no-nspawn`
- `rocknix.safe=1`
- `/flash/rocknix.reseed-guest`
- update tar `target/seed/`
- inherited internal payload filenames such as `ROCKNIX-*.tar` and `ROCKNIX-*.img.gz`
- `rocknix-guest.service` and current substrate helper names

## Build evidence vocabulary

- `BuildProof`: CI produced artifacts and local product-lane gates passed.
- `DeviceAccepted`: a named device/compatible booted the artifact and produced the required on-device acceptance evidence.
- `ReleaseCandidate`: reserved for a future public Nix-on-ROCK release channel; not produced by the first product lane.

## Non-goals for the first breakaway slice

- A standalone repository.
- Broad renaming of project variables, services, package names, or payload filenames.
- A general ROCKNIX replacement for every supported device.
- Public release publishing or marketing infrastructure.
