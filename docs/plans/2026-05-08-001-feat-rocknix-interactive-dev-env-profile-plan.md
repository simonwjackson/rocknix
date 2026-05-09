---
title: "feat: ROCKNIX Layer 14 interactive dev-env profile"
type: feat
status: completed
date: 2026-05-08
origin: in-conversation synthesis (no requirements doc on disk)
---

# feat: ROCKNIX Layer 14 interactive dev-env profile

## Summary

Add a second Layer 14 guest profile — `dev-env` — that boots the same nspawn substrate as `main-space` but lands the user inside an interactive sway session (USB keyboard primary; touch optional). Bake a small launcher (`fuzzel`), standard sway keybinds, a minimal status bar, and a developer-friendly package set so the device can launch, close, and switch between apps without an SSH tether. Ship as a peer profile selectable at the guest's nixosConfiguration level. The `main-space` kiosk path is untouched (other than a shared 1-LOC PATH fix that benefits both).

---

## Problem Frame

Layer 14 cold-boot autostart is validated end-to-end on AYN Thor (commits `35cb3ed7a4` … `eebfdc2a46`), but the only profile that lands today is `main-space` — a sway kiosk with no launcher, no keybinds, and no way to start an app interactively. To iterate on Korri (and any other Nix-built UI), the developer currently has to SSH from a workstation and run `swaymsg exec` over IPC (which is itself broken, see below). That tether breaks the "live in Nix space as the main system" thesis: the device cannot stand on its own as a Korri-adjacent dev environment.

A second observation while planning surfaced a real blocker: **sway's `exec` mechanism fails inside the nspawn guest with `execve failed: No such file or directory`** — for both IPC (`swaymsg exec`) *and* keybinds (verified live on Thor 2026-05-08). Root cause: the systemd unit's `path = [ dbus foot swaybg swaylock ]` produces a PATH composed entirely of nix store package `bin/` dirs, none of which contain `sh`. Sway calls `execlp("sh", "sh", "-c", cmd, NULL)`, the lookup misses, ENOENT. Without fixing this, *any* interactive sway profile is dead on arrival.

---

## Requirements

- R1. Boot Thor via the existing Layer 14 cold-boot autostart pipeline into an interactive sway session (no auto-launched app). `main-space.nix` semantics unchanged for THIN_HOST=yes builds.
- R2. From inside that session, the user can launch a terminal (foot), open a launcher, search and run any binary on PATH, kill the focused window, and exit sway — using only the USB keyboard plugged into Thor. No SSH required.
- R3. From inside the launched terminal, the user can run `nix run github:<acct>/korri#korri-desktop` (or a local checkout path) and have it render onscreen.
- R4. Sway's `exec` mechanism (IPC and keybinds) works inside the nspawn guest. Fixed in both `main-space` and `dev-env` profiles via the shared kiosk service.
- R5. A minimal onscreen status indicator shows clock and battery percentage so the user does not get an unexpected shutdown.
- R6. The dev-env profile is selectable as a peer of `main-space` via a separate `nixosConfigurations` output (`rocknix-guest-dev-env`). The user can switch a running guest from `main-space` to `dev-env` via in-guest `nixos-rebuild switch --flake ...#rocknix-guest-dev-env --option sandbox false` without re-flashing.
- R7. No regression on `main-space` cold-boot autostart, touch routing, or recovery toggle.

---

## Scope Boundaries

