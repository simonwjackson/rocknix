---
title: Trigger a fork's ROCKNIX SM8550 build via GitHub Actions when local make won't run
date: 2026-05-05
category: developer-experience
module: ROCKNIX build system
problem_type: developer_experience
component: tooling
severity: medium
applies_when:
  - The dev host cannot run ROCKNIX's local `make` flow (NixOS, missing FHS, or unsupported distro warning)
  - You need a fork-specific ROCKNIX image with custom build flags (e.g. `NIX_DAEMON_SUPPORT=yes`)
  - The official `update.rocknix.org` channel does not serve your fork
related_components:
  - tooling
tags: [rocknix, sm8550, github-actions, fork, nixos, build, ci]
---

# Trigger a fork's ROCKNIX SM8550 build via GitHub Actions when local make won't run

## Context

ROCKNIX's local build flow (`make SM8550`) expects a Debian/Ubuntu-style host with `/bin/bash`, GCC, and an FHS layout. On a NixOS dev host neither is true, and the build aborts at the dependency check:

```text
$ make SM8550
nohup: failed to run command 'make': No such file or directory
```

```text
$ build.ROCKNIX-SM8550.arm/toolchain/bin/make SM8550
PROJECT=ROCKNIX DEVICE=SM8550 ARCH=arm ./scripts/build_distro
/bin/sh: ./scripts/build_distro: /bin/bash: bad interpreter: No such file or directory
```

```text
**** This system lacks the following tools needed to build ****
... gcc, g++, perl::JSON, ... ****
**** The system appears to be a nixos system ****
**** unsupported distro nixos ****
```

The fork already has a working GitHub Actions workflow (`build-nightly.yml`) that produces a per-device `ROCKNIX-update-<DEVICE>-<DATE>` artifact. Triggering that workflow remotely is faster and more reliable than fighting the host build.

## Guidance

Push the branch, dispatch `build-nightly.yml` over the REST API with the per-device boolean input set, watch the run, then download the `ROCKNIX-update-<DEVICE>-<DATE>` artifact for the existing custom-fork deploy procedure.

### Push the branch

The Actions workflow runs against the ref you dispatch. Push your fork branch first:

```sh
git push -u origin feat/<your-branch>
```

### Read the workflow inputs

`.github/workflows/build-nightly.yml` defines `workflow_dispatch` inputs that mirror the device matrix:

```yaml
inputs:
  release: {type: boolean, default: false}
  RK3326: {type: boolean, default: false}
  ...
  SM8550: {type: boolean, default: false}
  ...
```

The custom branch's `set-envs` job uses `vars.SCHEDULE_DEVICES` (default `SM8550`) when no device boolean is set, so dispatching with no inputs already builds SM8550. Setting `SM8550=true` is explicit and unambiguous.

### Dispatch via REST API (no `gh` CLI required)

```sh
TOKEN=$(awk '/oauth_token:/ {print $2; exit}' ~/.config/gh/hosts.yml)
OWNER_REPO=simonwjackson/rocknix
REF=$(git branch --show-current)

curl -sS -X POST \
  "https://api.github.com/repos/${OWNER_REPO}/actions/workflows/build-nightly.yml/dispatches" \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d "$(jq -n --arg ref "$REF" '{ref:$ref, inputs:{release:"false", SM8550:"true"}}')"
```

The dispatch endpoint returns 204 with no body on success. Grab the run ID from the runs list right after:

```sh
curl -sS \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER_REPO}/actions/runs?branch=${REF}&event=workflow_dispatch&per_page=5" \
  | jq -r '.workflow_runs[] | select(.path==".github/workflows/build-nightly.yml") | "\(.id) \(.status) \(.html_url)"'
```

### Download the update artifact

The job uploads several artifacts. The deploy-ready one is `ROCKNIX-update-<DEVICE>-<DATE>`. The Actions API returns a ZIP wrapper around the actual `.tar` and `.tar.sha256`:

```sh
ART_ID=$(curl -sS -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER_REPO}/actions/runs/${RUN_ID}/artifacts" \
  | jq -r '.artifacts[] | select(.name | startswith("ROCKNIX-update-SM8550-")) | .id')

curl -sSL -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER_REPO}/actions/artifacts/${ART_ID}/zip" \
  -o payload.zip
```

`unzip` may not be on PATH on a NixOS host either; pull it through Nix:

```sh
nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#unzip \
  --command sh -c 'mkdir -p payload && unzip -q payload.zip -d payload'
```

The result inside `payload/`:

```text
ROCKNIX-SM8550.aarch64-<DATE>.tar
ROCKNIX-SM8550.aarch64-<DATE>.tar.sha256
```

Hand off to `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` for the on-device update.

## Why This Matters

The local-make path is the wrong tool when the host is not a supported build environment. Trying to coerce `/bin/bash`, GCC, and full FHS support onto a NixOS host is more work than the workflow it would replace, and the resulting environment drifts from CI. The fork already maintains a CI build that produces the exact artifact format the device update path expects, so dispatching the workflow gives a reproducible, fork-aware image without touching the host. Avoiding the local build also avoids one-off hacks (symlinking `/bin/bash`, FHS shims) that future contributors won't replicate.

## When to Apply

- The dev host is NixOS or any other non-Debian/Ubuntu environment ROCKNIX's `scripts/build_distro` does not support.
- You need a fork-specific image (custom `BUILD_BRANCH`, custom flags such as `NIX_INTEGRATION_SUPPORT=yes` or `NIX_DAEMON_SUPPORT=yes`) that the official `update.rocknix.org` channel cannot serve.
- You want CI-built artifacts rather than locally-built ones for reproducibility.
- Skip this procedure when the official nightly already covers your changes.

## Examples

Real run from this session:

```sh
git push -u origin feat/nix-layer-8-daemon-mode

curl -sS -X POST \
  "https://api.github.com/repos/simonwjackson/rocknix/actions/workflows/build-nightly.yml/dispatches" \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d '{"ref":"feat/nix-layer-8-daemon-mode","inputs":{"release":"false","SM8550":"true"}}'
```

Resulting run completed successfully:

```text
run_id=25361841532
status=completed
conclusion=success
html_url=https://github.com/simonwjackson/rocknix/actions/runs/25361841532
```

Artifacts produced:

```text
ROCKNIX-update-SM8550-20260505      1.86 GB
ROCKNIX-image-SM8550-20260505       1.69 GB
ROCKNIX-base-image-SM8550-20260505  386 MB
```

The `ROCKNIX-update-*` artifact unzipped to a `ROCKNIX-SM8550.aarch64-20260505.tar` + `.sha256`, which then fed straight into the existing `/storage/.update/` deploy path. ABL precheck reported `MATCH (no flash)` on both slots, the device returned in ~50s after reboot, and `OS_VERSION=20260505 BUILD_BRANCH=feat/nix-layer-8-daemon-mode` was confirmed via `/etc/os-release`.

## Related

- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` — on-device deploy of the artifact this workflow produces.
- `docs/solutions/developer-experience/nix-layer-8-daemon-mode-rocknix-2026-05-05.md` — the validation work that motivated this build.
- `.github/workflows/build-nightly.yml` — workflow inputs and `SCHEDULE_DEVICES` default.
- `.github/workflows/build-device.yml` — per-device job graph called by build-nightly.
- `Makefile` — the `make SM8550` target that doesn't work on non-FHS hosts.
