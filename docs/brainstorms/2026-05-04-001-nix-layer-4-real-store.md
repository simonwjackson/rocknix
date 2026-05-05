---
date: 2026-05-04
topic: nix-layer-4-real-store
---

# Nix Layer 4 — Standard Single-User Nix on Real `/nix`

## Problem Frame

Layers 1-3 are validated end-to-end on real SM8550 hardware. Today, every nix invocation goes through `nix-portable` under `proot`, which has measurable overhead and known compatibility limits (some packages fail under proot's syscall translation, ptrace-using tools misbehave, sandbox builds are unavailable).

ROCKNIX-as-base + Nix-as-toolbox is now a usable substrate, but it is a *limited* one. To make it the daily driver for development workflows on the device, we need real Nix running directly on `/nix` — single-user, root-owned, no proot wrapper. This is also the prerequisite for Layer 5 (persistent profiles) which gives `bat`, `fd`, `rg`, etc. on `$PATH` automatically after SSH login.

The target user is the device owner doing development and admin work over SSH. Not end users running EmulationStation games — that path is unaffected.

## Requirements

**Behavior**

- R1. After installation, typing `nix` in any login shell on the device runs the real Nix binary, not the portable wrapper. `which nix` returns a path under `/nix/var/nix/profiles/default/bin/`.
- R2. `nix run nixpkgs#<pkg>`, `nix-shell -p <pkg>`, and `nix build` work directly without invoking nix-portable. Standard nix subcommands behave as they do on any single-user nix install.
- R3. `nix profile install <pkg>` succeeds and the resulting binary is on `$PATH` in subsequent SSH sessions. (This is what makes Layer 5 land for free as a follow-up.)
- R4. The portable wrapper at `/storage/bin/nix-portable*` remains present and functional. Users can still invoke nix-portable explicitly when they want to (e.g., for cross-validation or to bypass real nix).

**Installation and Lifecycle**

- R5. A single command, run over SSH, performs the install end-to-end at runtime: download the Nix binary tarball, extract, populate `/nix/store` and `/nix/var` (both under the writable `/storage/.nix-root` bind), and write the runtime config to `~/.config/nix/`. The installed user is root (single-user mode). The `$PATH` prefix that makes real nix primary is shipped at *package build time* in `/etc/profile.d/998-nix-integration.conf` (because `/etc` is read-only at runtime); the prefix is always present even on devices where Layer 4 has not been installed. An empty `/nix/var/nix/profiles/default/bin` is harmless — the shell finds nothing there and falls through to `/storage/bin` (portable).
- R6. The installer is idempotent: running it again on an already-installed system either no-ops or upgrades to the latest Nix version with a clear status message.
- R7. A clean uninstall command removes `/nix/store/*`, `/nix/var/*`, and any profile.d edits the installer made, returning the system to the Layer 3 substrate (Layer 1/2 portable wrappers continue to work).
- R8. `nix-doctor` is extended to check Layer 4 readiness: real nix binary on `$PATH`, `/nix` is the bind-mounted storage location, `nix.conf` is in a writable location, basic `nix --version` smoke succeeds.

**Configuration**

- R9. Nix configuration lives outside `/etc` because `/etc` is read-only squashfs. Specifically: `~/.config/nix/nix.conf` (which is `/storage/.config/nix/nix.conf` since root's home is `/storage`).
- R10. Sandbox is enabled (`sandbox = true`) by default if the device supports it. The installer probes by attempting a small sandboxed build during install; if it fails, the installer falls back to `sandbox = false`, records the reason in install logs, and continues. Either outcome is a valid Layer 4 install.
- R11. The binary substituter is `https://cache.nixos.org` with the standard public key. No custom substituters in this layer.

**Coexistence and Reversibility**

- R12. Layer 4 install does not modify ROCKNIX boot, EmulationStation, Sway, Steam, Chromium, or any game-runtime path. A Layer 4 failure must never prevent the device from booting to the normal UI.
- R13. The recovery story is documented, not coded: if real nix breaks, `rm -rf /storage/.nix-root && reboot` (or full image reflash) returns to the Layer 1/2 working state. No special "rollback" command is needed.

## Success Criteria

- **Functional success**: After install, the standard Nix happy paths in R1-R3 work in a fresh SSH session. `nix-doctor` (extended for Layer 4) passes with zero errors.
- **Performance success**: A representative dev workflow runs *obviously* faster under real nix than under the portable wrapper. Specific workflow chosen during planning, but the comparison must be empirical (timed, both modes) and the result must be unambiguous to a human running it. No precise threshold required, but a "real nix is the same speed as proot" outcome means we have not delivered the performance motivation and Layer 4 is not a success regardless of functional correctness.
- **Compatibility success**: At least one package or workflow that is known to fail or misbehave under nix-portable runs cleanly under real nix. Identifying the workload is part of planning.
- **Reversibility success**: The uninstall path (R7) is exercised by the smoke test on every install. After uninstall, Layer 1/2 portable mode is fully functional again with no residue beyond `/nix` itself (which the Layer 3 mount keeps as an empty bind point).

## Scope Boundaries

**Out of scope for this layer:**
- Multi-user nix with nix-daemon, build users (`nixbld*`), and trusted-users config. Structurally impossible on ROCKNIX (no `useradd`/`groupadd`); deferred to Layer 8 if it is ever revisited (likely retired in favor of Layer 9).
- Persistent profiles with auto-`$PATH` integration on every login. That is Layer 5, which depends on this work landing first.
- NixOS configuration management of host services. That is Layer 9 (nspawn-hosted NixOS guest), which is a separate strategic bet and does not block this work.
- Migration of nix-portable's existing on-disk store into the real `/nix/store`. The two stores are independent. Real nix bootstraps from `cache.nixos.org`; nix-portable's store is left where it is.
- Any change to ROCKNIX boot, kernel, or service definitions. Layer 4 is purely a `/storage`-side and `/nix`-side concern.
- Any change to game performance or runtime. Layer 4 imposes zero load when nix is not in use.
- A graphical or EmulationStation-integrated entry point for Nix. SSH-only.

## Key Decisions

- **Real nix replaces portable as the default `$PATH` resolution for `nix`** — Rationale: the user picked performance and compatibility as motivations (1, 2 from the dialogue). Coexistence with explicit per-mode commands defers the win behind a manual opt-in step. Approach C's "rollback verb" was rejected because the device has no production state worth preserving — reflash plus an `rm -rf` is faster than a custom recovery command.
- **Single-user root mode, not multi-user** — Rationale: ROCKNIX has no `useradd` / `groupadd` / `adduser`. Multi-user nix is structurally impossible on this device without re-architecting user management, which is out of scope.
- **Config in `~/.config/nix`, not `/etc/nix`** — Rationale: `/etc` is read-only squashfs. `NIX_CONF_DIR` env override is an alternative but `~/.config` is more conventional and survives nix upgrades cleanly.
- **Sandbox stance is empirical, not prescriptive** — Rationale: `unprivileged_bpf_disabled=2` and the kernel config combination on SM8550 may or may not allow nix's sandbox. Probing during install and falling back gracefully is cheaper than reading the kernel source upfront.
- **No "rollback" command in `nixctl`** — Rationale: defensive engineering against failures the user does not need to recover from gracefully. `rm -rf /storage/.nix-root && reboot` is the recovery path; documented, not coded.
- **Bootstrap via the official Nix binary tarball, not the curl-pipe installer** — Rationale: the official `nix-{version}-aarch64-linux.tar.xz` ships a self-contained nix store and a controllable install script. The curl-pipe installer makes assumptions about sudo availability, profile rc editing, and channel registration that are awkward to neutralize on ROCKNIX. Fetching the tarball directly gives the same payload with full env control.

## Dependencies / Assumptions

- **Layer 3 is live and validated** ✓ — `/nix` is bind-mounted from `/storage/.nix-root` on every boot; smoke-tested 2026-05-04.
- **TLS to `cache.nixos.org` works on the device** ✓ — verified during the Layer 4 probe (`HTTP 200`, ~42ms).
- **User namespaces are enabled in the kernel** ✓ — verified (`max_user_namespaces=30795`, no clone gate). Sandbox builds depend on this.
- **`bash`, `xz`, `curl`, `unshare` available in the ROCKNIX image** ✓ — verified.
- **Nix install sequence will not need `useradd`/`groupadd`** — assumption; single-user root install does not require new system users, but the official install script may attempt it for multi-user paths and will need to be guided into single-user mode via `--no-daemon` or env flags.

## Outstanding Questions

### Resolve Before Planning

(None — all product decisions are settled.)

### Deferred to Planning

- [Affects R5][Technical] How exactly does the official Nix binary tarball's `install` script behave when `NIX_INSTALLER_NO_MODIFY_PROFILE=1`, `NIX_INSTALLER_NO_CHANNEL_ADD=1`, and a redirected `NIX_CONF_DIR` are set, on a system with read-only `/etc` and no sudo? Whether the script can be coerced into compliance, or whether we need to do a manual install bypassing it, is a planning-time investigation.
- [Affects R10][Needs research] Does `sandbox = true` work on this kernel given `unprivileged_bpf_disabled=2`? Likely yes for root-owned builds (root has CAP_SYS_ADMIN), but empirical confirmation is part of planning's first build attempt.
- [Affects "Performance success"][Needs research] What is the right representative workflow for the performance comparison? Candidates: `nix-shell -p python3 --run 'python3 -c "import requests"'` (cold path on a small package set), `nix build nixpkgs#hello` (build evaluation only), or a multi-package `nix-shell` with several deps. Planning should pick one and timing-fixture it.
- [Affects "Compatibility success"][Needs research] Which package is known to fail or misbehave under nix-portable that we can use as a positive-compatibility-result fixture? Candidates include anything using ptrace heavily (gdb, strace) or syscalls proot doesn't translate well. Identify during planning.
- [Affects R6][Technical] Should `nixctl install` always fetch the latest Nix version, or pin to a specific version recorded in the package source? Pinning is more reproducible and matches Layer 1/2's approach (nix-portable v012 is sha256-pinned); leaving floating tracks upstream more easily. Planning decision.
- [Affects R7][Technical] What does "clean uninstall" do about substituter cache and per-user state? Real nix install creates `~/.config/nix/nix.conf`, `~/.nix-profile` (symlink), `~/.nix-defexpr`, and gcroots under `/nix/var/nix/gcroots/`. Uninstall should remove `/nix/store/*` and `/nix/var/*` (full reset) and the `~/.config/nix/` and `~/.nix-defexpr` directories, leaving Layer 3's empty bind point. Whether to run `nix store gc` first as a courtesy, or just `rm -rf`, is a planning decision.
- [Affects R3][Technical] How are `~/.nix-profile/bin` (where `nix profile install` puts binaries) and nix's standard shell integration brought onto `$PATH` after install? Two viable approaches: (a) update `/etc/profile.d/998-nix-integration.conf` at package build time to explicitly prepend `${HOME}/.nix-profile/bin`, or (b) source nix's own `nix.sh` from a build-time-baked profile.d entry. Planning decision; either keeps R3's product behavior intact.

## Visual: How the Layers Stack After Layer 4

```
                ┌──────────────────────────────────────────────────────┐
                │  SSH login on ROCKNIX                                │
                │  PATH after profile.d sourcing:                      │
                │    /nix/var/nix/profiles/default/bin  ← real nix     │
                │    /storage/bin                       ← nix-portable │
                │    /usr/bin:/bin                                     │
                └─────────────────────┬────────────────────────────────┘
                                      │ user types `nix run nixpkgs#hello`
                                      ▼
                ┌──────────────────────────────────────────────────────┐
                │  Layer 4 (new): real nix on real /nix                │
                │  - /nix/store/*  (bootstrapped from cache.nixos.org) │
                │  - /nix/var/*    (gcroots, profiles)                 │
                │  - ~/.config/nix/nix.conf (sandbox=true|false)       │
                └─────────────────────┬────────────────────────────────┘
                                      │ /nix is bind-mounted
                                      ▼
                ┌──────────────────────────────────────────────────────┐
                │  Layer 3 (live): /nix → /storage/.nix-root           │
                │  systemd: nix-storage-setup.service + nix.mount      │
                └─────────────────────┬────────────────────────────────┘
                                      ▼
                ┌──────────────────────────────────────────────────────┐
                │  Layer 1/2 (live, fallback): nix-portable + proot    │
                │  - /storage/apps/nix-portable/                       │
                │  - /storage/bin/{nix,nix-shell,nix-run,...}          │
                │  Still callable via explicit `nix-portable` command  │
                └──────────────────────────────────────────────────────┘
```

## Next Steps

-> `/ce:plan` for structured implementation planning
