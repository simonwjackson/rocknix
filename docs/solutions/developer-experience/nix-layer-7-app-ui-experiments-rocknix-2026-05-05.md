---
title: ROCKNIX Layer 7 Nix-managed app and UI experiments
last_updated: 2026-05-05
date: 2026-05-05
category: developer-experience
module: ROCKNIX nix-integration
problem_type: developer_experience
component: tooling
severity: medium
applies_when:
  - Layer 4 real Nix, Layer 5 profiles, and Layer 6 activation are already working
  - Validating a Nix-supplied graphical app under ROCKNIX Sway without replacing EmulationStation
  - Adding storage-local app launchers that must remain reversible and ownership-tracked
resolution_type: tooling_addition
related_components:
  - nixctl
  - nix-doctor
  - nix-layer-activate
  - chromium
  - sway
  - SM8550
validated_on:
  device: thor
  branch: feat/nix-layer-7-app-ui-experiments
  nix_version: "2.34.7"
tags: [rocknix, nix, layer-7, apps, ui, chromium, sm8550]
---

# ROCKNIX Layer 7 Nix-managed app and UI experiments

## Context

Layers 4-6 proved that ROCKNIX can host a real storage-backed `/nix`, standard single-user Nix, persistent profiles, and reversible storage-local activation. Layer 7 tests the next boundary: a real Nix-supplied graphical app launched under ROCKNIX Sway without replacing EmulationStation or taking over system startup.

The first useful candidate was Chromium from `nixpkgs#chromium`, installed through the normal user profile and exposed through a Layer 6-managed launcher.

## Guidance

Keep Layer 7 split into two responsibilities:

1. Install packages with standard Nix profile commands.
2. Activate persistent launchers/profile snippets with Layer 6.

The first browser fixture lives at:

```text
projects/ROCKNIX/packages/tools/nix-integration/tests/fixtures/layer7-apps/browser/
```

It activates:

```text
/storage/bin/rocknix-layer7-browser
/storage/.config/profile.d/999-rocknix-layer7-browser
```

The launcher refuses to report ready unless the selected app binary resolves through `${HOME}/.nix-profile/bin` or `/nix/store`. A same-named binary from `/usr`, `/bin`, or unrelated `/storage/bin` is not Layer 7-ready.

Browser app state is isolated under Layer 7 experiment roots:

```text
/storage/.local/share/nix-apps/layer7/browser
/storage/.config/nix-apps/layer7/browser
/storage/.cache/nix-apps/layer7/browser
```

For Chromium on ROCKNIX/root, the launcher needs `--no-sandbox`. It also needs `CHROME_CONFIG_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` set in the Sway-launched command string; exporting them in the parent launcher process is not enough when dispatching via `swaymsg exec`. Without `CHROME_CONFIG_HOME` in the dispatched command, Crashpad writes to `/storage/.config/chromium/Crash Reports` even with `--user-data-dir` set.

## Why This Matters

Layer 7 proves Nix can provide more than CLI tools on ROCKNIX, but only if app integration stays narrow and reversible. The key safety boundary is that graphical app compatibility is package-specific: a Wayland, GPU, audio, or input failure should not be treated as a lower-layer Nix failure unless the evidence points there.

The control plane now reports Layer 7 readiness through:

```sh
nixctl status
nix-doctor --offline
```

Default runtime smoke covers activation, missing dependency behavior, unsafe binary origin, unsafe state paths, status, and doctor checks in temporary directories without launching graphics.

## Examples

Install the first candidate package on the device:

```sh
nix profile install nixpkgs#chromium
```

Run the opt-in hardware readiness smoke:

```sh
LAYER7_SMOKE=1 projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Observed on `thor`:

```text
[layer7-smoke] pre-flight: Layer 7 browser activation bundle
[layer7-smoke] activate: Layer 7 browser launcher bundle
[layer7-smoke] verify: launcher readiness uses Nix profile binary
[layer7-smoke] diagnostics: nixctl status and nix-doctor report Layer 7 state
[layer7-smoke] cleanup: deactivate Layer 7 launcher bundle
nix-integration Layer 7 smoke passed
```

Actual Sway launch was validated manually with the Layer 7 launcher. Sway reported a visible Chromium window:

```text
name: about:blank - Chromium
app_id: chromium-browser
```

The Chromium process came from the Nix store and used the isolated Layer 7 state path:

```text
/nix/store/...chromium-unwrapped.../chromium \
  --user-data-dir=/storage/.local/share/nix-apps/layer7/browser \
  --no-first-run --disable-sync --no-sandbox --ozone-platform=wayland about:blank
```

Crashpad was corrected to use the Layer 7 config root:

```text
--database=/storage/.config/nix-apps/layer7/browser/chromium/Crash Reports
```

Reboot persistence was validated by leaving the launcher active, rebooting, recopying the `/tmp` test tree, and running:

```sh
LAYER7_SMOKE=1 LAYER7_REBOOT_VERIFY=verify projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh
```

Observed result:

```text
[layer7-smoke] reboot verify: checking existing Layer 7 launcher after reboot
nix-integration Layer 7 reboot smoke passed
```

After verification, the smoke deactivated the launcher. Final state:

```text
Layer 6 state: inactive
Layer 7 launcher: inactive
Layer 7 app binary: /storage/.nix-profile/bin/chromium -> /nix/store/.../bin/chromium
nix-doctor: passed with 2 warning(s)
```

## When to Apply

- Use Layer 7 for manually launched Nix apps or UI dependencies after Layers 4-6 are healthy.
- Use Layer 6 for persistent launcher files; do not hand-copy app launchers into `/storage/bin`.
- Keep each app candidate isolated and document package-specific Wayland/GPU/audio/input findings.
- Do not add autostart, systemd, Ports catalog integration, or default UI replacement until manual launch and cleanup are boring.

## Related

- `docs/plans/2026-05-05-003-feat-nix-layer-7-app-ui-experiments-plan.md`
- `docs/solutions/developer-experience/nix-layer-6-managed-user-environment-rocknix-2026-05-05.md`
- `docs/solutions/developer-experience/nix-layer-5-persistent-profiles-rocknix-2026-05-05.md`
- `docs/solutions/best-practices/manual-steam-game-launching-rocknix-arm64-2026-05-04.md`
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`
- `projects/ROCKNIX/packages/tools/nix-integration/docs/layer7-app-experiment-contract.md`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`
