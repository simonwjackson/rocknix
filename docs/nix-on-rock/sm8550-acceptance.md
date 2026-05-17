# SM8550 Nix-on-ROCK Acceptance Evidence

The Nix-on-ROCK product lane separates CI build evidence from on-device acceptance.

- `BuildProof`: CI produced artifacts and local product-lane gates passed.
- `DeviceAccepted`: a named SM8550 device/compatible booted and produced the evidence below.
- `ReleaseCandidate`: reserved for a future public release channel.

## BuildProof evidence

A `BuildProof` artifact set should have:

- Nix-on-ROCK SM8550 product-lane workflow success.
- guest-substrate static checks pass.
- SM8550 `SYSTEM` budget pass.
- update tar contains `target/SYSTEM`.
- update tar contains `target/seed/*.tar.zst`.
- image gzip integrity pass.
- Nix-on-ROCK build manifest uploaded with branch, SHA, seed, storage, and recovery evidence.

## DeviceAccepted evidence

Record the exact device and compatible string. Do not generalize an Odin2Portal proof to every SM8550 variant.

Recommended evidence for the first accepted build:

- Device model and first `/proc/device-tree/compatible` entry.
- Installed build SHA and artifact manifest run ID.
- `/dev/sda18` mounted on `/flash` and `/dev/sda19` mounted on `/storage` for internal installs, when applicable.
- `/storage/nix-on-rock/rootfs/current` exists and contains a valid guest root.
- `/storage/nix-on-rock/images/seeds` contains the matching seed archive when the seed is needed.
- `systemctl --failed` on the host reports no unexpected failures.
- `rocknix-guest.service` is active for normal main-space boot.
- guest `systemctl --failed` reports no unexpected failures.
- `rocknix-guest-activation-audit --quiet` succeeds.
- host SSH remains reachable.

When available, run the installed runtime smoke in live mode:

```sh
ROCKNIX_GUEST_LIVE_SMOKE=1 /usr/lib/rocknix-guest-substrate/tests/guest-substrate-runtime-smoke.sh
```

## Recovery evidence

At least one accepted build per meaningful recovery change should verify:

- `/flash/rocknix.no-nspawn` routes the next boot to host recovery.
- `rocknix.safe=1` routes a one-boot recovery when the bootloader/cmdline path is available.
- removing `/flash/rocknix.no-nspawn` restores normal main-space boot.
- missing, corrupt, or wrong-compatible seed fails closed before guest extraction and leaves host recovery access available.
- `/flash/rocknix.reseed-guest` clears only after a successful reseed.

## Clean-storage evidence

For fresh install confidence, record at least one clean-storage or intentionally wiped guest-root pass:

- matching seed staged under `/storage/nix-on-rock/images/seeds`;
- first boot creates `/storage/nix-on-rock/rootfs/current`;
- guest boots to running state;
- legacy `/storage/.guest` and `/storage/machines/rocknix-guest` migration does not lose the selected generation when tested.

Do not touch Android or firmware partitions as part of acceptance evidence unless a separate plan explicitly approves it.
