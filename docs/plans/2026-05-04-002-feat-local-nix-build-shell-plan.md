---
title: "feat: Make local ROCKNIX builds work from a Nix flake"
type: feat
status: active
date: 2026-05-04
---

# feat: Make local ROCKNIX builds work from a Nix flake

## Overview

Add a reliable Nix-flake-powered local build environment so this checkout can build ROCKNIX on a developer machine without Docker as the default path. Nix should provide the host tooling and an FHS-compatible runtime, while the existing ROCKNIX shell build system remains authoritative for compiling the distribution.

The target outcome is: a developer can enter a Nix-provided build environment, run SM8550-oriented build entrypoints, and produce the same class of local artifacts that the Docker-based workflow produces, without installing Ubuntu packages onto the host and without mutating the host's real `/usr` or `/nix`.

## Problem Frame

The fork currently depends on GitHub Actions for full image builds, with observed turnaround around 14 hours. There is already a first-pass `flake.nix` and `.envrc`, but it is only a dependency shell/FHS wrapper, not a complete local-build workflow. The repo's build scripts still expect distro-style tools, FHS paths such as `/usr/include`, and a writable `/nix` directory because `scripts/checkdeps` prepares `/nix` before builds. Docker satisfies those assumptions today via `Dockerfile`; the flake should satisfy them locally without Docker.

The developer-facing goal is faster iteration on image-side changes like `projects/ROCKNIX/packages/tools/nix-integration/` and splash/UI changes. This plan does not attempt to convert ROCKNIX itself into Nix derivations. It uses Nix as the reproducible host environment for the existing build system.

## Requirements Trace

- R1. The flake provides all host tools required by `scripts/checkdeps` and the practical SM8550 build path, including tools present in `Dockerfile` but missing from the current flake.
- R2. The default local workflow does not require Docker or Podman.
- R3. The build environment satisfies ROCKNIX's FHS assumptions: `/usr/include/stdio.h`, `/usr/include/ncurses.h`, Perl modules, Java, font tools, image tools, and a writable `/nix` path from inside the build environment.
- R4. The workflow exposes clear SM8550 entrypoints for at least aarch64 image work and, when needed, the matching arm/compat build path used by `Makefile`.
- R5. The workflow preserves existing Docker and GitHub Actions behavior; CI remains a separate path.
- R6. The flake input set is reproducible enough for local iteration, with an explicit lock-file policy.
- R7. Docs explain how to use the local flake workflow, what it does and does not isolate, and common failure modes.

## Scope Boundaries

- Do not rewrite the ROCKNIX build system as native Nix derivations.
- Do not remove Docker targets from `Makefile`, `Dockerfile`, or `.github/workflows/`.
- Do not change package build semantics, target images, or device configuration.
- Do not require host-wide installation of Ubuntu/Debian build packages.
- Do not make full local builds mandatory for contributors; this is an opt-in developer workflow.
- Do not solve distributed binary caching in this plan. Local `ccache` usage is in scope; remote cache seeding is a separate performance project.

### Deferred to Separate Tasks

- **Remote build cache parity:** Reusing the GitHub release ccache artifacts locally could materially improve first-build time, but should be planned separately because it touches authentication, artifact download policy, and cache invalidation.
- **Self-hosted CI runner:** A local flake workflow helps this machine; replacing or supplementing GitHub Actions with a self-hosted runner is a separate infrastructure decision.
- **Nix derivation packaging of ROCKNIX outputs:** Useful long-term, but too large for this iteration.

## Context & Research

### Relevant Code and Patterns

