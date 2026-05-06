---
title: Stage a minimal systemd-nspawn rootfs from on-device Nix closures on ROCKNIX
date: 2026-05-06
category: best-practices
module: ROCKNIX nix-integration
problem_type: best_practice
component: tooling
severity: low
applies_when:
  - You need a small systemd-nspawn guest rootfs on a ROCKNIX SM8550 device
  - Cross-building a full aarch64 NixOS tarball is overkill for the proof
  - The host already has Layer 3 `/nix` and Layer 4 real Nix installed
related_components:
  - systemd-nspawn
  - nix
  - SM8550
tags: [rocknix, nspawn, nix, layer-9, sm8550, guest, closure]
---

# Stage a minimal systemd-nspawn rootfs from on-device Nix closures on ROCKNIX

## Context

Layer 9 needs a guest rootfs at `/storage/machines/rocknix-guest`, but cross-building a full aarch64 NixOS image off-device is heavy for what is initially a yes/no proof. ROCKNIX with Layers 3-4 already has a real `/nix/store` populated with the closure for `nix`, `bash`, and their dependencies. That closure is enough for `systemd-nspawn --register=no` to run a one-shot Nix proof inside a guest.

This entry captures the on-device staging recipe so future agents do not re-derive it, and so they avoid the two non-obvious traps we hit while building it.

## Guidance

Resolve the real store paths, copy the closure into the guest, and add minimal `/bin/sh` and `/usr/bin/nix` entry points:

```sh
ROOT=/storage/machines/rocknix-guest
NIX_BIN=$(readlink -f /nix/var/nix/profiles/default/bin/nix)
NIX_STORE_BIN=$(readlink -f /nix/var/nix/profiles/default/bin/nix-store)
BASH_BIN=$(find /nix/store -maxdepth 4 -type f -path "*/bin/bash" -perm /111 2>/dev/null | head -1)

mkdir -p "$ROOT/bin" "$ROOT/usr/bin" "$ROOT/nix/store" \
         "$ROOT/etc" "$ROOT/tmp" "$ROOT/proc" "$ROOT/sys" "$ROOT/dev"
chmod 1777 "$ROOT/tmp"
printf 'NAME=rocknix-layer9-proof\nID=rocknix-layer9-proof\n' >"$ROOT/etc/os-release"

/nix/var/nix/profiles/default/bin/nix-store -qR "$NIX_BIN" "$NIX_STORE_BIN" "$BASH_BIN" \
  | while IFS= read -r ref; do
      [ -n "$ref" ] && cp -a "$ref" "$ROOT/nix/store/"
    done

ln -s "$BASH_BIN"      "$ROOT/bin/sh"
ln -s "$BASH_BIN"      "$ROOT/bin/bash"
ln -s "$NIX_BIN"       "$ROOT/usr/bin/nix"
ln -s "$NIX_STORE_BIN" "$ROOT/usr/bin/nix-store"
```

Then run a bounded proof with `--register=no` (required because ROCKNIX builds systemd with `machined=false`):

```sh
timeout 45 /usr/bin/systemd-nspawn --quiet --register=no \
  --directory=/storage/machines/rocknix-guest /bin/sh -lc \
  "printf 'layer9-guest-proof\n'; nix --version"
```

Resulting size on `thor`: about 176 MB for nix + bash and their closure.

## Why This Matters

Two gotchas cost real time on the first attempt and will cost it again for any future contributor who follows the obvious path:

1. **Profile-aggregator symlinks resolve to a directory, not a binary.** On ROCKNIX, `/nix/var/nix/profiles/default/bin/bash` resolves through `readlink -f` to a `*-profile/bin/bash` path under a profile-aggregator store entry, not to a real bash binary store path. Copying that `*-profile` directory is not enough; the guest needs the real `bash-*/bin/bash` store path. Fix: enumerate real binaries with `find /nix/store -maxdepth 4 -type f -path "*/bin/bash" -perm /111` and use the resulting store path as the symlink target. The same pattern applies to other tools like `nix` and `nix-store`, but those happen to already be in non-profile store entries.

2. **Standalone nspawn must skip machined registration.** ROCKNIX's `projects/ROCKNIX/packages/sysutils/systemd/package.mk` builds with `-Dmachined=false`. Without `--register=no`, every nspawn invocation fails:

```text
Failed to register machine: The name org.freedesktop.machine1 was not provided by any .service files
```

A third, lower-impact warning is also expected and can be ignored for one-shot proofs:

```text
/etc/localtime does not point into /usr/share/zoneinfo/, not updating container timezone.
```

## When to Apply

- Layer 9 manual proofs and any later opt-in nspawn experiment that does not need a real NixOS guest.
- Quick on-device sanity checks for tools whose closures already live in the on-device `/nix/store`.
- Skip this approach when the experiment requires a full NixOS userspace (systemd as PID 1, NixOS modules, `nixos-rebuild`); cross-build a real NixOS tarball off-device for that.

## Examples

Real proof output from `thor` after staging:

```text
[layer9-smoke] start: bounded systemd-nspawn guest proof command
/etc/localtime does not point into /usr/share/zoneinfo/, not updating container timezone.
layer9-guest-proof
nix (Nix) 2.34.7
[layer9-smoke] cleanup: verify no guest process or enabled guest unit remains
nix-integration Layer 9 smoke passed
```

Cleanup is a directory removal:

```sh
rm -rf /storage/machines/rocknix-guest
```

Removing the guest root must not touch host `/nix`, `/storage/.nix-profile`, `/storage/.config/nix`, or `/storage/.config/nix-daemon`. Those are owned by Layers 3-8 and have separate lifecycles.

## Related

- `docs/solutions/developer-experience/nix-layer-9-nspawn-guest-proof-rocknix-2026-05-06.md`
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer9-nspawn-guest-contract.md`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- `projects/ROCKNIX/packages/sysutils/systemd/package.mk`
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
