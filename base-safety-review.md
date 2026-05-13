# Base Safety Review — Host Reduction toward NixOS Guest UX

Scope: pre-flight review for "shrink ROCKNIX host, let the NixOS guest own product UX, keep host SSH and validation reliable." No files modified. Evidence cites paths in `projects/ROCKNIX/packages/tools/nix-integration/`, `projects/ROCKNIX/packages/rocknix/`, `projects/ROCKNIX/packages/sysutils/systemd/`, `packages/network/openssh/`, and the SM8550 device options.

The asks below are framed as *invariants the host must keep* and *gates that must keep passing* before any host subsystem is deleted. Anything outside those lists is fair game for reduction.

---

## Review

### Correct (currently safe)

- **Device gating is precise.** Only `DEVICE=SM8550` pulls `nix-integration` (`projects/ROCKNIX/packages/virtual/image/package.mk:110-111`), and the systemd package strips `systemd-nspawn` plus its template unit on every other device (`projects/ROCKNIX/packages/sysutils/systemd/package.mk:162-167`). Static checks enforce both rules (`tests/nix-integration-static-checks.sh`, "Device gates" block).
- **Two-knob recovery escape is wired and self-tested.** `/flash/rocknix.no-nspawn` (sticky, SD-card-reader removable) and `rocknix.safe=1` on the kernel cmdline both flip `default.target` to `rocknix.target` via `rocknix-recovery-toggle` running `Before=sysinit.target` (`scripts/rocknix-recovery-toggle`, `system.d/rocknix-recovery-toggle.service`). The legacy `rocknix.target` still exists (`projects/ROCKNIX/packages/rocknix/system.d/rocknix.target`).
- **Guest unit refuses to leak the host.** `rocknix-guest-v2.service` carries no `--bind-ro=/usr`, `/lib`, `/etc/profile`, or bare `/storage`; static and runtime smoke both fail-closed if those reappear (`tests/nix-integration-static-checks.sh`, `tests/nix-integration-runtime-smoke.sh`).
- **Guest tarball is SHA256-pinned.** Promote path verifies + repairs profile drift, requires guest NetworkManager active, and restarts the guest to boot the new generation (`package.mk`, `scripts/rocknix-guest-promote`, `system.d/rocknix-guest-promote.service`).
- **Soak harness already names the right invariants.** `rocknix-guest-soak` samples host SSH on `127.0.0.1:22`, guest resolv-ownership, no host-`/usr` leak in guest PATH, sway/pipewire alive, baseline memory growth (`scripts/rocknix-guest-soak`).

### Blocker — minimum host checklist that must remain intact

Before deleting any host subsystem, every one of these has to keep working end-to-end. Anything that breaks one is a hard stop.

1. **Host SSH on :22, independent of UI plane.**
   - `packages/network/openssh/system.d/sshd.service` is `WantedBy=multi-user.target`, gated by `ConditionKernelCommandLine=|ssh` *or* `ConditionPathExists=|/storage/.cache/services/sshd.conf`. Keep both triggers and keep `multi-user.target` reachable on every default boot path. The guest path already requires this (`rocknix-graphical.target` has `Requires=multi-user.target`).
   - Soak's `check_host_ssh_responsive` is the canonical probe. It must stay green.

2. **`rocknix.target` (legacy ROCKNIX UI) must still boot to a usable state.**
   - Both escape hatches land here; the `HOW-TO-FALL-BACK.md` shipped to `/flash/` instructs the user to use it. Deleting the legacy UI services (`essway.service`, `sway.service`, `seatd.service`, `rocknix-autostart.service`, `rocknix-automount.service`, plus the touch/volume/perf quirks all `WantedBy=rocknix.target`) would strand both escape paths.
   - The recovery toggle itself refuses to switch to a target that does not exist (`systemctl list-unit-files` guard in `rocknix-recovery-toggle`), so a half-removed `rocknix.target` will leave whatever `default.target` was last — fragile.

3. **`/flash` writable and present, and `HOW-TO-FALL-BACK.md` installed there.**
   - `package.mk` copies the doc to `/flash/HOW-TO-FALL-BACK.md` and the recovery toggle reads `/flash/rocknix.no-nspawn`. If `/flash` partition layout changes or gets mounted RO, the sticky escape silently stops working.

