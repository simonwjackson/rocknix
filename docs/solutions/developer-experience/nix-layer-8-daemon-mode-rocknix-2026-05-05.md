---
title: ROCKNIX Layer 8 experimental Nix daemon mode
date: 2026-05-05
category: developer-experience
module: ROCKNIX nix-integration
problem_type: developer_experience
component: tooling
severity: medium
applies_when:
  - Validating whether host-side nix-daemon should run on ROCKNIX
  - Layer 4 single-user/root Nix already works and daemon mode is being considered
  - Daemon units or build identities are being added to the nix-integration package
resolution_type: tooling_addition
related_components:
  - nixctl
  - nix-doctor
  - nix-daemon
  - systemd
  - SM8550
tags: [rocknix, nix, layer-8, daemon, systemd, sm8550]
---

# ROCKNIX Layer 8 experimental Nix daemon mode

## Context

Layers 4-7 already provide practical Nix capability on ROCKNIX without a daemon: real `/nix`, standard single-user/root Nix, persistent profiles, reversible Layer 6 activation, and a Layer 7 Chromium app launch under Sway.

Layer 8 tests whether host-side `nix-daemon` is safe enough to keep as an optional layer. The first hardware validation on `thor` reached a No-Go preflight result: the daemon binary exists, but the current image does not provide daemon build identities and the active Nix config is still the single-user/root fallback.

## Guidance

Keep daemon mode gated behind explicit diagnostics and lifecycle controls:

```sh
nixctl daemon status
nixctl daemon preflight
nixctl daemon enable
nixctl daemon disable
nixctl daemon rollback
```

Do not enable daemon mode unless preflight passes. Current required gates are:

```text
/nix is mounted
Layer 4 real Nix exists
nix-daemon exists
nix-daemon.socket exists
nix-daemon.service exists
build-users-group is non-empty
the configured build group exists in /etc/group
```

The `nix-integration` package now has an image-time gate:

```text
NIX_DAEMON_SUPPORT=yes
```

When enabled during image build, it can add `nixbld` build identities with ROCKNIX's `add_group`/`add_user` helpers. Runtime scripts must not invent users/groups under `/storage`.

## Why This Matters

A daemon that starts without the right identity model is worse than no daemon: it can create unclear ownership, unsafe build behavior, or boot/service coupling. The current single-user/root model is known-good, so Layer 8 must prove it is safer or more useful before becoming anything more than an experiment.

The important result from `thor` is that the safety gate worked. `nixctl` refused to enable daemon mode before any persistent daemon state was created.

## Examples

On `thor`, with the Layer 8 scripts copied to `/tmp` and daemon units supplied as fixtures:

```sh
NIX_LAYER8_SYSTEMD_DIR=$PWD/system.d scripts/nixctl daemon status
```

Reported:

```text
Layer 8 (experimental daemon) status
--------------------------------------
  state:      inactive
  eligible:   unsupported: build-users-group is empty (single-user/root config)
  daemon:     /nix/var/nix/profiles/default/bin/nix-daemon
  socket:     /tmp/nix-integration-layer8-test/.../system.d/nix-daemon.socket
  service:    /tmp/nix-integration-layer8-test/.../system.d/nix-daemon.service
  sock path:  /nix/var/nix/daemon-socket/socket
  build grp:
  socket run: inactive
  service run: inactive
  fallback:   Layer 4 single-user/root Nix remains primary unless daemon is explicitly enabled
```

Doctor passed with warnings while Layer 8 was inactive:

```text
OK: Layer 8 daemon state: inactive
WARN: Layer 8 daemon eligibility: unsupported: build-users-group is empty (single-user/root config)
OK: Layer 8 socket unit present: .../nix-daemon.socket
OK: Layer 8 service unit present: .../nix-daemon.service
WARN: Layer 8 build-users-group is empty; this is expected for Layer 4 single-user/root fallback but not daemon mode
OK: Layer 8 daemon socket not present while inactive/not running: /nix/var/nix/daemon-socket/socket
OK: Layer 8 fallback: Layer 4 single-user/root Nix remains the primary recovery path
nix-doctor: passed with 4 warning(s)
```

Opt-in hardware smoke stopped at preflight:

```text
nix-integration runtime smoke passed
[layer8-smoke] pre-flight: Layer 8 daemon prerequisites
FAIL: Layer 8 daemon preflight failed
```

No daemon state was left behind:

```text
/storage/.config/nix-integration/layer8/state -> absent
```

## When to Apply

- Use the Layer 8 diagnostics when deciding whether to build an image with daemon support.
- Keep using Layers 4-7 on current SM8550 images unless `NIX_DAEMON_SUPPORT=yes` was enabled at image build time and preflight passes.
- Treat a missing `nixbld` group or empty `build-users-group` as a No-Go for host daemon mode, not as something to patch at runtime.
- If future daemon-enabled images pass preflight, then run `LAYER8_SMOKE=1` and reboot verification before documenting daemon mode as usable.

## Related

- `docs/plans/2026-05-05-004-feat-nix-layer-8-daemon-mode-plan.md`
- `docs/solutions/developer-experience/nix-layer-7-app-ui-experiments-rocknix-2026-05-05.md`
- `docs/solutions/developer-experience/nix-layer-6-managed-user-environment-rocknix-2026-05-05.md`
- `docs/solutions/developer-experience/nix-layer-5-persistent-profiles-rocknix-2026-05-05.md`
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
