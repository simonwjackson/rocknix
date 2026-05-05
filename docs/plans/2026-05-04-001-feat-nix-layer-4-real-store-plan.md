---
title: "feat: Nix Layer 4 — standard single-user Nix on real /nix"
type: feat
status: active
date: 2026-05-04
origin: docs/brainstorms/2026-05-04-001-nix-layer-4-real-store.md
---

# feat: Nix Layer 4 — standard single-user Nix on real /nix

## Overview

Layers 1-3 of the ROCKNIX nix-integration package are validated end-to-end on real SM8550 hardware. Today, every nix invocation goes through `nix-portable` under proot, which has measurable overhead and known compatibility limits. Layer 4 installs **real, standard, single-user, root-owned Nix** directly onto the storage-backed `/nix` mount provided by Layer 3.

The change is small in image-rebuild surface (one new script in `/usr/bin`, two `$PATH` additions in profile.d) and most of the lifecycle (install, uninstall, upgrade) lives entirely in `/storage` and runs at runtime from SSH. After this lands, daily-driver workflows on the device — `nix run`, `nix-shell -p`, eventually `nix profile install` (Layer 5) — execute against real Nix without proot in the loop.

## Problem Frame

Real nix on a real `/nix` is the prerequisite for several capabilities the device owner wants today:
- **Performance**: proot's syscall translation imposes per-call overhead on every Nix operation. Real nix using normal POSIX should be obviously faster on representative dev workflows.
- **Compatibility**: ptrace-using tools (gdb, strace) and packages with unusual sandbox requirements misbehave or fail under proot. Real nix should run them cleanly.
- **Profiles foundation**: `nix profile install` requires a real `/nix/var/nix/profiles/` hierarchy. Layer 5 lands almost for free as a follow-up once Layer 4 is in.
- **Bounded next step**: significantly smaller scope than Layer 9 (NixOS via nspawn), which is a separate strategic bet.

The user is the device owner doing development work over SSH. End users running EmulationStation games are unaffected — Layer 4 imposes zero load when nix is not in use.

(see origin: `docs/brainstorms/2026-05-04-001-nix-layer-4-real-store.md`)

## Requirements Trace

Carried forward from the origin document. Stable IDs match the requirements doc.

**Behavior**
- R1. After install, `nix` resolves to real Nix in any login shell. `which nix` returns a `/nix/var/nix/profiles/default/bin/` path.
- R2. `nix run nixpkgs#<pkg>`, `nix-shell -p <pkg>`, and `nix build` work directly without invoking `nix-portable`.
- R3. `nix profile install <pkg>` succeeds and the resulting binary is on `$PATH` in subsequent SSH sessions.
- R4. The portable wrapper at `/storage/bin/nix-portable*` remains present and functional. Users can still invoke nix-portable explicitly.

**Installation and Lifecycle**
- R5. A single command performs the install end-to-end at runtime. Build-time profile.d work delivers the `$PATH` ordering.
- R6. The installer is idempotent.
- R7. A clean uninstall returns the system to the Layer 3 substrate.
- R8. `nix-doctor` is extended with Layer 4 checks.

**Configuration**
- R9. Nix configuration in `~/.config/nix/nix.conf` (= `/storage/.config/nix/nix.conf`), not `/etc/nix/`.
- R10. Sandbox is empirically probed; `sandbox = true` if a small sandboxed build succeeds, `sandbox = false` otherwise. Either is a valid Layer 4 install.
- R11. Substituter is `https://cache.nixos.org` with the standard public key.

**Coexistence and Reversibility**
- R12. Layer 4 install does not modify ROCKNIX boot, EmulationStation, Sway, Steam, Chromium, or any game-runtime path.
- R13. Recovery is documented, not coded: `rm -rf /storage/.nix-root && reboot` or full reflash.

## Scope Boundaries

**Out of scope:**
- Multi-user Nix with `nix-daemon`, `nixbld*` users, and trusted-users config. Structurally impossible (no `useradd`/`groupadd`); deferred to Layer 8 if ever revisited (likely retired in favor of Layer 9).
- Persistent profiles with auto-`$PATH` integration on every login. That is Layer 5.
- NixOS configuration management of host services. That is Layer 9 (separate strategic bet).
- Migration of nix-portable's existing on-disk store into the real `/nix/store`. The two stores are independent.
- Any change to ROCKNIX boot, kernel, or service definitions outside the Nix-integration package.
- A graphical or EmulationStation-integrated entry point for Nix. SSH-only.

