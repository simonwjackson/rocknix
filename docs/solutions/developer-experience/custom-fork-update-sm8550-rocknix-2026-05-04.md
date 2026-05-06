---
title: Deploy a custom-fork ROCKNIX build to an SM8550 device with a bricking-risk decision tree
date: 2026-05-04
category: developer-experience
module: ROCKNIX SM8550 custom-fork deployment
problem_type: developer_experience
component: tooling
severity: medium
applies_when:
  - You build ROCKNIX from a fork (not the official `ROCKNIX/distribution` repo) and need to flash it to a real device.
  - The official `update.rocknix.org` channel cannot serve your build because it only knows about upstream releases.
  - The target device uses the qcom-abl bootloader (SM6115, SM8250, SM8550, SM8650) where the on-device update path also flashes the ABL partitions.
related_components:
  - tooling
tags: [rocknix, sm8550, odin2, custom-build, ota-update, qcom-abl, deployment]
---

# Deploy a custom-fork ROCKNIX build to an SM8550 device

## Context

ROCKNIX ships an `rocknix-update` script that talks to `https://update.rocknix.org` and pulls the matching nightly or release for the device's `HW_DEVICE` / `HW_ARCH` / `BUILD_BRANCH`. The endpoint only knows about upstream `ROCKNIX/distribution` builds. A fork building images with custom changes (e.g. `NIX_INTEGRATION_SUPPORT=yes` on a downstream branch) cannot use the official channel — `rocknix-update check` either reports no update or, worse, would offer to "update" the device back to upstream.

The on-device boot script (busybox `init` from `packages/sysutils/busybox/scripts/init`) supports a manual override path: any `*ROCKNIX*.tar`, `.img.gz`, or `.img` placed in `/storage/.update/` is detected at next boot, AVFS-mounted, compatibility-checked, and applied. This document captures the full procedure for using that path safely on Snapdragon devices where the update also flashes the qcom-abl bootloader, plus the precheck that drives bricking risk to effectively zero.

## Guidance

### The procedure

```sh
TAR=/path/to/ROCKNIX-SM8550.aarch64-<DATE>.tar       # produced by your fork's build
DEV=root@<device-ip>

# 1. Pre-flight (read-only): disk space, empty .update, abl partitions, power
ssh $DEV '
  set -e
  free=$(df -m /storage | awk "NR==2 {print \$4}")
  [ "$free" -ge 2200 ] || { echo "FAIL: need >= 2200 MB free on /storage"; exit 1; }
  if [ -n "$(ls -A /storage/.update/ 2>/dev/null)" ]; then
    echo "FAIL: /storage/.update not empty"; ls -la /storage/.update/; exit 1
  fi
  test -b "$(blkid -t PARTLABEL=abl_a -o device)"
  test -b "$(blkid -t PARTLABEL=abl_b -o device)"
  echo "battery: $(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1)%"
  echo "online:  $(cat /sys/class/power_supply/*/online 2>/dev/null | head -1)"
'

# 2. Verify artifact host-side
sha256sum -c "$TAR.sha256"

# 3. ABL skip precheck — the bricking-risk gate (see "Why this matters")
ELF_PATH=$(tar -tf "$TAR" | grep abl_signed-SM8550.elf | head -1)
ELF_SHA=$(tar -xf "$TAR" "$ELF_PATH" -O | sha256sum | awk '{print $1}')
ELF_SIZE=$(tar -xf "$TAR" "$ELF_PATH" -O | wc -c)
ssh $DEV "
  for slot in abl_a abl_b; do
    DEV_BLOCK=\$(blkid -t PARTLABEL=\$slot -o device)
    SS=\$(blockdev --getss \$DEV_BLOCK)
    COUNT=\$(( ($ELF_SIZE + \$SS - 1) / \$SS ))
    SUM=\$(dd if=\$DEV_BLOCK bs=\$SS count=\$COUNT status=none | head -c $ELF_SIZE | sha256sum | awk '{print \$1}')
    if [ \"\$SUM\" = \"$ELF_SHA\" ]; then
      echo \"  \$slot: MATCH (no flash)\"
    else
      echo \"  \$slot: differs -- WILL FLASH\"
    fi
  done
"

# 4. Transfer (resumable; falls back to scp if rsync absent on device)
rsync -P --inplace --partial "$TAR" "$TAR.sha256" "$DEV:/storage/.update/" \
  || scp "$TAR" "$TAR.sha256" "$DEV:/storage/.update/"

# 5. Device-side sha256 verify
ssh $DEV '
  cd /storage/.update
  expected=$(awk "{print \$1}" *.sha256)
  actual=$(sha256sum *.tar | awk "{print \$1}")
  [ "$expected" = "$actual" ] || { echo MISMATCH; rm -f *.tar *.sha256; exit 1; }
  echo OK
'

# 6. Snapshot pre-update state for the record
ssh $DEV 'cat /etc/os-release; echo; uname -a' > pre-update-state.txt

# 7. Reboot. SSH connection drops as device goes down.
ssh $DEV 'sync; nohup reboot >/dev/null 2>&1 & disown' || true

# 8. Wait for device to come back (typical: ~3-5 min for the full update cycle)
for i in $(seq 1 60); do
  sleep 10
  ssh -o ConnectTimeout=4 -o BatchMode=yes $DEV true 2>/dev/null && break
done

# 9. Validate the new build
ssh $DEV '
  cat /etc/os-release | grep -E "OS_VERSION|BUILD_BRANCH|BUILD_ID|BUILD_DATE"
  uname -r
  # custom-fork-specific validation goes here -- e.g. for a Nix-integration build:
  # systemctl is-active nix-storage-setup.service nix.mount
  # cat /proc/mounts | grep " /nix "
'
```