- `flake.nix` already defines `rocknix-env` as a `buildFHSEnv` package and a default `mkShell`. It also uses a tmpfs `/nix` with the host `/nix/store` read-only bound back in, which directly addresses `scripts/checkdeps` requiring writable `/nix`.
- `.envrc` currently watches `flake.nix` and loads the flake with `--no-write-lock-file`; this favors convenience but leaves the exact nixpkgs revision floating.
- `Dockerfile` is the best parity reference for host tools: Ubuntu Jammy, locale setup, `default-jre`, Go, Python, `parted`, `xxd`, `automake`, Perl modules, font tools, `rdfind`, `xmlstarlet`, `rsync`, and writable `/nix`.
- `scripts/checkdeps` is the primary dependency contract. It verifies commands, Perl modules, `/usr/include/ncurses.h`, `/usr/include/stdio.h`, and then prepares `/nix` if needed.
- `Makefile` defines the existing SM8550 local target as an arm build followed by an aarch64 build. CI splits those into separate jobs, but local entrypoints should make the relationship explicit.
- `.github/workflows/build-aarch64*.yml` shows CI's ccache environment variables and staged build commands. The local workflow should mirror the useful environment defaults without copying GitHub artifact plumbing.
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` documents a late image-stage failure caused by a stale package reference. Local builds should make it easier to catch these before another 14-hour CI cycle.

### Institutional Learnings

- Stale entries in `projects/ROCKNIX/packages/virtual/image/package.mk` surface late and expensively during image builds. Any local build workflow should include a cheap static validation hook for package references before doing long compile work.
- The current CI improvement work already optimized the fork toward SM8550. Local flake entrypoints should default to SM8550 rather than all-device `world` builds.

### External References

- External research not used. Existing repo patterns and the current `buildFHSEnv` approach are sufficient for this plan.

## Key Technical Decisions

- **Use Nix as a host environment, not as the ROCKNIX build system.** ROCKNIX's scripts remain the source of truth. The flake supplies tools, FHS compatibility, and ergonomic entrypoints.
- **Keep `buildFHSEnv` as the no-Docker isolation layer.** It is the closest local analogue to the Docker image because ROCKNIX expects FHS paths and writable `/nix`. It still uses Linux namespaces/bubblewrap, but it avoids Docker/Podman and host package installation.
- **Align tool coverage against both `scripts/checkdeps` and `Dockerfile`.** `checkdeps` is necessary but not sufficient; the Docker image includes practical tools such as `parted`, `xxd`, Go, and `automake` that may only fail later in a full image build.
- **Commit `flake.lock` unless implementation finds a strong reason not to.** Local build reproducibility matters more than floating with `nixos-unstable` on every shell entry. `.envrc` should stop suppressing lock-file creation once the lock policy is explicit.
- **Expose specific apps for SM8550 workflows.** A generic shell is useful, but repeatable entrypoints reduce mistakes around `PROJECT`, `DEVICE`, `ARCH`, and whether the arm compat phase is needed.
- **Preserve Docker as a fallback.** Some hosts may not support unprivileged user namespaces or `buildFHSEnv` bind behavior. The plan should leave existing Docker workflows untouched and document the fallback instead of pretending every Linux host behaves the same.

## Open Questions

### Resolved During Planning

- **Should this replace Docker?** No. It should make Docker unnecessary for the normal local path, while leaving Docker and CI untouched.
- **Should the flake build ROCKNIX as Nix derivations?** No. That is much larger than the user request and would fight the existing build system.
- **Should the workflow default to SM8550?** Yes. The fork and current device work are SM8550-centered, and all-device local builds are too expensive for iteration.

### Deferred to Implementation

- **Exact missing package list after the first real local build:** Use `Dockerfile`, `scripts/checkdeps`, and any actual failures to add host tools, but do not overfit the plan to names before implementation touches the shell.
- **Whether `buildFHSEnv` works on this exact host without extra kernel/sysctl configuration:** The plan assumes a normal Nix-on-Linux host with unprivileged namespaces. If the host rejects bubblewrap, document Docker fallback and any host prerequisite separately.
- **Whether local arm compat must always precede aarch64 for the desired output:** The `Makefile` target does both. Implementation should expose both split and combined entrypoints so the developer can choose based on change scope.

## Implementation Units

- [ ] **Unit 1: Harden the flake dependency set and lock policy**

**Goal:** Make the existing flake a faithful local replacement for the Docker image's host tool layer.

**Requirements:** R1, R3, R6

**Dependencies:** None

**Files:**
- Modify: `flake.nix`
- Modify: `.envrc`
- Create or modify: `flake.lock`
- Test: `tests/local-build-flake-static-checks.sh`

**Approach:**
- Compare `mkRocknixBuildInputs` against `scripts/checkdeps` and `Dockerfile`, then add missing practical host tools rather than waiting for late image-stage failures.
- Keep the Perl module bundle as the central place for `scripts/checkdeps` Perl requirements.
- Preserve the FHS wrapper's writable `/nix` strategy: `/nix` as tmpfs inside the environment, with the Nix store visible read-only for Nix-provided tools.
- Set locale defaults matching the Docker image closely enough for deterministic build scripts.
- Establish the lock policy: commit `flake.lock` and remove `.envrc`'s `--no-write-lock-file`, unless implementation finds repo policy that forbids locks.

**Execution note:** Characterize the current flake's failure mode first, then change the smallest dependency set that satisfies `scripts/checkdeps` and the first SM8550 build stage.

**Patterns to follow:**
- `Dockerfile` package list for practical build-tool coverage.
- `scripts/checkdeps` for the formal dependency contract.
- Existing `flake.nix` `mkRocknixBuildInputs` helper for keeping package lists shared between `devShells` and `buildFHSEnv`.

**Test scenarios:**
- Happy path: inside the Nix-provided shell, every command and Perl module checked by `scripts/checkdeps` is available.
- Happy path: inside `rocknix-env`, `/nix` is writable while Nix-provided tools remain executable from the Nix store.
- Edge case: `.envrc` reloads the pinned flake without generating untracked lock-file churn after the lock policy is established.
- Error path: the static check fails if a tool listed in `scripts/checkdeps` or the Docker parity allowlist is removed from `flake.nix`.

**Verification:**
- The flake exposes a reproducible dependency environment and `scripts/checkdeps` can pass from inside the intended local build environment without installing host packages.

- [ ] **Unit 2: Add ergonomic no-Docker build entrypoints**

**Goal:** Provide clear flake apps for common SM8550 local build workflows so developers do not have to memorize environment variables or enter Docker.

**Requirements:** R2, R4, R5

**Dependencies:** Unit 1

**Files:**
- Modify: `flake.nix`
- Test: `tests/local-build-flake-static-checks.sh`

**Approach:**
- Add flake apps that run through the FHS build environment rather than directly in the plain `mkShell`.
- Provide an interactive app for entering the full build environment.
- Provide split SM8550 entrypoints for aarch64 and arm/compat paths, plus a combined SM8550 target that mirrors `Makefile` semantics.
- Default environment variables should match the fork's current target: `PROJECT=ROCKNIX`, `DEVICE=SM8550`, and the appropriate `ARCH` per entrypoint.
- Avoid hiding long-running behavior. App names and docs should make clear which entrypoints may start multi-hour builds.

**Patterns to follow:**
- `Makefile` SM8550 target for arm + aarch64 sequencing.
- `.github/workflows/build-aarch64-toolchain.yml` and `.github/workflows/build-aarch64.yml` for staged build intent.
- Existing `apps.default = rocknix-env` pattern in `flake.nix`.

**Test scenarios:**
- Happy path: flake metadata exposes named apps for entering the environment, SM8550 aarch64 build, SM8550 arm/compat build, and combined SM8550 build.
- Happy path: each app's wrapper enters the FHS environment before invoking ROCKNIX scripts.
- Edge case: overriding `DEVICE` or `ARCH` intentionally is either supported explicitly or rejected/documented; the default apps should not silently build the wrong target.
- Error path: static checks fail if the SM8550 app names disappear or stop referencing the FHS environment.

**Verification:**
- A developer can discover local build entrypoints from the flake and start the intended SM8550 build path without Docker.

- [ ] **Unit 3: Mirror useful CI ccache defaults locally**

**Goal:** Make local rebuilds benefit from ROCKNIX's existing per-build-root ccache behavior without adding remote cache complexity.

**Requirements:** R2, R4, R7

**Dependencies:** Unit 1

**Files:**
- Modify: `flake.nix`
- Test: `tests/local-build-flake-static-checks.sh`

**Approach:**
- Carry forward the non-GitHub-specific ccache environment defaults from `.github/workflows/build-aarch64*.yml`, especially compiler-check and compression settings.
- Keep ccache data in the existing ROCKNIX build root locations rather than a global host cache, so local behavior matches CI and `scripts/makefile_helper` cleanup expectations.
- Do not implement release-artifact ccache download in this unit; only make local cache behavior predictable.

**Patterns to follow:**
- `.github/workflows/build-aarch64.yml` ccache environment variables.
- `.github/workflows/build-aarch64-toolchain.yml` ccache environment variables.
- `scripts/makefile_helper` cleanup behavior for build-root `.ccache` directories.

**Test scenarios:**
- Happy path: the local build environment exports the same core ccache behavior as CI for compiler checking, compression, and sloppiness.
- Edge case: local cache settings do not force a single global cache path that would mix devices or architectures.
- Error path: static checks fail if ccache defaults are removed from the flake environment.

**Verification:**
- Local build entrypoints use predictable ccache behavior while preserving existing build-root cache isolation.

- [ ] **Unit 4: Add static validation for the local build flake**

**Goal:** Catch regressions in the flake workflow before a developer starts a multi-hour local build.

**Requirements:** R1, R3, R4, R6

**Dependencies:** Units 1-3

**Files:**
- Create: `tests/local-build-flake-static-checks.sh`
- Modify: `flake.nix`

**Approach:**
- Add a lightweight shell static check script that validates `flake.nix` contains the expected environment surfaces, app names, FHS wrapper, lock policy, and critical dependency categories.
- Expose that script through the flake's `checks` output so the normal flake validation path covers the local-build contract without starting a distribution build.
- Include checks for the late-failure class already documented in the fork: a cheap guard for stale package references in `projects/ROCKNIX/packages/virtual/image/package.mk`, if it can be implemented without needing a full build.
- Keep the test script host-friendly. It should not run a full image build, download sources, or require Docker.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` for simple shell static checks with clear failure messages.
- The stale package reference lesson in `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`.