### Deferred to Separate Tasks
- **Layer 5 (persistent profiles)**: Will land as a follow-up plan once Layer 4 is validated. Layer 4's profile.d work pre-positions the `$PATH` ordering Layer 5 needs.
- **Image rebuild + on-device validation**: Plan execution produces source changes only. The image rebuild and on-device validation cycle uses the same procedure documented in `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`.

## Context & Research

### Relevant Code and Patterns

- **Existing nix-integration package**: `projects/ROCKNIX/packages/tools/nix-integration/` — Layer 4 extends this package, not a new one. Mirror its conventions throughout.
- **`nix-portable-install` script** at `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-portable-install` (265 lines) — pattern for `nixctl install`: download with sha256 verification, atomic-ish install into `/storage`, idempotent re-runs, install/repair/remove/status subcommands, environment-variable overrides for every URL/path/version.
- **`nix-doctor` script** at `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor` — pattern for adding Layer 4 checks: extend with conditional checks that activate when real nix is detected on disk.
- **`profile.d/998-nix-integration.conf`** — currently sets `NP_*` env vars and prepends `/storage/bin` to `$PATH`. Layer 4 modifies it to additionally prepend `/nix/var/nix/profiles/default/bin` and `${HOME}/.nix-profile/bin` ahead of `/storage/bin`.
- **`tests/nix-integration-static-checks.sh`** — pattern for static-check tests: shell syntax, executable bit, presence of expected files. Add `nixctl` and any new helper scripts.
- **`tests/nix-integration-runtime-smoke.sh`** — pattern for runtime smoke tests on the device. Layer 4 adds an opt-in path that exercises the install/use/uninstall cycle.
- **`package.mk` `post_install` hook** — pattern for shipping new scripts into `/usr/bin` at image build time. Layer 4 adds `nixctl` here.

### Institutional Learnings

- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` — describes the image-rebuild-and-flash cycle. Layer 4 will require one such cycle to ship the build-time changes (profile.d, `/usr/bin/nixctl`, package.mk wiring); thereafter all install/uninstall/upgrade cycles are runtime-only.
- `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md` — original layered plan. Section "Unit 5: Layer 4 — Standard single-user/root Nix" is the high-level intent this plan operationalizes.
- `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md` — earlier handoff that proposed `nixctl use-portable` / `use-standard` mode-switching commands. **The brainstorm doc deliberately rejected this design** in favor of real nix as primary on `$PATH` with no mode-switch verb. This plan follows the brainstorm. Documented under Key Technical Decisions for traceability.

### External References

- **Nix binary tarball release pattern**: `https://releases.nixos.org/nix/nix-<version>/nix-<version>-aarch64-linux.tar.xz`. The tarball contains an embedded `/nix/store/*` closure (Nix's own dependencies) and a `.reginfo` file usable with `nix-store --load-db` to register the closure.
- **`nix-store --load-db` and `--register-validity`**: documented in `nix-store(1)`. Standard mechanism for populating a fresh `/nix/store/` from a known-valid set of paths without re-substituting from a binary cache.
- **cache.nixos.org public key**: `cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=` (well-known constant, baked into nix.conf).

## Key Technical Decisions

- **Use the official upstream installer with env overrides, not a manual reimplementation.** *(Deviation from the original plan; resolved during Unit 3 implementation.)* The plan originally favored a manual install on the assumption that the upstream `install` script would fight ROCKNIX's read-only `/etc`, missing sudo, and root-only model. Investigation during Unit 3 showed the script can be coerced into clean compliance with three env vars (`NIX_INSTALLER_NO_MODIFY_PROFILE=1`, `NIX_INSTALLER_NO_CHANNEL_ADD=1`, `NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`) plus two ROCKNIX-specific patches applied at install time: a sed replacing `cp -RP --preserve=ownership,timestamps` with `cp -RPp` (busybox cp compatibility), and writing `nix.conf` with `build-users-group=` empty *before* running the installer (so its final `nix-env -i $nix` step does not try to use the missing `nixbld` group). This is significantly less code than reimplementing the installer's logic and stays aligned with upstream's evolving conventions.

- **Pin the Nix version in source, defaultable via env var.** Mirrors the Layer 1/2 approach for `nix-portable v012`. Specific version selected during this plan's implementation (latest stable at the time, e.g., `2.24.10`) and recorded as `NIX_VERSION` constant in `nixctl`. Provides reproducibility, sha256-verifiable downloads, and a deliberate upgrade ritual via `nixctl upgrade`.

- **No `nixctl use portable|native` mode-switching command.** Brainstorm rejected this in favor of real-nix-as-primary on `$PATH`, with portable still callable explicitly via `/storage/bin/nix-portable`. Justification: the device has no production state worth a graceful rollback; reflash + `rm -rf /storage/.nix-root` is faster than maintaining a mode-switch abstraction. Supersedes `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md` Layer 4 design.

