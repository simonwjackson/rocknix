---
title: ROCKNIX Layer 6 managed user environment activation
last_updated: 2026-05-05
date: 2026-05-05
category: developer-experience
module: ROCKNIX nix-integration
problem_type: developer_experience
component: tooling
severity: medium
applies_when:
  - Layer 5 profile tools work and storage-local wrappers or profile snippets need reversible management
  - Adding Nix-managed user environment files without taking over ROCKNIX system paths
  - Validating activation, conflict refusal, rollback, and reboot persistence on SM8550
resolution_type: tooling_addition
related_components:
  - nix-layer-activate
  - nixctl
  - nix-doctor
  - profile.d
  - SM8550
validated_on:
  device: thor
  branch: feat/nix-layer-4-real-store
  nix_version: "2.34.7"
tags: [rocknix, nix, layer-6, activation, user-environment, sm8550]
---

# ROCKNIX Layer 6 managed user environment activation

## Context

Layer 5 made persistent CLI tools work through standard `nix profile` commands, but storage-local files still required hand management. Layer 6 adds a narrow activation engine for Nix-built user-environment bundles that can install wrappers and profile snippets under `/storage`, record ownership, refuse unsafe overwrites, and deactivate cleanly.

## Guidance

Keep Layer 6 focused on storage-file activation, not package installation. Standard `nix profile` remains the interface for CLI packages. Use Layer 6 for declared files such as:

```text
/storage/bin/<name>
/storage/.config/profile.d/<name>
```

A bundle manifest is line-oriented and busybox-shell friendly:

```text
# surface|name|source|mode
bin|rocknix-layer6-smoke|files/bin/rocknix-layer6-smoke|0755
profile.d|999-rocknix-layer6-smoke|files/profile.d/999-rocknix-layer6-smoke|0644
```

Activate and inspect through `nixctl`:

```sh
nixctl user-env preflight /path/to/bundle
nixctl user-env activate /path/to/bundle
nixctl status
nix-doctor --offline
nixctl user-env deactivate
```

## Why This Matters

ROCKNIX sources storage-local files during normal shell/UI operation, so unmanaged writes can break recovery tools or change runtime behavior in ways that are hard to unwind. Layer 6 makes ownership explicit and keeps the initial blast radius small: wrappers and profile snippets only, no autostart/systemd/system paths by default.

The important safety rules are:

- refuse non-owned target conflicts by default
- reject empty manifests so activation cannot create an active zero-file generation
- record every owned file with metadata
- fail doctor on partial state, missing targets, external edits, or missing backing sources
- refuse Layer 4 uninstall while Layer 6 is active
- deactivate before removing `/nix/store`, because active wrappers may reference store paths

## Examples

Validated on `thor`:

```sh
LAYER6_SMOKE=1 projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Observed result:

```text
[layer6-smoke] pre-flight: Layer 6 activation bundle
[layer6-smoke] activate: Layer 6 smoke bundle
[layer6-smoke] verify: wrapper and profile snippet work in a fresh shell
[layer6-smoke] diagnostics: nixctl status and nix-doctor report Layer 6 state
[layer6-smoke] conflict: non-owned target is refused and preserved
[layer6-smoke] cleanup: deactivate Layer 6 smoke bundle
nix-integration Layer 6 smoke passed
```

The default runtime smoke also exercises temporary-surface activation and guards two important failure cases:

```text
non-owned target conflict -> activation fails and preserves the user file
empty manifest -> activation fails with no active generation
```

Reboot persistence validation:

```sh
LAYER6_SMOKE=1 LAYER6_REBOOT_VERIFY=prepare projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
reboot
LAYER6_SMOKE=1 LAYER6_REBOOT_VERIFY=verify projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Observed result after reboot:

```text
[layer6-smoke] reboot verify: checking existing Layer 6 managed files after reboot
nix-integration Layer 6 reboot smoke passed
```

After verify, cleanup removed:

```text
/storage/bin/rocknix-layer6-smoke
/storage/.config/profile.d/999-rocknix-layer6-smoke
```

and Layer 6 state reported `inactive`.


## When to Apply

- Use Layer 6 when a future Nix app/UI experiment needs a wrapper or profile snippet under `/storage`.
- Do not use Layer 6 for broad dotfile management, ROMs, saves, Steam/FEX state, browser profiles, or ROCKNIX system paths.
- Defer `/storage/.config/system.d` and autostart integration until wrapper/profile activation remains boring across repeated hardware validation.

## Related

- `docs/plans/2026-05-05-002-feat-nix-layer-6-user-environment-plan.md`
- `docs/solutions/developer-experience/nix-layer-5-persistent-profiles-rocknix-2026-05-05.md`
- `docs/solutions/runtime-errors/rocknix-nix-profiled-path-reset-2026-05-05.md`
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-layer-activate`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