**Test scenarios:**
- Happy path: the static check passes on the completed flake setup.
- Happy path: the flake exposes a check that runs the static validation without invoking a full ROCKNIX build.
- Error path: removing the FHS wrapper or writable `/nix` handling fails the check.
- Error path: removing an SM8550 app entrypoint fails the check.
- Error path: reintroducing a stale package reference in `projects/ROCKNIX/packages/virtual/image/package.mk` fails the check when the package cannot be found in the repo.
- Edge case: the check remains fast and does not depend on a populated build directory.

**Verification:**
- A quick static validation exists for the local flake workflow and catches the highest-cost configuration regressions.

- [ ] **Unit 5: Document the no-Docker local build workflow**

**Goal:** Make the workflow usable without reading `flake.nix` internals.

**Requirements:** R2, R4, R5, R7

**Dependencies:** Units 1-4

**Files:**
- Modify: `README.md`
- Create: `documentation/LOCAL_NIX_BUILD.md`
- Test: `tests/local-build-flake-static-checks.sh`

**Approach:**
- Add a concise README section that points to the Nix flake local build path and explicitly says Docker remains supported.
- Add a durable developer-facing build note with prerequisites, available flake apps, expected build outputs, common failures, and what is still slower locally.
- Explain the isolation boundary honestly: this is not Docker, but `buildFHSEnv` still uses bubblewrap namespaces and requires host support for them.
- Include guidance for when to run split arm/aarch64 paths versus the combined SM8550 path.
- Explain that the first full build can still be long; the value is local control, warmer incremental state, and avoiding GitHub Actions queue/artifact overhead.