- **Profile.d edited at build time, not install time.** `/etc` is read-only at runtime. The PATH-ordering change must ship in the package via `998-nix-integration.conf`. The path entries `/nix/var/nix/profiles/default/bin` and `${HOME}/.nix-profile/bin` are present in `$PATH` even on devices where Layer 4 has never been installed; an empty bin directory is harmless — the shell finds nothing there and falls through to `/storage/bin` (portable wrappers).

- **Sandbox empirical probe with documented fallback.** During install, run a small sandboxed build. If it succeeds, `nix.conf` gets `sandbox = true`; if it fails (kernel feature missing, bpf restriction, etc.), the installer logs the reason and writes `sandbox = false`. Both outcomes are valid Layer 4 installs. Building a robust priori check from the kernel config is more code than it is worth — the build either succeeds or it does not.

- **Config in `~/.config/nix/nix.conf`, not `NIX_CONF_DIR=/storage/etc/nix`.** XDG-conventional, survives nix upgrades cleanly, no extra environment-variable plumbing in profile.d.

## Open Questions

### Resolved During Planning

- **Q: Does the official tarball install script work with overrides on RO `/etc`?** **A:** Plan does not use it. Manual install instead.
- **Q: How does `~/.nix-profile/bin` reach `$PATH`?** **A:** Profile.d explicitly prepends both `/nix/var/nix/profiles/default/bin` and `${HOME}/.nix-profile/bin` at build time. We do not source nix's `nix.sh`; explicit-prepend is simpler and equally effective.
- **Q: Pin nix version or float?** **A:** Pin. `NIX_VERSION` constant in `nixctl`, env-var-overridable.
- **Q: What does clean uninstall remove?** **A:** `/nix/store/*`, `/nix/var/*` (everything under the bind mount except the empty mount point), `~/.config/nix/`, `~/.nix-defexpr`, `~/.nix-profile` (symlink), `~/.nix-channels`. Leaves the Layer 3 bind mount itself intact.

### Deferred to Implementation

