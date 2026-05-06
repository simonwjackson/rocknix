---
title: ROCKNIX Layer 10 must not trust stale guest running metadata
date: 2026-05-06
category: runtime-errors
module: ROCKNIX nix-integration
problem_type: runtime_error
component: tooling
symptoms:
  - `nixctl guest status` could report a Layer 10 guest as running solely because `/storage/.config/nix-integration/layer10/state` contained `running`.
  - `nix-doctor --offline` could treat stale Layer 10 lifecycle metadata as live guest state.
  - A failed or interrupted guest start/stop sequence could leave operators with ambiguous status output.
root_cause: logic_error
resolution_type: code_fix
severity: medium
related_components:
  - nixctl
  - nix-doctor
  - systemd-nspawn
  - Layer 10 guest lifecycle
tags: [rocknix, nix, layer-10, nspawn, lifecycle, stale-state]
---

# ROCKNIX Layer 10 must not trust stale guest running metadata

## Problem

Layer 10 introduced managed `nixctl guest` lifecycle state under `/storage/.config/nix-integration/layer10`. The first implementation allowed `state=running` metadata to count as authoritative evidence that a guest was live.

That is unsafe for lifecycle management: metadata can survive an interrupted command, killed process, reboot, failed `systemctl start`, or manual cleanup. Status should prove a guest is running from live host evidence, not from a stale marker file.

## Symptoms

A stale state file such as:

```text
/storage/.config/nix-integration/layer10/state -> running
```

could make `nixctl guest status` report:

```text
state:      running
running:    yes
```

without an active `rocknix-guest.service` and without a `systemd-nspawn` process for the configured guest root.

The same logic existed in both:

- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`

## What Didn't Work

Layer 9's simpler proof-state model was a poor fit for Layer 10 lifecycle ownership. In Layer 9, `running` was mostly a proof/smoke diagnostic and a warning to clean up after a manual test. In Layer 10, `running` becomes operational state that gates `run`, `start`, `stop`, and `cleanup` decisions.

Carrying forward the Layer 9 pattern directly meant the metadata file could become a source of truth. That makes sense for states like `failed`, `proof-ready`, or `stopped`, but not for `running`.

## Solution

Make live evidence authoritative for `running`:

- `layer10_running` now checks only live unit/process evidence:
  - `systemctl is-active <guest unit>` when `systemctl` is available
  - `ps` evidence for `systemd-nspawn` referencing the configured guest root
- `layer10_state` maps stale `state=running` metadata with no live evidence to `failed`.
- `nix-doctor` uses the same model, so status and health checks agree.
- Runtime smoke now includes a stale-state fixture: write `running` to the Layer 10 state file, provide no live process/unit, and assert `nixctl guest status` reports `failed`.

Conceptually:

```sh
layer10_running() {
  systemctl is-active "$guest_unit" && return 0
  ps shows systemd-nspawn for "$guest_root" && return 0
  return 1
}

layer10_state() {
  layer10_running && echo running && return

  case "$(layer10_state_value)" in
    running) echo failed ;;   # stale running metadata
    failed|partial) echo failed ;;
    *) classify rootfs mode ;;
  esac
}
```

The regression test lives in:

```text
projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

It stages:

```text
state=running
fake nspawn present
bootable rootfs fixture present
no active unit/process evidence
```

and expects:

```text
state:      failed
```

## Why This Works

`running` is not durable state. It is a live condition. A file can record that a start was attempted or that a previous command believed the guest was active, but it cannot prove the process still exists.

By treating stale `running` metadata as `failed`, Layer 10 becomes conservative:

- `cleanup` does not assume the guest is live when it is not.
- `status` tells the operator that lifecycle state needs attention.
- `nix-doctor` flags the condition instead of hiding it behind a false healthy/running report.
- Future `start`/`stop` behavior can recover from stale state deterministically.

This matches the Layer 10 safety contract: guest lifecycle failures must surface through `nixctl guest` and `nix-doctor`, while host SSH and Layers 4/8 remain the recovery path.

## Prevention

- Do not use metadata alone as proof of liveness for managed guests, daemons, or services.
- For every `state=running` branch, require live evidence from a process, socket, unit, pidfile validation, or equivalent host-owned source.
- Treat durable state files as hints or last known state. They can prove `failed`, `stopped`, or `configured`; they cannot prove `running`.
- Add stale-state fixtures whenever lifecycle code writes state before or during process start.
- Keep `nixctl` and `nix-doctor` state machines aligned; operators should not see contradictory Layer 10 statuses.

## Related

- `docs/plans/2026-05-06-001-feat-nix-layer-10-managed-guest-operations-plan.md`
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer10-guest-lifecycle-contract.md`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