**Patterns to follow:**
- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` for durable operational notes.
- `README.md` existing build-command style.

**Test scenarios:**
- Happy path: docs name the no-Docker entrypoints and the expected SM8550 output location.
- Happy path: docs describe Docker fallback without suggesting Docker was removed.
- Edge case: docs explain what to do if `buildFHSEnv`/bubblewrap cannot start on the host.
- Error path: docs warn that full local builds can still be multi-hour and should not be mistaken for instant Nix derivation builds.

**Verification:**
- A developer can follow the docs to choose the appropriate local flake entrypoint and understand fallback/recovery options.

## System-Wide Impact

- **Developer workflow:** Adds a first-class local path alongside Docker and GitHub Actions. It should reduce reliance on 14-hour CI cycles for source validation.
- **Build outputs:** Intended outputs remain under existing ROCKNIX build, release, and target directories. The plan does not change image format or install/update procedures.
- **Host mutation:** The flake should avoid host package installation and should not chown the real host `/nix`; writable `/nix` should be scoped to the FHS environment.
- **CI parity:** GitHub Actions remains Docker-based. The flake should mirror useful env defaults, not become a new CI requirement.
- **Failure modes:** If bubblewrap/FHS env fails on a host, Docker remains the fallback. If dependencies are missing from the flake, static checks and `scripts/checkdeps` should fail early.
- **Unchanged invariants:** Existing `make docker-*` targets, `.github/workflows/`, `Dockerfile`, and ROCKNIX package build semantics remain unchanged.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `buildFHSEnv` does not run on the host due to namespace restrictions | Document the prerequisite and keep Docker fallback intact. |
| Flake dependency list drifts from Docker/checkdeps over time | Add static checks and cite `Dockerfile` + `scripts/checkdeps` as the parity sources. |
| First local build is still very slow | Set expectations in docs; use ccache defaults; defer remote cache seeding to a separate task. |
| Writable `/nix` handling accidentally mutates host `/nix` | Keep the tmpfs/bind strategy inside the FHS env and test for that contract. |
| App wrappers hide long-running or destructive cleanup behavior | Name entrypoints clearly and avoid implicit clean/distclean behavior. |
| Locking nixpkgs introduces update maintenance | Treat `flake.lock` updates as explicit developer-maintenance work, similar to dependency updates. |

## Documentation / Operational Notes

- The docs should make clear that this workflow is meant for Linux hosts with Nix installed.
- The docs should distinguish plain `nix develop` from the full FHS `rocknix-env`; the latter is the supported build environment.
- The docs should call out that local build outputs can consume substantial disk space under `build.ROCKNIX-*`, `sources/`, `target/`, and `release/`.
- The docs should mention the current in-flight CI run separately only if execution has already produced evidence worth recording; otherwise keep docs evergreen.

## Sources & References

- Related code: `flake.nix`
- Related code: `.envrc`
- Related code: `Dockerfile`
- Related code: `scripts/checkdeps`
- Related code: `Makefile`
- Related code: `.github/workflows/build-aarch64.yml`
- Related code: `.github/workflows/build-aarch64-toolchain.yml`
- Related docs: `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