### What the on-device update path actually does

When the boot script finds a `*ROCKNIX*.tar` in `/storage/.update/`:

1. AVFS-mounts it to peek at `target/`.
2. Runs `check_is_compatible` — reads `/etc/os-release` from old `/sysroot` and new `/update`, requires matching `HW_ARCH` and `HW_DEVICE`. Mismatched arch/device aborts the update with a clear error.
3. `update_file KERNEL` and `update_file SYSTEM` — `dd if=... of=/flash/{KERNEL,SYSTEM} bs=1M conv=fsync`. Writes are in-place on the vfat `/flash` partition.
4. `update_bootloader` runs `${SYSTEM_ROOT}/usr/share/bootloader/update.sh` from the new image, which sources `updateabl`.
5. `updateabl` (on SM6115/SM8250/SM8550/SM8650) reads the SHA256 of the currently-flashed `abl_a` and `abl_b` partitions and **only flashes if they differ** from the new `abl_signed-<DEVICE>.elf`. If both match, it prints `"ABL_A and ABL_B match update version — skipping flash"` and exits.
6. Cleans `/storage/.update/.tmp`, writes `UPDATE` to `/storage/.boot.hint`, reboots into the new system.

## Why This Matters

**Bricking-risk topology on Snapdragon ROCKNIX devices:**

| Write | Failure outcome | Recovery |
|---|---|---|
| `/flash/SYSTEM` (vfat file `dd`) | won't-boot-to-OS, bootloader fine | reflash from `/storage/.update/` via SSH-from-recovery, or fastboot |
| `/flash/KERNEL` (vfat file `dd`) | won't-boot-to-OS, bootloader fine | same as above |
| `abl_a`, `abl_b` partition `dd` | **only** real bricking vector | EDL (Qualcomm Emergency Download Mode) + `qdl`/QFIL |

The ABL flash is the only operation that can soft-brick the device. The rest are recoverable without USB tooling. So the question for every custom-fork update reduces to: **does this build's ABL ELF differ from what's currently on the device's `abl_a`/`abl_b` slots?**

**The ABL skip precheck (Step 3) answers this before the reboot.** If both slots already hold the same ELF the new build is shipping, `updateabl` will skip the flash entirely and the only writes during the update are the two `/flash` files — neither of which can affect the bootloader. The bricking vector is gone.

For most fork updates this returns "MATCH" on both slots, because:

- `rocknix-abl` is pinned to a versioned upstream tarball (`https://github.com/ROCKNIX/abl/releases/download/v<X.Y.Z>/...`).
- The qcom-abl ELF is built reproducibly from that source.
- Forks rarely touch this package — most diverge in userspace, the kernel config, or new ROCKNIX packages, not the bootloader.

When the precheck shows "differs — WILL FLASH" on either slot, the update is still safe in the normal case (A is flashed first, then B, both with the same content; power loss between leaves one A/B slot bootable), but you have a real interruption window. Plug in the charger, or postpone.

**Why the official update channel doesn't help here:**

`rocknix-update` POSTs `OS`, `ARCH`, `SOC`, `VERSION`, `BUILD`, `DEV`, `FORCE`, `BRANCH` to `update.rocknix.org` and gets back a signed URL. The endpoint's database tracks builds from `ROCKNIX/distribution`'s `next` and `release` branches only. A fork's `BUILD_BRANCH` value (e.g. `custom`) returns no match, or worse the endpoint may try to "downgrade" the device back to upstream's latest. The boot-script override path (`/storage/.update/*.tar`) is the supported way to install any image whose filename contains `ROCKNIX`.

## When to Apply

- After every successful CI build of your fork, when you want to test the resulting image on real hardware.
- Whenever the official update channel is not viable: forks, branches with a different `BUILD_BRANCH`, locally-built images, or development snapshots.
- Specifically on qcom-abl SoCs (SM6115, SM8250, SM8550, SM8650) — non-Snapdragon devices have a simpler bootloader update model and don't need the ABL precheck.

Skip this procedure when you'd be flashing the same image the device already has, or when the upstream nightly already covers your changes — in those cases just let `rocknix-update` do its normal thing.

## Examples

### A real run from this session (Odin2 Portal, 2026-05-04)

