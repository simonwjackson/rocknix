# SM8550 DeviceAccepted Evidence — sobo / Odin2Portal — 2026-05-18

## Result

`DeviceAccepted` for `sobo` / Odin2Portal (`ayn,odin2portal`) on the Nix-on-ROCK SM8550 product-lane branch.

This evidence applies only to the Odin2Portal-compatible SM8550 device tested here. Do not generalize it to Thor / `ayn,thor` without a separate device run.

## BuildProof source

- GitHub Actions run: <https://github.com/simonwjackson/rocknix/actions/runs/25996518119>
- Branch: `feat/nix-on-rock-product-lane`
- Installed host build: `e82f77eddf52ea3de77551c8fa8a56f274abcd4e`
- Update artifact: `ROCKNIX-SM8550.aarch64-20260518.tar`
- Image artifact: `ROCKNIX-SM8550.aarch64-20260518.img.gz`
- Expected guest seed: `rocknix-guest-rootfs-odin2portal-4fb6d8f14bae.tar.zst`
- Guest seed SHA256: `dc05c42344496c6f0fa66aa7514845cc6ab32a2d61881eb9341843aad39bcdde`

Local artifact checks before install:

- update tar checksum: passed
- image checksum: passed
- image gzip integrity: passed
- update tar contained `target/SYSTEM`
- update tar contained `target/seed/rocknix-guest-rootfs-odin2portal-4fb6d8f14bae.tar.zst`
- update-tar seed SHA matched the expected guest seed SHA256

## Device

- Device name: `sobo`
- Hostname: `SM8550`
- Compatible: `ayn,odin2portal`
- Internal install mounts:
  - `/dev/sda18 on /flash`
  - `/dev/sda19 on /storage`

## Acceptance checks

After installing `ROCKNIX-SM8550.aarch64-20260518.tar` through the normal `/storage/.update` path and rebooting:

- `BUILD_ID="e82f77eddf52ea3de77551c8fa8a56f274abcd4e"`
- host failed units: `0`
- `rocknix-guest.service`: `active`
- guest system state: `running`
- guest failed units: `0`
- `rocknix-guest-activation-audit --quiet`: passed
- live runtime smoke:
  - `ROCKNIX_GUEST_LIVE_SMOKE=1 /usr/lib/rocknix-guest-substrate/tests/guest-substrate-runtime-smoke.sh`
  - result: passed
- installed soak probe:
  - `ROCKNIX_REQUIRE_HOST_ESSWAY=no rocknix-guest-soak --hours 1 --interval-seconds 1`
  - result: `soak passed: 1 samples, zero alarms`

## Cold reboot check

A follow-up reboot of `sobo` succeeded.

Post-reboot checks:

- `BUILD_ID="e82f77eddf52ea3de77551c8fa8a56f274abcd4e"`
- host failed units: `0`
- `rocknix-guest.service`: `active`
- guest system state: `running`
- guest failed units: `0`

## Notes

The first installed pass exposed stale assumptions in `rocknix-guest-soak`, not a device failure:

- guest `/etc/resolv.conf` is an absolute guest symlink and must be checked from the guest namespace;
- localhost SSH recovery should count authentication refusal as daemon responsiveness.

Those probe fixes are included in build `e82f77eddf52ea3de77551c8fa8a56f274abcd4e` and passed on-device soak after install.