4. **Recovery toggle service + script + both targets shipped together.**
   - `rocknix-recovery-toggle.service` must run `Before=sysinit.target`; the toggle script must keep its OR semantics (flag file *or* `rocknix.safe=1`); `rocknix-graphical.target` and `rocknix.target` must both be installed. Static checks enforce this — keep the static check gate in CI.

5. **Storage substrate: `/storage/.nix-root` → `/nix` bind, `/storage/machines/rocknix-guest`, `/storage/.guest`.**
   - `nix-storage-setup.service` + `nix.mount` are `WantedBy=multi-user.target`. The guest unit has `ConditionPathExists=/storage/machines/rocknix-guest` and `RequiresMountsFor=/storage /nix`. The promote helper writes into `/storage/.guest`. Reducing the host must not touch these paths or the units that prepare them.

6. **Kernel cmdline invariants.**
   - `systemd.unified_cgroup_hierarchy=1 systemd.legacy_systemd_cgroup_controller=0` (in `projects/ROCKNIX/devices/SM8550/options`) plus the env `SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1` in the guest unit. Comment in the guest unit documents that the guest's systemd-258 aborts on cgroup v1; removing or rewording the cmdline is a silent-boot-fail risk.

7. **InputPlumber + scrubbed `/run/udev`.**
   - `rocknix-guest-udev-stage` is mandatory: without it, libseat in the guest opens InputPlumber-hidden `event*` nodes and cascades a wlroots GPU reset to black screens (validated 2026-05-08 per the script's own header). If InputPlumber is removed from the host or its hidden-tag emission changes, the guest UI is in danger.

8. **Guest `ExecStartPre` repair pass (`rocknix-guest-prep`).**
   - Must keep relinking `${GUEST_ROOT}/init` and `${GUEST_ROOT}/sbin/init` to the current system profile, must keep creating `/storage/.guest`, must keep writing the resolv-ownership marker. The unit's `ConditionPathExists` only covers the rootfs; without this prep step a cold boot after a profile change strands the guest.

9. **systemd build flags: `-Dmachined=false`, no `nspawn` services enabled by default, `nspawn` binary present only on SM8550.**
   - Three static-check assertions and the systemd `safe_remove` block enforce this; keep them paired with whatever host reduction you do, so we never accidentally re-enable host-side machine registration.

10. **`enable_service` set in `nix-integration` post_install.**
    - `nix-storage-setup.service`, `nix.mount`, `rocknix-graphical.target`, `rocknix-guest-v2.service`, `rocknix-guest-promote.service`, `rocknix-recovery-toggle.service` — six enables. Static checks fail if any goes missing. Do not let host reduction drop the recovery toggle or promote.

### Blocker — validation gates that must stay green

These are the gates that prove the checklist above. Don't delete host subsystems unless all six are passing on the affected build.

- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` — package-shape contract; enforces no `--bind-ro=/usr|/lib|/etc/profile`, no `--bind=/storage` blanket, removal of every Layer 4-12 host CLI, presence of recovery toggle, SHA256 verify of guest tarball, etc.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh` — runs in two modes: build/CI (file/unit presence + forbidden-bind scan) and `ROCKNIX_GUEST_LIVE_SMOKE=1` (on-device: `/nix` mounted, default.target ∈ {`rocknix-graphical.target`, `rocknix.target`}, all four units installed, guest root exists).
- `scripts/rocknix-guest-soak` (24 hourly samples, fail-fast on first alarm) — host SSH probe, resolv-ownership, no host-/usr leak in guest PATH, sway/pipewire alive, MemAvailable not dropping >200 MB from baseline, `essway.service` active. **This soak is the de-facto integration test for "host reduction did not regress anything."**
- Boot validation matrix: cold boot with neither escape → guest main-space; cold boot with `/flash/rocknix.no-nspawn` → `rocknix.target`; cold boot with `rocknix.safe=1` → `rocknix.target`; cold boot after clearing both → back to guest. None of these are automated yet — they are the manual gate before merging host-reduction work.
- `rocknix-guest-promote.service` clean run on a fresh `/storage` (validated by the `system profile drifted` / `applied system path is missing` branches in the script). Worth a contrived test before any host change that might starve the promote helper of `/storage/.guest` or `/run/current-system`.
- Build matrix gate: at least one **non-SM8550** image build must keep succeeding to prove the gating still strips `nspawn`, `nix-integration`, and friends from non-SM8550 SKUs.

### Note — high-risk removal warnings

These are the host subsystems most tempting to delete next. Each carries a concrete, evidence-backed failure mode.

1. **Removing legacy host UI (`essway.service`, `sway.service`, `emustation.service`, `seatd.service`, `rocknix-autostart.service`) entirely.**
   - **Risk: bricks both recovery escape hatches.** `/flash/rocknix.no-nspawn` and `rocknix.safe=1` both set `default.target=rocknix.target`, which `Requires=multi-user.target graphical.target` and pulls the host UI stack via `WantedBy=rocknix.target` (see grep evidence in review notes). If you remove the host UI, recovery boots to a blank graphical.target with no user-facing surface and only SSH-as-root as a recovery shell. That contradicts the brief's "reliable recovery" requirement.
   - **Risk: breaks the soak harness.** `check_host_essway_alive` alarms unconditionally if `essway.service` is not active. The harness will need an explicit rework before that service can disappear, or every soak run will FAIL.
   - **Mitigation if you proceed:** redefine `rocknix.target` to a minimal-but-usable recovery shell (e.g., a getty on `tty1` + sshd + a visible "you are in recovery mode" banner on console + working `connmanctl`), update `HOW-TO-FALL-BACK.md`, and add a runtime check that the recovery plane reaches *something* the user can interact with.

2. **Removing host `rocknix-autostart`/`autostart`/`quirks` packages.**
   - **Risk: silently breaks first-boot defaults** that the rest of the build assumes (SSH-on-by-default on non-main branches set in `projects/ROCKNIX/packages/rocknix/package.mk:73-92`, audio fixups, perf mode, controller setup, HDMI check). The guest doesn't reproduce these on the host side. If recovery still depends on the legacy plane, deleting autostart cripples recovery's audio/input.
   - **Mitigation:** if `autostart/099-networkservices` (which enables sshd by default on non-main builds) goes away, you must explicitly seed `/storage/.cache/services/sshd.conf` or add `ssh` to the kernel cmdline so sshd's `ConditionKernelCommandLine` keeps activating it. Otherwise SSH only comes up when a user has manually toggled it once — losing the "host SSH is always there" invariant.

3. **Removing host PipeWire/WirePlumber/Bluez/alsa stack from the SM8550 image.**
   - **Risk: guest audio relies on host kernel + InputPlumber + a *minimal* host substrate, not a full host audio daemon, but soak still grep-checks for `pipewire` *anywhere on system* (`check_guest_pipewire_alive`). That check is satisfied by the guest's pipewire; deleting the host's is fine. Still — the recovery plane `rocknix.target` *will* lose audio if these are gone, which is fine for "ssh-only recovery" but a problem if recovery still expects a UI.
   - **Mitigation:** make an explicit decision: "recovery is SSH+console only" vs. "recovery keeps audio/UI". Document it in `HOW-TO-FALL-BACK.md` and update the soak `essway` check accordingly.

4. **Deleting `connman` / `iwd` / `wpa_supplicant` / NetworkManager from the host.**
   - **Risk: kills `rocknix-guest-promote`.** Promote calls `systemctl is-active NetworkManager.service` *inside* the guest, but if the host owns no network bring-up at boot, the guest needs to own wlan0 fully from PID 1. The guest unit already runs `no --private-network`, so the host netns is shared — meaning if no host service is configuring the radio before the guest is up, the guest's NM must do it. Currently this is "Tier C finding: guest's NetworkManager owns wlan0 directly," but that's only validated for the running configuration. Removing a host-side network service without first proving the guest gets wifi from cold boot every time is a regression risk for the promote loop (which needs internet to `nix build`).
   - **Mitigation:** before deleting host networking, soak across at least 3 cold boots with no host network units and confirm `rocknix-guest-promote.service` succeeds with no manual intervention.

5. **Reducing or moving `/flash` or removing `qcom-abl` bootloader bits.**
   - **Risk: silently disables `/flash/rocknix.no-nspawn`.** If `/flash` is no longer auto-mounted RW early, the sticky escape stops working and the only recovery path is a transient `rocknix.safe=1` kernel cmdline edit — which on a locked-down bootloader is *not user-recoverable* on Thor.
   - **Mitigation:** any change to the flash partition must be paired with a manual test that touching `/flash/rocknix.no-nspawn` from a card reader on another machine flips the next boot.

6. **Trimming `rocknix-automount.service` or `udevil`.**
   - **Risk: guest unit has `After=rocknix-automount.service` and `Requires=nix.mount`.** Removing automount may leave `/storage` unmounted at the moment the guest tries to start, leading to a `ConditionPathExists` failure on `/storage/machines/rocknix-guest` and a hard boot loop with no UI.
   - **Mitigation:** if automount goes away, replace its responsibilities with explicit `*.mount` units and make sure the guest unit's `RequiresMountsFor=/storage /nix` resolves the same way.

7. **Trimming the kernel cmdline.**
   - **Risk:** dropping `systemd.unified_cgroup_hierarchy=1` is silently fatal to the guest (documented in `rocknix-guest-v2.service` itself). Dropping `quiet rootwait` is cosmetic, dropping `irqaffinity=0-2` or `usbcore.interrupt_interval_override=...` may regress controller behavior. Avoid blanket-cleaning this line.

8. **Removing the `BUILD_BRANCH != main` overrides** in `projects/ROCKNIX/packages/rocknix/package.mk` (lines 80-87) that turn SSH/samba/wifi on by default for dev builds.
   - **Risk:** developer builds without SSH means losing the only recovery channel when the guest is broken. Keep these (or replace with an explicit "dev build" knob) before deleting `autostart`.

9. **Bumping `PKG_NIX_GUEST_REV` while host reduction is in flight.**
   - **Risk:** `rocknix-guest-promote` builds the *packaged* guest *inside the running guest*. If the running guest's Nix/network/`/run/current-system` is broken by the host reduction in the same image, promote never converges and the device is stuck at the previously-applied generation forever (until a recovery boot).
   - **Mitigation:** never combine a host-shrink commit with a guest-rev bump; do them in separate images, soak each independently.

10. **Deleting the static-checks gate from CI without a replacement.**
    - The static-checks script is the only thing currently preventing accidental reintroduction of `--bind-ro=/usr`, `nix-daemon.service`, the old `nixctl`/`nix-doctor` CLIs, host-side ExecStopPost fallback hooks, and a non-SM8550 build pulling in nspawn. Any host-reduction PR that touches `tests/nix-integration-static-checks.sh` should be reviewed line-by-line.

### Note — observations and follow-ups (not blockers)

- **Soak harness embeds a "host UI still active" assertion** (`check_host_essway_alive`). This is currently *correct* (legacy UI is the validated recovery floor) but will become wrong the moment host UI is intentionally removed. Plan to refactor that probe in the same PR that retires the host UI — otherwise the soak misreports.
- **`/run/current-system` seeding is documented as a known fragile path** in `rocknix-guest-prep` (Tier E3). Worth promoting the guest config to install a tmpfiles.d entry that materializes it from `/nix/var/nix/profiles/system` so the host prep helper can eventually go away.
- **`rocknix-graphical.target` does `Requires=multi-user.target`** — good. Keep that line; it is the only thing guaranteeing the SSH plane is reached even on guest-only boots.
- **No automated cold-boot validation** of the recovery toggle exists. The flag-file/cmdline OR-semantics is unit-tested only by static `grep` checks, not by a `systemd-analyze verify` or a QEMU boot. Worth adding before retiring more host code.
- **`progress.md` / `plan.md` were not present** at the requested paths. If the parent expects them, that is a missing input; this review proceeded from the code alone.

---

## TL;DR — bare minimum host checklist

1. Host SSH on :22 reachable from `multi-user.target` on **every** boot path (guest, recovery, dev).
2. `rocknix.target` boots to a usable recovery surface (UI or documented SSH/console-only — pick one and document).
3. `/flash` writable, `HOW-TO-FALL-BACK.md` present, `/flash/rocknix.no-nspawn` escape works after a teardown.
4. Recovery toggle service + script + both targets shipped and enabled.
5. `/storage/.nix-root`, `/storage/machines/rocknix-guest`, `/storage/.guest` paths intact; `nix.mount` and `nix-storage-setup.service` enabled.
6. Kernel cmdline keeps `systemd.unified_cgroup_hierarchy=1`.
7. `systemd-nspawn` binary + `-Dmachined=false` build flag + SM8550-only gating preserved.
8. `rocknix-guest-prep` and `rocknix-guest-udev-stage` ExecStartPre helpers preserved.
9. Static-checks + runtime-smoke + soak harness all run and pass in CI / on-device before any host-reduction merge.
10. Guest revision pin is **not** bumped in the same image as a host-reduction change.