```
=== Pre-flight ===
  /storage free: 34873 MB
  abl_a present
  abl_b present
  battery: 63%
  status:  Discharging

=== ABL skip precheck ===
  abl_a: MATCH (no flash)
  abl_b: MATCH (no flash)

=== Transfer ===
1.86 GB transferred at ~20 MB/s in 94s

=== Device-side sha256 ===
sha256: MATCH
  7ecd852f0a004d052b400b7c0b0e0522ecf26ed9e81234683d30bb3b7a8a64e1

=== Pre-update state ===
OS_VERSION="20260428"   BUILD_BRANCH="next"     BUILD_ID="f1aec01871..."
Linux SM8550 7.0.1 #1 SMP PREEMPT Tue Apr 28 07:03:06 UTC 2026 aarch64

=== Reboot at 19:13:06 UTC ===
[19:13:09] device offline -- update in progress
... ~3 min ...

=== After reboot ===
OS_VERSION="20260503"   BUILD_BRANCH="custom"   BUILD_ID="4102892348..."
Linux SM8550 7.0.2 #1 SMP PREEMPT Sat May  2 23:19:22 UTC 2026 aarch64
```

Total wall-clock from "go" to validated: ~3 minutes 30 seconds. ABL flash skipped on both slots as predicted.

### Hazard discovered during this work: stale `PKG_DEPENDS_TARGET` references

During the first attempt, `make image` failed in the `build-aarch64` step with:

```
Exception: Invalid package reference: dependency gnupg in package
image::PKG_DEPENDS_TARGET is not valid
```

Root cause: the fork's nix-integration commit accidentally re-added `gnupg` to `PKG_DEPENDS_TARGET` in `projects/ROCKNIX/packages/virtual/image/package.mk`. Upstream had removed the `gnupg` package on 2025-11-19 (commit `55ffbd7375 gnupg: remove unused package`) but left the package list otherwise untouched. The accidental re-add introduced a reference to a package that no longer existed in the tree.

Fix was a one-character revert. The general lesson for fork maintainers: **whenever you modify `projects/ROCKNIX/packages/virtual/image/package.mk` on a downstream branch, audit `PKG_DEPENDS_TARGET` for stale package names that upstream may have since removed**. The image build runs after every dependency in this list is resolved, so a stale reference is a hard failure that surfaces only at image-time — well after the slow toolchain and aarch64 stages have completed.

A small CI guard would catch this earlier:

```sh
# pseudo-check, run before the image stage
for pkg in $(grep -oE '[a-z][a-z0-9-]+' \
             projects/ROCKNIX/packages/virtual/image/package.mk \
             | sort -u); do
  find packages/ projects/ -name package.mk -path "*/$pkg/*" \
    -exec grep -l "^PKG_NAME=\"$pkg\"" {} + >/dev/null \
    || echo "stale ref: $pkg"
done
```

### Validation checklist for a Nix-integration-enabled build

When the fork's build sets `NIX_INTEGRATION_SUPPORT=yes`, the post-update validation should additionally confirm Layer 3 came up and the shipped profile integration sorts after ROCKNIX's busybox PATH reset:

```sh
ssh $DEV '
  systemctl is-active nix-storage-setup.service nix.mount
  cat /proc/mounts | grep " /nix "
  ls -ld /storage/.nix-root /storage/.nix-root/store /storage/.nix-root/var/nix
  ls /usr/bin/nixctl /usr/bin/nix-doctor /usr/bin/nix-layer-activate /etc/profile.d/998-nix-integration.conf
  touch /nix/.layer3-validated && ls -la /nix/.layer3-validated  # persistence smoke
  . /etc/profile
  case "$PATH" in /storage/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/storage/bin:*) echo "PATH integration OK" ;; *) echo "PATH integration unexpected: $PATH"; exit 1 ;; esac
'
```

Both units should report `active`. `/proc/mounts` should show `/nix` backed by the same block device as `/storage` (the bind source). The Layer 3 design is fail-closed — if the units fail, multi-user.target still reaches and EmulationStation/SSH/Sway still come up.

For Layer 4 and Layer 5 validation on a device where installing real Nix is acceptable:

```sh
ssh $DEV '
  nixctl install
  . /etc/profile
  nix --version
  nix run nixpkgs#hello
  nix profile install nixpkgs#hello
  command -v hello
  hello
  nixctl status
  nix-doctor --offline
  nix profile remove hello
'
```

For a reboot persistence check, install `hello`, reboot, then validate that `command -v hello` still resolves under `/storage/.nix-profile/bin` before removing it. `nix-doctor --offline` should pass with only the expected offline warning on a healthy Layer 4/5 install.

## Related

- `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md` — the layered Nix integration plan whose Layer 3 this update first delivers to a real device.
- `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md` — the Layer 3+ handoff that defines the validation steps used in the example above.
- `docs/plans/2026-05-01-001-explore-nixos-on-rocknix-via-nspawn.md` — Layer 9 exploration that depends on this deployment path being repeatable.
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md` — operator-facing doc for the SM8550 Nix experiment, including the Layer 3 validation list.
- `projects/ROCKNIX/packages/sysutils/busybox/scripts/init` — the boot-time update applier.
- `projects/ROCKNIX/packages/rocknix/sources/scripts/updateabl` — the qcom-abl flasher with the no-op skip behavior the precheck exploits.
- `projects/ROCKNIX/packages/rocknix/sources/scripts/rocknix-update` — the official update path, for contrast.