- **Exact Nix version and sha256 to pin.** Decided when the implementer fetches the latest stable from `releases.nixos.org`. The version is recorded as a constant in `nixctl` source.
- **Exact representative perf workflow for the comparison fixture.** Candidates: `nix-shell -p python3 --run 'python3 -c "import json; print(...)"'` (cold-cache parsing/import work) versus `nix-shell -p jq --run 'echo {} | jq .'` (faster steady-state). Implementer picks one for the smoke-test bench harness during Unit 6; the precise choice does not affect correctness, only the acceptance demo.
- **Exact compat-positive fixture (something that fails under proot but works under real nix).** Strong candidate: `nix-shell -p strace --run 'strace -e trace=write echo hello'` because proot itself uses ptrace and cannot be ptraced inside. Implementer confirms during Unit 6 by running it under both portable and real nix.
- **Exact sandbox probe expression.** Implementer writes a small `nix build` invocation against a derivation that exercises the sandbox (e.g., a no-op derivation with a builder that writes to `$out`). The exact expression is plumbing detail.
- **Whether to include `experimental-features = nix-command flakes` in default nix.conf.** Likely yes (the brainstorm assumes flakes work in R2's `nix run nixpkgs#<pkg>`). Confirmed during Unit 3 implementation.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
nixctl <verb>
  ├─ status        → read-only: report installed/not, version, sandbox setting, /nix layout
  ├─ install       → download tarball → verify sha256 → extract to /storage cache
  │                   → cp embedded store into /nix/store/
  │                   → nix-store --load-db < .reginfo
  │                   → set up /nix/var/nix/profiles/per-user/root/profile
  │                   → ln -s ... ~/.nix-profile
  │                   → write ~/.config/nix/nix.conf
  │                   → probe sandbox (small build); if fails, rewrite sandbox=false
  │                   → final: nix --version smoke
  ├─ upgrade       → install with new version; idempotent if already at target
  ├─ uninstall     → rm /nix/store/* /nix/var/* ~/.config/nix ~/.nix-{defexpr,profile,channels}
  └─ doctor        → delegates to nix-doctor with --layer4 flag

profile.d/998-nix-integration.conf  (built into image, always present):
  PATH = ${HOME}/.nix-profile/bin : /nix/var/nix/profiles/default/bin : /storage/bin : ...
         ────────── L5 ─────────── ─────────── L4 ────────────── ─── L1/2 ──
  When neither L4 nor L5 is installed, the L4/L5 prefixes resolve to nothing
  and the shell falls through to /storage/bin. No coordination required.
```

## Implementation Units

- [x] **Unit 1: Build-time profile.d and package.mk wiring**

**Goal:** Bake the `$PATH` ordering and ship the `nixctl` script via the existing `nix-integration` package. After this unit, image rebuilds carry the prefix even on devices with no Layer 4 installed; the empty-bin fall-through is harmless.

**Requirements:** R5 (build-time portion), R12 (no boot impact)

**Dependencies:** None

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/profile.d/998-nix-integration.conf`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/package.mk`

**Approach:**
- Profile.d update: prepend `${HOME}/.nix-profile/bin` and `/nix/var/nix/profiles/default/bin` to `$PATH`, ahead of the existing `/storage/bin` entry. Use the same `case` guard against duplicate entries that the file already uses for `/storage/bin`.
- `package.mk`: add `cp ${PKG_DIR}/scripts/nixctl ${INSTALL}/usr/bin` and `chmod 0755 ${INSTALL}/usr/bin/nixctl` next to the existing entries for `nix-portable-install`/`-run`/`nix-doctor`.

**Patterns to follow:**
- Existing `case`-guard idiom in `998-nix-integration.conf` for the `/storage/bin` prepend.
- Existing copy/chmod block in `package.mk`'s `post_install`.

**Test scenarios:**
- Edge case: profile.d sourcing succeeds when neither real nix nor `~/.nix-profile` exists — verified via `sh -n` syntax check and a static-check that sources the file in a clean environment.
- Edge case: re-sourcing the file does not duplicate `$PATH` entries — verified by sourcing twice in a test harness and grepping the resulting `$PATH`.
- Integration: a fresh image build includes `/usr/bin/nixctl` — verified in CI by inspecting the produced SYSTEM squashfs (existing image-validation tests can be extended to assert presence).

**Verification:**
- Static checks pass on the modified profile.d file.
- `nixctl` binary lands in `/usr/bin/` after a fresh build, executable, with correct content.
- On a device that has never run Layer 4 install, `echo $PATH` shows the new prefix entries before `/storage/bin`, and the system continues to boot and function exactly as today (Layer 1/2 unaffected).

---

- [x] **Unit 2: `nixctl` script skeleton + `status` subcommand**

**Goal:** Land the read-only entry point first. `nixctl status` reports whether real Nix is installed, what version, where its store is, what the sandbox setting is, and what `/nix` is bound to. Easy first land — exercises the file layout, environment variable overrides, and usage strings without any destructive operations.

**Requirements:** R5 (front-door), R6 (idempotent skeleton)

**Dependencies:** Unit 1

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`

**Approach:**
- Mirror the structure of `nix-portable-install`: shebang, license header, `set -eu`, environment-variable defaults at the top (`NIX_VERSION`, `NIX_TARBALL_URL_TEMPLATE`, `NIX_TARBALL_SHA256`, `NIX_INSTALL_ROOT=/nix`, `NIX_USER_CONFIG_DIR=${HOME}/.config/nix`, `NIX_CACHE_DIR=/storage/.cache/nix-install`), `usage()` function, top-level subcommand dispatch.
- `status` reads `/nix/var/nix/profiles/default/bin/nix --version` if present, parses `~/.config/nix/nix.conf` for sandbox setting, calls `findmnt /nix` (or `mount | grep` fallback) to confirm the bind, and prints a structured report.
- All other subcommands (`install`, `upgrade`, `uninstall`, `doctor`) print "not yet implemented" until later units land. Exit cleanly.

**Patterns to follow:**
- Variable-override-at-the-top pattern from `scripts/nix-portable-install`.
- `usage()` function shape and the case-based subcommand dispatch.

**Test scenarios:**
- Happy path: `nixctl status` on a system with no Layer 4 installed reports "not installed" with non-zero detail (e.g., the `/nix` mount status from Layer 3 still shown).
- Happy path: `nixctl --help` and `nixctl` (no args) print usage and exit 0.
- Edge case: `nixctl status` with `/nix` not bind-mounted reports the discrepancy without crashing.
- Error path: unknown subcommand prints usage to stderr, exits non-zero.

**Verification:**
- `nixctl status` runs cleanly on a Layer 3 device and reports "real nix not installed" with a clear next-step hint.
- All declared subcommands are reachable and either print structured "not yet implemented" or run their real logic (post-later-units).

---

- [x] **Unit 3: `nixctl install` with sandbox probe**

**Goal:** Implement the manual install path: download Nix binary tarball, verify, extract, populate `/nix/store/`, register the closure DB, set up profiles and `~/.nix-profile` symlink, write `nix.conf`, probe sandbox, finalize. Idempotent — re-running is a no-op when the target version already matches.

**Requirements:** R1, R2, R5, R6, R9, R10, R11

**Dependencies:** Unit 2

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`

**Approach:**
- Pin `NIX_VERSION` and `NIX_TARBALL_SHA256` as constants near the top of `nixctl`. The implementer selects the latest stable Nix release at implementation time (e.g., `2.24.X`).
- Download flow: `curl -L --fail -o "${NIX_CACHE_DIR}/nix-${NIX_VERSION}.tar.xz" "${tarball_url}"` → `sha256sum -c` against the pinned hash → extract to `${NIX_CACHE_DIR}/nix-${NIX_VERSION}/`.
- Store population: copy the tarball's embedded `/nix/store/*` into `/nix/store/` (the bind-mounted `/storage/.nix-root/store/`). Cheap and atomic; the embedded closure is a few hundred MB at most.
- Closure DB: `/nix/store/.../bin/nix-store --load-db < ${extracted}/.reginfo` — registers the validity of the embedded paths so subsequent `nix` invocations recognize them.
- Profile setup: create `/nix/var/nix/profiles/per-user/root/`, populate the default profile by symlinking the just-installed nix package, set `/nix/var/nix/profiles/default` → `per-user/root/default`, and create `~/.nix-profile` → `/nix/var/nix/profiles/per-user/root/profile`.
- `nix.conf`: write to `~/.config/nix/nix.conf` with `substituters = https://cache.nixos.org/`, the standard public key, and `sandbox = true`.
- Sandbox probe: run a small `nix build` against a derivation that exercises the sandbox. If the build fails with a sandbox-specific error, rewrite `nix.conf` to set `sandbox = false`, log the reason, and retry. The set of sandbox-failure error patterns to detect is implementer judgement; conservative is to fall back on any non-zero exit from the probe.
- Final: invoke `${NIX_INSTALL_ROOT}/var/nix/profiles/default/bin/nix --version` and assert success. Print a structured summary: version, sandbox setting, store location.
- Idempotency: at the top of `install`, check if `~/.config/nix/nix.conf` exists AND `${NIX_INSTALL_ROOT}/var/nix/profiles/default/bin/nix --version` reports the pinned version. If both true, no-op with a clear "already at version X" message.

**Execution note:** This is the riskiest unit. Add a static check that the script's commands are syntactically valid even before the runtime environment exists. Smoke-test the install path on the device manually before committing to image-rebuild iteration cycles.

**Patterns to follow:**
- Download + verify pattern from `scripts/nix-portable-install`'s `download_artifact()`.
- Idempotency pattern: check-target-state-first, no-op if already in target state.

**Test scenarios:**
- Happy path: `nixctl install` on a fresh Layer 3 device with no real nix installed completes successfully; `nix --version` reports the pinned version; `which nix` resolves to `/nix/var/nix/profiles/default/bin/nix`.
- Happy path: re-running `nixctl install` after a successful install is a no-op with a clear "already installed" message.
- Edge case: install on a device with an older real-nix install upgrades cleanly (effectively the upgrade path; Unit 4 surfaces it as a separate verb but this is the same code path).
- Error path: sha256 mismatch on the downloaded tarball aborts the install before any `/nix` mutation, leaves the system in pre-install state, exit non-zero with a clear message.
- Error path: sandbox probe fails — installer rewrites `nix.conf` to `sandbox = false`, logs the reason, continues, and the final `nix --version` still succeeds. Both `sandbox = true` and `sandbox = false` outcomes are valid passes.
- Error path: download fails (network down, server returns 5xx) — install aborts cleanly without partial `/nix` mutation, exit non-zero.
- Integration: after install, opening a fresh SSH session shows `which nix` resolving to the real-nix path (verifies Unit 1's profile.d work + Unit 3's install agree).

**Verification:**
- On a fresh Layer 3 device, a single `nixctl install` invocation produces a working real-nix installation that survives reboot (because everything lives under `/storage`, which Layer 3 persists).
- `nix run nixpkgs#hello` works without invoking nix-portable (verify by checking process tree: no `proot` or `nix-portable` parent processes).

---

- [x] **Unit 4: `nixctl uninstall` and `nixctl upgrade`**

**Goal:** Complete the lifecycle. Uninstall returns the system to the Layer 3 substrate; upgrade is a thin wrapper around install with a different version.

**Requirements:** R6, R7

**Dependencies:** Unit 3

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`

**Approach:**
- `uninstall`: delete `/nix/store/*`, `/nix/var/*`, `~/.config/nix/`, `~/.nix-defexpr`, `~/.nix-profile` (the symlink), `~/.nix-channels` if present. Leave the `/nix` bind mount itself untouched (Layer 3 owns it). Print a structured summary of what was removed and confirm `which nix` no longer resolves to a real-nix path (it should now resolve to `/storage/bin/nix` — the portable wrapper — or be unfound if even portable is uninstalled).
- `upgrade`: parse a target version from `--version <X.Y.Z>` argument (default: re-read the pinned `NIX_VERSION` constant), then call the install path. Idempotency in `install` handles the "already at target" case.
- Add a confirmation prompt for `uninstall` (interactive only, skippable with `--yes`) — destructive operations should fail safe.

**Patterns to follow:**
- `remove` subcommand pattern from `scripts/nix-portable-install`.

**Test scenarios:**
- Happy path: `nixctl uninstall` on a system with real nix installed removes all artifacts, leaves Layer 3 bind mount intact (`mount | grep /nix` still shows it), `which nix` resolves to `/storage/bin/nix` (portable wrapper).
- Happy path: `nixctl uninstall` followed by `nixctl install` produces a working install (full cycle reversibility).
- Happy path: `nixctl upgrade --version <newer>` upgrades cleanly when newer version differs from current.
- Edge case: `nixctl upgrade` to the currently installed version is a no-op via install's idempotency path.
- Error path: `nixctl uninstall` without `--yes` in a non-interactive shell aborts cleanly.
- Error path: `nixctl uninstall` on a system without real nix installed prints "nothing to uninstall" and exits 0 (idempotent).
- Integration: after uninstall, `nix-portable-install install` (Layer 1/2's installer, untouched) still works correctly — Layer 4's lifecycle does not interfere with Layer 1/2's lifecycle.

**Verification:**
- The full install → use → uninstall → install cycle is repeatable without manual intervention on the device.
- After uninstall, the device is in a Layer-3-only state indistinguishable from a device that had never run Layer 4.

---

- [x] **Unit 5: `nix-doctor` Layer 4 extensions**

**Goal:** Extend the existing `nix-doctor` script to report Layer 4 readiness when real nix is detected on disk. Layer 1/2 checks remain unchanged.

**Requirements:** R8

**Dependencies:** Unit 3 (so the things doctor checks for can exist)

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor`

**Approach:**
- Add a conditional block that activates when `/nix/var/nix/profiles/default/bin/nix` exists. If absent, doctor's behavior is unchanged from today.
- New checks under the conditional:
  - real-nix binary exists and is executable
  - `nix --version` succeeds (no proot in the process tree)
  - `~/.config/nix/nix.conf` exists and is readable
  - sandbox setting in nix.conf is parseable (records what it is, doesn't fail either way)
  - `/nix` is bind-mounted from `/storage/.nix-root` (already a Layer 3 check; just confirm not regressed)
  - `~/.nix-profile` symlink resolves correctly
  - `which nix` resolves to the real-nix path (verifies profile.d + install agreement)
- Optional: a `--dev-shell-smoke` extension that runs against real nix instead of portable when real nix is detected as primary.

**Patterns to follow:**
- Conditional-section pattern in existing `nix-doctor`. The current script already has flag-gated sections (`--no-smoke`, `--dev-shell-smoke`). Add a new section gated by "real nix detected on disk", auto-activated.

**Test scenarios:**
- Happy path: doctor on a Layer 3 device (no Layer 4 installed) behaves identically to today, no Layer 4 lines in output.
- Happy path: doctor on a Layer 4 device prints the new checks, all pass, exit 0.
- Edge case: Layer 4 partially installed (e.g., real-nix binary exists but `~/.config/nix/nix.conf` was manually deleted) — doctor reports the specific missing artifact, exit non-zero.
- Edge case: `which nix` resolves to portable instead of real (profile.d not yet sourced in this shell, or build-time profile.d not deployed yet) — doctor flags this as a warning, not a failure (operationally the user can still run real nix directly).

**Verification:**
- On a Layer 4 device, `nix-doctor` passes all checks and reports the configured sandbox setting.
- On a Layer 3-only device, `nix-doctor` output is unchanged from today's behavior.

---

- [x] **Unit 6: Tests — static checks and runtime smoke**

**Goal:** Extend existing test scaffolding to cover the new `nixctl` script and the Layer 4 happy path. Static checks run in CI; runtime smoke runs on the device.

**Requirements:** Tests for R1, R2, R5, R6, R7, R8 (verifying via the test harness, not via implementation discipline alone)

**Dependencies:** Units 2, 3, 4, 5

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- **Static checks**: add `nixctl` to the existing `check_script` calls. Add an assertion that the new profile.d entries are present in `998-nix-integration.conf`. Add a syntax-check pass over `nixctl` (`sh -n`) and a usage-string presence check.
- **Runtime smoke** (opt-in, gated by an env var or flag like `LAYER4_SMOKE=1`):
  1. `nixctl status` → expects "not installed" if running on a clean device
  2. `nixctl install` → expects success
  3. `nix --version` → expects real nix version (validate by checking process tree has no `proot`)
  4. Representative perf workflow (e.g., `nix-shell -p jq --run 'echo {} | jq .'`) timed
  5. Compat-positive workflow (e.g., `nix-shell -p strace --run 'strace -e write echo hi'`) — succeeds under real nix where it would fail or behave oddly under proot
  6. `nixctl uninstall --yes` → expects clean removal
  7. `nix-portable --version` (the explicit-call fallback) → expects success (R4: portable still works after Layer 4 cycle)
- Smoke test does not gate on perf numbers (per brainstorm "Pragmatic" criterion) but records timings to stdout for human inspection.

**Patterns to follow:**
- Existing `nix-integration-static-checks.sh` `check_script` pattern.
- Existing `nix-integration-runtime-smoke.sh` shape and exit-code conventions.

**Test scenarios:**
- Static checks: pass on a clean repo; fail with a clear message if `nixctl` is missing, non-executable, or has a syntax error.
- Static checks: fail with a clear message if `998-nix-integration.conf` is missing the new path entries.
- Runtime smoke: end-to-end install/use/uninstall cycle completes without manual intervention on a Layer 3 device.
- Runtime smoke: emits a perf-comparison line ("real nix: Xs, portable: Ys") for human review without failing on the difference.

**Verification:**
- Static checks pass in CI on every commit.
- Runtime smoke, when manually invoked on the device, exercises the full Layer 4 lifecycle and leaves the device in the original Layer 3 state.

---

- [x] **Unit 7: Documentation**

**Goal:** Update the device-specific Nix experiment doc with Layer 4 usage. New users picking up the device should be able to install real nix from the doc alone.

**Requirements:** Documentation; no direct functional requirement, but supports R5 by giving users the runtime command surface.

**Dependencies:** Units 1-6

**Files:**
- Modify: `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md`

**Approach:**
- Add a "Layer 4: Standard Nix on real `/nix`" section after the existing Layer 1-3 sections.
- Cover: what Layer 4 is, prerequisites (Layer 3 active), install command, status command, uninstall, upgrade, troubleshooting (sandbox = false fallback, what to do if `which nix` still resolves to portable).
- Cross-reference the recovery procedure documented in `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` for the "if all else fails" path.
- Document the explicit-call fallback: `nix-portable` is still available even when real nix is primary.
- Note the build-time vs runtime split: profile.d ships with the image; install/uninstall are runtime.

**Patterns to follow:**
- Existing structure of `NIX_EXPERIMENT.md` (Layer-by-Layer sections with command examples).

**Test scenarios:**
- Test expectation: none — pure documentation. Verify by reading and following the steps yourself on the device.

**Verification:**
- A newcomer reading the doc top-to-bottom can install Layer 4, run a sample workflow, and uninstall, without consulting outside sources.

## System-Wide Impact

- **Interaction graph**: Layer 4's `$PATH` entries (Unit 1) take effect on **every login shell** on the device — including SSH, console TTYs, and any shell launched from EmulationStation/Sway. The empty-bin fall-through is the safety property: if real nix is not installed, those PATH entries resolve nothing and behavior is identical to today. If something else later writes binaries into `/nix/var/nix/profiles/default/bin/` (extremely unlikely but possible), they would shadow `/storage/bin` entries with the same name. No current ROCKNIX components do this.
- **Error propagation**: install failures are isolated — `nixctl install` aborts on any error before mutating `/nix` (download/verify gate). After mutation begins, the system can be left in a partial state, but `nixctl uninstall` cleans it up. Profile.d sourcing failures cannot occur because the file uses `case`-guards, not destructive operations; even if `$HOME` is unset, sourcing succeeds with no-op for that path entry.
- **State lifecycle risks**: `/nix/store/*` lives on `/storage` (via Layer 3 bind), shared with everything else on `/storage`. A full Nix store can grow large over time. Mitigation: documented `nix store gc` advice in Unit 7; not automated. ROCKNIX's `/storage` is 90+ GB on this device; a few GB of Nix store is well within budget.
- **API surface parity**: The `nixctl` command is a new public surface. Its environment-variable overrides (`NIX_VERSION`, `NIX_INSTALL_ROOT`, `NIX_USER_CONFIG_DIR`, `NIX_CACHE_DIR`) constitute a contract. Document them in usage strings and `NIX_EXPERIMENT.md`.
- **Integration coverage**: Unit 6's runtime smoke test exercises the install→use→uninstall cycle as a single integration test. This is the only place in this plan where the multi-script interaction (profile.d + nixctl + nix-doctor + nix-portable still working) is verified end-to-end.
- **Unchanged invariants**:
  - ROCKNIX boot, `EmulationStation`, Sway, Steam, Chromium: untouched. Verified by R12 and the no-op-when-empty `$PATH` design.
  - `nix-portable-install` and the Layer 1/2 wrapper scripts: untouched. Verified by Unit 6 step 7 (explicit `nix-portable --version` after Layer 4 cycle).
  - `nix-storage-setup.service` and `nix.mount`: untouched. Layer 4 lives entirely in user-space at runtime.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Sandbox probe gives a false negative (sandbox could work but probe fails for unrelated reasons) | Probe is conservative — `sandbox = false` is a valid Layer 4 install per R10. Implementer can manually flip to `sandbox = true` and retry; documented in Unit 7. |
| Pinned Nix version becomes outdated; `cache.nixos.org` evicts the closure | Realistic risk over months. Mitigation: `nixctl upgrade --version <newer>` is a one-command refresh. Pinned hash makes the failure mode explicit (sha mismatch on install) rather than silent corruption. |
| Manual install path drifts from official Nix install behavior over Nix releases | The manual install does narrow, well-defined operations (extract store, register DB, set up profiles). These are stable Nix internals across releases. Quarterly re-verification of `nixctl install` against a current Nix version is sufficient. |
| `~/.nix-profile/bin` listed in `$PATH` even when not present | Harmless: the shell silently skips missing PATH entries. No diagnostic noise. |
| First-time `nix build` of anything substantial is slow on aarch64 device | Out of scope. Real nix uses `cache.nixos.org` substituters by default; the device pulls pre-built binaries, not source builds. Documented expectation in Unit 7. |
| Image rebuild cycle to ship Unit 1's profile.d change is the gating delay | Acknowledged; ~14h CI cost. Mitigation: bundle Layer 4 changes with any other queued image-side work (e.g., Layer 9 nspawn restoration if planned for the same iteration) to amortize. Out of scope for this plan. |
| `nixctl install` partially completes, leaves system in undefined state | `nixctl uninstall` is forgiving (idempotent removal of artifacts that may or may not exist). Worst case the user reflashes — documented in Unit 7 and the recovery solutions doc. |

## Documentation / Operational Notes

- **Image-rebuild cadence**: Unit 1's profile.d change requires one image rebuild + reflash. After that, Layer 4 install/uninstall/upgrade cycles are runtime-only; no further rebuilds needed for normal Layer 4 iteration.
- **Operational verification post-flash**: extend the existing on-device validation (the `findmnt /nix` + `systemctl is-active nix.mount` pattern) with a check that `/usr/bin/nixctl` is present and `nixctl status` runs cleanly. The existing recovery procedure already covers everything Layer 4 might break.
- **GC advice**: `nix store gc` should be mentioned in Unit 7's troubleshooting section. Manual, not scheduled.
- **Layer 5 hand-off**: when this plan's units are all green, Layer 5 (persistent profiles) becomes a small follow-up — `nix profile install <pkg>` works out of the box, and `${HOME}/.nix-profile/bin` is already on `$PATH` from Unit 1's profile.d work. No additional image-side changes needed.

## Sources & References

- **Origin document**: `docs/brainstorms/2026-05-04-001-nix-layer-4-real-store.md`
- Related plans: `docs/plans/2026-04-28-001-feat-layered-nix-integration-plan.md`, `docs/plans/2026-04-28-002-nix-layers-3-plus-handoff.md`
- Related solutions: `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
- Related code:
  - `projects/ROCKNIX/packages/tools/nix-integration/` (existing package, extended)
  - `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-portable-install` (pattern for nixctl)
  - `projects/ROCKNIX/packages/tools/nix-integration/scripts/nix-doctor` (extended in Unit 5)
- External docs:
  - `https://releases.nixos.org/nix/` (binary tarball release pattern)
  - `nix-store(1)` (`--load-db`, `--register-validity`)
  - `https://nixos.org/manual/nix/stable/installation/single-user.html` (single-user install reference)