- Not building the full four-image layered plan (`minimal-baseline` ← `korri-minimal` ← `korri-full` + `desktop`). That is the ultimate goal; this plan is the prerequisite dev environment.
- Not consolidating the repo's three flake.nix files (`/flake.nix`, `guest/flake.nix`, `modules/flake.nix`).
- Not retiring Layer 13 modules.
- Not seeding `/storage/config/rocknix.nix` on first boot or implementing the user-owned config customization model.
- Not building a `rocknix-rebuild` host wrapper.
- Not baking Korri into the image. Korri is launched from a working directory at runtime (`nix run` from a clone or flake URL).
- Not implementing a touch-friendly on-screen keyboard or squeekboard. USB keyboard is the primary input.
- Not adding gamepad → keyboard mapping via InputPlumber profiles.
- Not solving bottom-panel touch routing on unpatched kernels (independent track; Build #25587967031 covers it).

### Deferred to Follow-Up Work

- On-screen keyboard for touch-only operation: separate plan after the dev-env loop is closed.
- Status bar enrichment beyond clock/battery (volume, wifi, brightness sliders): polish iteration on the dev-env profile.
- Korri auto-launch on session start: separate plan once `dev-env` is shipping.
- `/storage/config/rocknix.nix` user-config seeding: separate plan as part of the four-image milestone.

---

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/main-space.nix` — current Layer 14 kiosk profile. Composes the same six modules the dev-env profile will compose. Bakes `rocknix-sway-kiosk.service` and `/etc/sway/config` for Thor.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/modules/display.nix` — owns sway, foot, swaybg, swaylock, mesa-demos, vulkan-tools, the `WLR_*` env vars, and `programs.sway.enable = true`. Reused as-is.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/modules/{base,tools,ssh,audio,network}.nix` — composed by both profiles.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix` — exposes `nixosConfigurations.rocknix-guest` and `nixosConfigurations.rocknix-guest-main-space`. Pins `nixpkgs/nixos-25.11`. Adds dev-env output here.
- `projects/ROCKNIX/packages/tools/nix-integration/guest/rocknix-guest.nix` — current default import target (`./profiles/ssh.nix`); not touched by this plan.

### Institutional Learnings

- `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md` — current cold-boot pipeline (recovery-toggle → graphical.target → guest-v2.service → multi-user → sway-kiosk). Dev-env reuses it byte-for-byte.
- Pattern: `/etc` in the guest is squashfs RO; live edits go in `/storage/machines/rocknix-guest/etc/nixos/` then `nixos-rebuild switch --flake .#<config> --option sandbox false`. R6 piggybacks on this.
- Pattern: drop-ins under `/storage/.config/system.d/<unit>.d/` survive reboot. Used for the kiosk service's TTY binding today.
- Live finding (this session, 2026-05-08): `execlp("sh", ...)` from sway's fork inside nspawn fails because the systemd unit's PATH contains no shell. Verified by reading `/proc/$(pgrep sway)/environ` and reproducing with `env -i PATH="$sway_path" sh -c ...`. Fix: add `bashInteractive` (or `bash`) to the unit's `path = [ ... ]`.

### External References

- fuzzel(1) — Wayland-native application launcher; supports keyboard search and touch click. Single binary, no GTK runtime, in nixpkgs 25.11 as `fuzzel`.
- sway(5) — `bindsym` syntax, `exec` semantics, `bar { status_command }` for the bottom status line.

---

## Key Technical Decisions

- **Launcher: `fuzzel`** (not `bemenu`, not `wofi`). Wayland-native, fast, supports both keyboard search and pointer/touch click. Lighter than `wofi` (no GTK), more capable than `bemenu`. Single nixpkgs package, builds for aarch64.
- **No display manager** (no greetd, no SDDM, no lightdm). The existing `rocknix-sway-kiosk.service` pattern — bare systemd unit launching sway directly with `wlroots`'s libseat backend — already works under nspawn and avoids PAM/logind issues that broke greetd in Layer 14 first-light. Dev-env reuses the *same* unit name and same launch posture; the only change is the sway config baked into `/etc/sway/config`.
- **Status bar: sway's built-in `swaybar` with an inline shell `status_command`** that emits clock and battery every 5 s. Keeps R5 satisfied without pulling in waybar/i3status-rust and their toolchains. Path-of-least-resistance now; can swap to waybar in a follow-up if richer info is wanted.
- **Pre-spawn one foot terminal on session start** so the user lands on a working terminal, not an empty desktop. Done via `exec foot` in the sway config (the same exec path R4 fixes).
- **Profile selection mechanism: separate `nixosConfigurations` output, manual rebuild from inside the guest.** No flag file, no host-side prep change. Build-time gives `main-space`; runtime swap is a single `nixos-rebuild switch` command. This avoids tangling profile selection into the boot pipeline before we know what the four-image plan wants. Documented swap procedure in U4.
- **Reuse `programs.sway.enable = true`** from `display.nix`. Do not re-enable in dev-env (it's already on via the shared module).
- **PATH fix lives in `display.nix`, not in each profile.** Both profiles compose `display.nix`, both want the fix, no reason to duplicate. The kiosk service's `path = [ ... ]` either moves into `display.nix` as a NixOS service definition, or `display.nix` adds a `systemd.services.rocknix-sway-kiosk.path = [ pkgs.bashInteractive ]` extension. Decision: keep the full service in `main-space.nix` for now (it's tightly coupled to Thor sway config) and just edit its `path` line. Dev-env will define its own `rocknix-sway-kiosk.service` with the corrected path. Cleaner factoring is a follow-up.

---

## Open Questions

### Resolved During Planning

- **Why does sway exec fail inside nspawn?** Resolved: PATH gap, no `sh`. Live-tested 2026-05-08 against a running guest.
- **Which launcher?** Resolved: fuzzel (see Key Technical Decisions).
- **How does the user switch between profiles?** Resolved: in-guest `nixos-rebuild switch --flake ...#rocknix-guest-dev-env --option sandbox false`. No host-side changes for this milestone.
- **Does dev-env need a display manager?** Resolved: no. Bare systemd unit launching sway directly already works under nspawn.

### Deferred to Implementation

- **Which exact set of dev tools to bake into the profile beyond foot/fuzzel/git/htop/btop?** Decide while writing U2; do not over-bake. User can `nix shell` for anything missing.
- **Does the touch-routing block in `main-space.nix` belong in a shared module?** Yes long-term, but factoring during this plan would expand scope. Copy verbatim into `dev-env.nix` for now; flag for follow-up.
- **Status command exact format.** Decide while writing the script in U2. `printf '%s | %s%%\n' "$(date '+%H:%M')" "$(cat /sys/class/power_supply/BAT*/capacity)"` shape, but path may differ on Thor. Verify at implementation time against `/sys/class/power_supply/`.

---

## Implementation Units

### U1. Fix sway exec PATH in `rocknix-sway-kiosk.service`

**Goal:** Sway's `execlp("sh", ...)` resolves successfully inside the nspawn guest. Both IPC `swaymsg exec` and bound keybinds spawn child processes correctly. Precondition for U2's keybinds.

**Requirements:** R4.

**Dependencies:** None.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/main-space.nix`

**Approach:**
- In the `systemd.services.rocknix-sway-kiosk` definition, extend `path` to include `pkgs.bashInteractive`. The current `path = with pkgs; [ dbus foot swaybg swaylock ];` becomes `path = with pkgs; [ dbus foot swaybg swaylock bashInteractive ];`.
- No other changes to the unit. Comment block above the unit gets a one-line note explaining the `bashInteractive` requirement (sway's `execlp("sh", ...)` searches PATH; without bash on PATH the lookup misses).

**Patterns to follow:**
- Existing kiosk service in `main-space.nix` lines ~65–95.

**Test scenarios:**
- Happy path / Integration: After rebuilding the guest closure with the fix, run `swaymsg 'exec /run/current-system/sw/bin/touch /tmp/exec-test'` from inside the guest; `/tmp/exec-test` exists within 2 s.
- Happy path / Integration: After the same rebuild, run `swaymsg 'bindsym Mod4+t exec /run/current-system/sw/bin/touch /tmp/keybind-test'`, press Super+T on Thor's USB keyboard; `/tmp/keybind-test` exists within 2 s.
- Error path: `journalctl -u rocknix-sway-kiosk.service --since '1 minute ago' | grep 'execve failed'` returns nothing after the fix is live (no new ENOENT spam).

**Verification:**
- Live test on Thor: rebuild guest, exec via IPC, exec via keybind, both succeed. journal clean of `execve failed`.

---

### U2. Add `profiles/dev-env.nix` — interactive sway profile

**Goal:** A second Layer 14 profile that composes the same modules as `main-space` but bakes an interactive sway session (no kiosk auto-app), a launcher, sane keybinds, a minimal status bar, a pre-spawned terminal, and dev-flavored packages.

**Requirements:** R1, R2, R3, R5.

**Dependencies:** U1 (so the keybinds in this unit's sway config actually work).

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/dev-env.nix`

**Approach:**
- Mirror `main-space.nix`'s import block (base, tools, ssh, display, audio, network).
- Set `networking.hostName = lib.mkForce "rocknix-nix-dev";` to distinguish from main-space in machinectl/journal.
- Carry the same `time.timeZone` and `services.journald.extraConfig` (volatile, 64 M) as main-space.
- Define `systemd.services.rocknix-sway-kiosk` with the same shape as main-space (Type=simple, root user, /run/user/0 install pre, libseat backend, restart on failure) and the corrected `path = with pkgs; [ dbus foot swaybg swaylock bashInteractive fuzzel git ];` (PATH includes everything keybinds need to exec).
- Add `environment.systemPackages = with pkgs; [ fuzzel git htop btop ];`. `foot`/`swaybg`/`swaylock` are already provided by `display.nix`.
- Bake `/etc/sway/config` with:
  - The same Thor output config as main-space (DSI-2 transform 90, DSI-1 disable, touch routing block — copy the full block verbatim, including post-patch per-device rules).
  - `seat * hide_cursor 1000` and `default_border none` retained.
  - `set $mod Mod4`.
  - Keybinds: `bindsym $mod+Return exec foot`, `bindsym $mod+d exec fuzzel`, `bindsym $mod+Shift+q kill`, `bindsym $mod+Shift+e exec swaymsg exit`, `bindsym $mod+Left/Right/Up/Down focus left/right/up/down`, `bindsym $mod+Shift+Left/Right/Up/Down move left/right/up/down`, `bindsym $mod+1..9 workspace number 1..9`, `bindsym $mod+Shift+1..9 move container to workspace number 1..9`, `bindsym $mod+f fullscreen toggle`, `bindsym $mod+Space floating toggle`.
  - `exec foot` at end of config so the user lands on a terminal.
  - `bar { status_command while sleep 5; do printf '%s | %d%%\n' "$(date '+%H:%M')" "$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)"; done; position bottom; }` (verify `/sys/class/power_supply/` path on Thor at implementation time).
- Reuse the same `WLR_NO_HARDWARE_CURSORS=1`, `WLR_LIBINPUT_NO_DEVICES=1`, `XDG_RUNTIME_DIR=/run/user/0`, `HOME=/root`, `USER=root` env on the unit.

**Patterns to follow:**
- `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/main-space.nix` — clone its structure, swap the `/etc/sway/config` body and the unit's `path`/`environment.systemPackages`.

**Test scenarios:**
- Happy path: Build `nix build .#nixosConfigurations.rocknix-guest-dev-env.config.system.build.toplevel` succeeds (after U3) and produces a closure containing fuzzel, git, htop, btop, foot.
- Happy path: Rebuild guest live on Thor against `dev-env` config; sway session comes up with one foot terminal visible on DSI-2.
- Happy path: Press Super+Return; a second foot terminal opens. Press Super+Shift+Q on the second; it closes.
- Happy path: Press Super+D; fuzzel appears, type "htop", Enter; htop launches in a new terminal-equivalent (or fuzzel runs the binary directly — verify behavior at impl).
- Happy path / R3: Inside foot, run `nix run nixpkgs#hello`; "Hello, world!" prints.
- Edge case: Battery indicator in the status bar shows a number 0–100 within 5 s of session start.
- Edge case: Touch-tap on DSI-2 surface delivers `wl_touch.down` (regression check on R7 — touch routing carried verbatim from main-space).
- Error path: If `/sys/class/power_supply/BAT*/capacity` is unreadable, the status_command does not crash sway (use `2>/dev/null | head -1` so empty is fine).
- Integration: `journalctl -u rocknix-sway-kiosk.service` shows clean startup, no execve errors after U1+U2.

**Verification:**
- Thor boots into dev-env profile (after U3+U4), sway session appears, all keybinds work, status bar shows clock+battery, foot terminal pre-spawned, fuzzel launches arbitrary binaries.

---

### U3. Wire `rocknix-guest-dev-env` into the guest flake outputs

**Goal:** A `nixosConfigurations.rocknix-guest-dev-env` output exists alongside `rocknix-guest-main-space`, importable by `nixos-rebuild` from inside the running guest.

**Requirements:** R6.

**Dependencies:** U2.

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix`

**Approach:**
- Add a `devEnvConfiguration = nixpkgs.lib.nixosSystem { system = targetSystem; modules = [ ./profiles/dev-env.nix ]; };` binding alongside the existing `mainSpaceConfiguration`.
- Add `nixosConfigurations.rocknix-guest-dev-env = devEnvConfiguration;` to the flake's outputs map alongside `rocknix-guest-main-space`.
- No changes to the `packages.<sys>.rootfs` builder (rootfs is still built from `configuration` — the default — for the boot-staging path; dev-env is reachable only via in-guest rebuild for now, matching the manual-swap decision in Key Technical Decisions).

**Patterns to follow:**
- Existing `mainSpaceConfiguration` definition and `nixosConfigurations.rocknix-guest-main-space` output in the same file.

**Test scenarios:**
- Happy path: `nix flake show` against `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix` lists `rocknix-guest-dev-env` under `nixosConfigurations`.
- Happy path: `nix eval .#nixosConfigurations.rocknix-guest-dev-env.config.networking.hostName` returns `"rocknix-nix-dev"`.
- Happy path: `nix build .#nixosConfigurations.rocknix-guest-dev-env.config.system.build.toplevel --no-link` succeeds.
- Edge case: `nix flake check` (or the equivalent `nix-integration-static-checks.sh`) does not regress.

**Verification:**
- Flake evaluates and the new closure builds locally.

---

### U4. Document the live profile-swap procedure

**Goal:** A single, copy-pasteable runbook the developer can use to switch a running Thor guest from `main-space` to `dev-env` (and back) without re-flashing. Linked from the Layer 14 contract doc.

**Requirements:** R6.

**Dependencies:** U3.

**Files:**
- Create: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-dev-env-profile.md`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md` (add a "Sibling profiles" section with a link).

**Approach:**
- Document the goal, prerequisites (Thor booted into Layer 14, network up, guest reachable via tailscale).
- SSH-from-workstation runbook:
  1. `ssh root@thor` to host.
  2. Enter guest via `nsenter` pattern (already documented in contract).
  3. From inside guest: `cd /etc/nixos` (or wherever flake source is staged in the guest — verify at implementation; may need to clone the repo's `guest/` dir into `/storage/machines/rocknix-guest/etc/nixos/` first).
  4. `nixos-rebuild switch --flake .#rocknix-guest-dev-env --option sandbox false`.
  5. Wait for `rocknix-sway-kiosk.service` restart; the new sway session lands on Thor's screen.
- Reverse procedure: same with `#rocknix-guest-main-space`.
- Note that switch is *not persistent across reflash* — the next image pull restores main-space. That is intentional for now; persistent selection is the four-image plan's job.
- Note known limitations: USB keyboard required (no on-screen keyboard yet); battery in the status bar reads from `/sys/class/power_supply/BAT*/capacity`; if the guest has no flake source staged, the procedure starts with cloning the repo into the guest first.

**Patterns to follow:**
- Tone and structure of `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md`.
- Existing contract docs under `projects/ROCKNIX/packages/tools/nix-integration/docs/layer*-*.md`.

**Test scenarios:**
- Test expectation: none — pure documentation. Verification is a clean read-through and a successful manual run-through during U2/U3 testing on Thor.

**Verification:**
- A second person (or future-self) can follow the runbook end-to-end on Thor and end up in a dev-env session without asking questions.

---

## System-Wide Impact

- **Interaction graph:** Adds a new sibling `nixosConfigurations` output. No host-side scripts change. The host's `rocknix-layer14-prep` continues to stage the *default* closure (`rocknix-guest`) on flash — dev-env is a runtime opt-in.
- **Error propagation:** Sway exec failures previously surfaced only in journal as `execve failed`; after U1, those are gone for both profiles. Status_command failures are swallowed by `2>/dev/null` so the bar stays alive even if `/sys/class/power_supply` shape changes.
- **State lifecycle risks:** In-guest `nixos-rebuild switch` mutates `/storage/machines/rocknix-guest/etc/nixos/` symlinks. Reverting is a second `nixos-rebuild switch` to the other profile. No persistent state is migrated between profiles (both share `/run`, `/var`, `/storage`).
- **API surface parity:** The `nixosConfigurations` map gains one entry. No CLI, no env var, no host-side contract changes.
- **Integration coverage:** The keybind regression test in U1 is also implicit coverage for U2 (keybinds drive U2's value). The cold-boot regression test on `main-space` (R7) is the explicit guard against U1's PATH change breaking the kiosk path.
- **Unchanged invariants:** `rocknix-guest` (Layer 10b minimal default) and `rocknix-guest-main-space` continue to evaluate and build identically. THIN_HOST=yes still produces a byte-equivalent main-space image (modulo the 1-LOC PATH fix). Recovery toggle (`/flash/rocknix.no-nspawn`) still returns the legacy UI. Touch routing pinned to DSI-2 still in place.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `bashInteractive` on the kiosk unit's PATH bloats closure size meaningfully. | Bash is already in the closure (it's a NixOS module dependency). Adding it to the unit's `path` only changes the runtime PATH env, not what's installed. Closure size unchanged. |
| Keybinds work in a fresh sway session but `swaymsg exec` over IPC still fails for some other reason (different code path). | U1's test scenarios cover both paths. If IPC still fails, that's a separate bug — but the dev-env value prop only requires keybinds, so dev-env is unblocked either way. |
| Status bar's `/sys/class/power_supply/BAT*/capacity` glob misses on Thor (different naming, e.g. `battery@5`). | Verify at implementation by reading `ls /sys/class/power_supply/` on Thor before finalizing the status_command. Fallback: hard-code the actual battery node name with a comment pointing to the device. |
| Adding `fuzzel` and `git` to the dev-env profile pulls in transitive aarch64 builds that aren't substituted by the cache, slowing first rebuild. | Both are well-known nixpkgs packages with binary cache hits on aarch64-linux. Even uncached, they're <30 s build each on Thor; iteration cost is bounded. |
| `nixos-rebuild switch` from inside the guest needs the `guest/` flake source staged at a writable path. The squashfs `/etc/nixos` is RO. | The Layer 14 iteration pattern already documents staging the guest flake under `/storage/machines/rocknix-guest/etc/nixos/`. U4's runbook explicitly calls out the staging step as a prerequisite. |
| Pre-spawning `foot` at sway-start runs before sway's IPC is fully ready, race-loses, no terminal appears. | sway's `exec` directives in config run after compositor init by design. Verify on first live test; if racy, add `exec_always` or a 1 s delay. |
| Dev-env profile drifts from main-space over time (different sway config, different unit definition). | Flag the sway-config block and the rocknix-sway-kiosk unit as duplication in U2's open question; address in a follow-up factoring pass once both profiles are validated. |

---

## Documentation / Operational Notes

- New runbook at `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-dev-env-profile.md` (U4).
- Cross-link from `layer14-main-space-contract.md`.
- Solution doc — *not* required by this plan, but a "first usable Korri-adjacent dev session on Thor" learning would be a natural `se-compound` candidate after the loop closes.

---

## Sources & References

- In-conversation synthesis (this turn) — narrowed scope from the four-image plan to a single Korri-adjacent dev environment.
- Live debug session 2026-05-08: identified sway exec PATH gap by comparing `/proc/$(pgrep sway)/environ` to `execlp("sh", ...)` semantics.
- `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md`
- `docs/brainstorms/2026-05-07-002-rocknix-thin-host-nix-main-space.md`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/main-space.nix`
- `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix`
