---
title: refactor: Move SM8550 audio policy into the Nix guest
type: refactor
status: active
date: 2026-05-11
---

# refactor: Move SM8550 audio policy into the Nix guest

## Summary

Move SM8550/AYN Odin2 audio policy out of the ROCKNIX host and into `rocknix-nix-guest`, while keeping the host as a kernel/device/recovery substrate. The implementation should make the guest own ALSA UCM, PipeWire/WirePlumber policy, default audio routing, and hardware volume/power/lid handling, with host changes limited to complete `/dev/snd` and staged udev pass-through.

---

## Problem Frame

Thor already passes the ALSA device nodes into the guest, but audio is not yet guest-native in the architectural sense: the guest lacks the AYN Odin2 UCM policy that ROCKNIX carries, udev staging can be incomplete at guest start, and the current live workaround falls back to manual PipeWire sink creation. Since the product direction is to thin or eventually remove ROCKNIX, the correct fix is not to bind host `/usr/share/alsa` or host PipeWire sockets; it is to move audio policy into the guest and reduce ROCKNIX to hardware bring-up plus recovery.

---

## Requirements

- R1. The Nix guest owns normal-path SM8550 audio policy: ALSA UCM, PipeWire, WirePlumber, default route/profile, and volume behavior.
- R2. ROCKNIX host responsibility remains limited to kernel/DT/drivers/firmware, `/dev/snd` pass-through, scrubbed udev staging, and recovery fallback.
- R3. The implementation must not reintroduce broad host binds such as host `/usr`, `/lib`, `/usr/share/alsa`, host PipeWire sockets, or raw `/run/udev`.
- R4. The guest must discover AYN Odin2 audio through standard ALSA/UCM/WirePlumber mechanisms rather than a permanent hard-coded `hw:0,0` sink workaround.
- R5. Physical volume, power, and lid events must be owned in the guest without racing logind or host `input_sense`.
- R6. The rollout must preserve a safe recovery path: host audio services may remain installed and reclaimed after guest failure, but must not be the normal audio owner under `THIN_HOST=yes`.
- R7. Validation must prove both policy correctness and device ownership: UCM resolution, WirePlumber non-dummy sink creation, volume mutation, button events, fake suspend/resume, and host reclaim behavior.
- R8. ROCKNIX image builds must consume the same guest source of truth as `rocknix-nix-guest`, or deliberately sync the vendored guest kit, so audio ownership changes cannot validate in one repo and disappear in the packaged image.

---

## Scope Boundaries

- Do not make the ROCKNIX host the audio policy owner by binding host ALSA config, host PipeWire sockets, or host user runtime directories into the guest.
- Do not broaden nspawn to bind all of `/dev`, `/usr`, `/lib`, or `/storage` to make audio discovery easier.
- Do not rely on host `volume`, host `input_sense`, or host `rocknix-fake-suspend` for the guest normal path.
- Do not remove host recovery audio services in this plan; they remain part of fallback/reclaim until the guest path is proven over cold boots.
- Do not attempt a full non-container NixOS boot migration here; this plan is for the current nspawn Layer 14 architecture.

### Deferred to Follow-Up Work

- Upstreaming AYN Odin2 UCM to nixpkgs or alsa-ucm-conf upstream: follow-up after the in-guest package is proven on Thor.
- Removing host recovery audio packages entirely: follow-up after guest-owned audio survives soak/cold-boot validation and recovery requirements are redefined.
- Generalizing beyond SM8550/AYN Odin2: follow-up once the Thor-specific path is stable.
- Replacing staged host udev with a more guest-owned device metadata strategy: follow-up after the current nspawn audio path is proven and the remaining host dependency is understood.

---

## Context & Research

### Relevant Code and Patterns

- `rocknix: projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service` defines the nspawn boundary and already binds `/dev/snd` plus staged `/run/.guest-udev:/run/udev`.
- `rocknix: projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-guest-udev-stage` stages `/run/udev` and removes InputPlumber-hidden records. Live investigation showed rerunning it after boot populated missing sound udev records.
- `rocknix: projects/ROCKNIX/packages/audio/alsa-ucm-conf/patches/SM8550/0001_Add-AYN-Odin2.patch` contains the current AYN Odin2 UCM policy, including speaker/headphone/DisplayPort devices and boot mixer sequences.
- `rocknix: projects/ROCKNIX/packages/audio/alsa-ucm-conf/patches/SM8550/0002_AYN-Odin2---Add-EFI-boot-compatibility.patch` carries the alternate card-name compatibility symlink.
- `rocknix: projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayn-common.dtsi` declares the AYN Odin2 sound card model and button input mapping.
- `rocknix-nix-guest: modules/audio.nix` is the guest audio module and current home for root-scoped PipeWire workarounds.
- `rocknix-nix-guest: modules/lid.nix` is the guest lid/power/volume owner and already uses kernel input device names rather than fixed event numbers.
- `rocknix-nix-guest: profiles/main-space.nix` anchors kiosk session environment such as `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, and `SDL_AUDIODRIVER`.
- `rocknix: projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` and `rocknix-nix-guest: scripts/static-checks.sh` are the architecture guardrails to extend.

### Institutional Learnings

- `rocknix: docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md` documents why raw `/run/udev` is unsafe and why staged udev is part of the Layer 14 contract.
- `rocknix: docs/plans/2026-05-07-003-feat-rocknix-layer-14-thin-host-main-space-plan.md` establishes the thin-host direction: host installed fallback, guest main-space ownership.
- `rocknix: docs/plans/2026-05-11-001-refactor-cemu-guest-owned-runtime-peelback-plan.md` provides the responsibility-classification pattern to reuse for audio peelback.
- `rocknix: docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md` warns against trusting stale metadata; audio validation should use live `aplay`, `alsaucm`, `wpctl`, and `pactl` evidence.

### External References

- ALSA UCM documentation: `https://github.com/alsa-project/alsa-ucm-conf/blob/master/ucm2/README.md`
- ALSA UCM debugging: `https://github.com/alsa-project/alsa-ucm-conf/blob/master/ucm2/DEBUG.md`
- WirePlumber ALSA monitor configuration: `https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html`
- PipeWire daemon/configuration docs: `https://docs.pipewire.org/page_daemon.html`
- NixOS `services.pipewire.systemWide`: `https://search.nixos.org/options?channel=unstable&show=services.pipewire.systemWide&query=services.pipewire.systemWide`
- systemd-nspawn documentation: `https://www.freedesktop.org/software/systemd/man/systemd-nspawn.html`

---

## Key Technical Decisions

- Guest UCM is the source of truth for normal audio policy: This preserves the long-term direction of thinning ROCKNIX instead of making the host ALSA installation part of the product path.
- Host udev staging remains transitional infrastructure: WirePlumber needs udev metadata, but the host should only provide a scrubbed, complete device database until the guest no longer depends on nspawn staging.
- Prefer WirePlumber/ALSA UCM over permanent manual `module-alsa-sink`: The manual sink was useful diagnostically, but a durable appliance should expose Speaker/Headphones/DisplayPort through UCM-backed card profiles and routes.
- Use NixOS system-wide/root-compatible PipeWire deliberately: The kiosk bypasses PAM and per-user systemd, so audio daemons need a service model that matches the root-owned single-seat guest.
- Hardware buttons remain guest-owned: logind should ignore power/lid keys, and the guest button handler should consume input events by kernel device name.
- Host reclaim remains recovery-only: Keeping fallback audio services available after guest failure is compatible with thinning as long as they are not part of the normal audio path.
- The packaged guest source must be explicit: either ROCKNIX consumes `rocknix-nix-guest` as the source of truth, or the vendored `nix-integration/guest` tree is updated in the same work. Silent divergence is not acceptable for this audio migration.

---

## Open Questions

### Resolved During Planning

- Is `/dev/snd` missing from the guest? No. The host binds `/dev/snd`, and the guest sees `controlC0`, `pcmC0D0p`, `pcmC0D1p`, `pcmC0D2c`, and `timer`.
- Should the fix bind host `/usr/share/alsa` into the guest? No. That would preserve host policy ownership and fight the thinning goal.
- Why did WirePlumber initially miss useful card policy? The guest had incomplete/stale staged udev and lacked AYN Odin2 UCM content.

### Deferred to Implementation

- Exact Nix packaging shape for UCM: choose the cleanest implementation after inspecting nixpkgs `alsa-ucm-conf` composition, but keep the output as a guest-owned UCM tree.
- Exact WirePlumber default profile/route command or rule: validate after UCM is installed, because profile names and availability should be UCM-driven.
- Whether software volume works on UCM-backed routes without an extra filter: validate against real WirePlumber nodes after UCM installation.

---

## Output Structure

Expected new/changed areas across the two repositories:

    rocknix-nix-guest/
      README.md
      flake.nix
      packages/audio/ayn-odin2-ucm/
        default.nix
        README.md
        ucm2/...
      modules/audio.nix
      modules/lid.nix
      profiles/main-space.nix
      scripts/static-checks.sh

    rocknix/
      projects/ROCKNIX/packages/tools/nix-integration/package.mk
      projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl
      projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-guest-udev-stage
      projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-host-reclaim
      projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service
      projects/ROCKNIX/packages/tools/nix-integration/guest/modules/audio.nix
      projects/ROCKNIX/packages/tools/nix-integration/guest/modules/lid.nix
      projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh
      projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md
      projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-soak-checklist.md

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```mermaid
flowchart LR
  subgraph Host[ROCKNIX host: substrate and recovery]
    Kernel[Kernel / DT / drivers / firmware]
    DevSnd[/dev/snd]
    UdevStage[Scrubbed, complete /run/.guest-udev]
    Reclaim[Recovery reclaim services]
  end

  subgraph Guest[NixOS guest: normal product path]
    UCM[AYN Odin2 UCM package]
    PW[PipeWire]
    WP[WirePlumber ALSA/UCM policy]
    Route[Default speaker/headphone/DP route]
    Buttons[Volume / power / lid handler]
    Apps[Steam, Cemu, desktop apps]
  end

  Kernel --> DevSnd --> Guest
  Kernel --> UdevStage --> WP
  UCM --> WP --> Route --> Apps
  Buttons --> Route
  Buttons --> PW
  Reclaim -. only after guest failure .-> Kernel
```

---

## Implementation Units

### U1. Establish the packaged guest source of truth

**Goal:** Ensure the ROCKNIX image path consumes the same guest audio implementation that is developed and validated in `rocknix-nix-guest`.

**Requirements:** R1, R2, R8

**Dependencies:** None

**Files:**
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/package.mk`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/scripts/nixctl`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/guest/modules/audio.nix`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/guest/modules/lid.nix`

**Approach:**
- Decide explicitly whether the vendored guest tree under `nix-integration/guest` remains mirrored source or becomes deprecated in favor of the external `rocknix-nix-guest` source.
- If the vendored tree remains in use for image builds, update it in the same implementation sequence as `rocknix-nix-guest`.
- If the external repo becomes authoritative, update host packaging and `nixctl` defaults so builds cannot silently use stale vendored modules.
- Add static checks that fail when host packaging points at one guest source while validation targets another.

**Patterns to follow:**
- Existing `package.mk` guest installation path.
- Existing `nixctl` guest kit discovery via `NIX_LAYER13_GUEST_KIT_DIR`.

**Test scenarios:**
- Happy path: image build/import path uses the same audio module and UCM package validated in `rocknix-nix-guest`.
- Regression: vendored guest audio module lacks the new UCM/audio ownership contract while external guest has it; static checks fail.
- Regression: `nixctl` defaults to a stale guest kit without an explicit override; static checks fail or docs identify the override as required.

**Verification:**
- A developer can identify the authoritative guest source from docs and static checks.
- The ROCKNIX packaged image path cannot accidentally omit the guest-owned audio changes.

---

### U2. Make host udev staging complete for sound devices

**Goal:** Ensure the staged `/run/udev` bound into the guest contains sound card metadata before nspawn starts, while preserving InputPlumber-hidden filtering.

**Requirements:** R2, R3, R7

**Dependencies:** None

**Files:**
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-guest-udev-stage`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-soak-checklist.md`

**Approach:**
- Keep the existing staged-udev model and hidden-device scrub; do not raw-bind host `/run/udev`.
- Add a bounded readiness check before copying so the sound card control device udev record is present when available.
- Treat missing sound metadata as a diagnostic warning or bounded failure according to the current guest-start reliability contract, not an infinite boot wait.
- Preserve idempotency: rerunning the stage script should refresh the staged tree and remove hidden InputPlumber records again.

**Patterns to follow:**
- Existing `rocknix-guest-udev-stage` scrub-and-copy behavior.
- Existing static-check style in `nix-integration-static-checks.sh` that prevents broad host binds and unsafe regressions.

**Test scenarios:**
- Happy path: host `/run/udev/data` contains the sound control record; staging copies it into `/run/.guest-udev/data` and still removes hidden InputPlumber records.
- Edge case: sound udev data is delayed; staging waits up to the bounded readiness window and then copies complete data once it appears.
- Error path: sound udev data never appears; staging emits a clear diagnostic and does not silently produce an incomplete staged tree that looks healthy.
- Regression: staged tree must not contain `inputplumber/by-hidden` records or dangling tag symlinks after the sound readiness change.

**Verification:**
- Guest sees `/run/udev/data` entries for `/dev/snd/controlC0` after cold start.
- WirePlumber in the guest sees an ALSA card without needing a manual rerun of the stage script.
- Static checks still reject raw `/run/udev` binds and broad host filesystem leaks.

---

### U3. Package AYN Odin2 UCM inside `rocknix-nix-guest`

**Goal:** Move the AYN Odin2/SM8550 UCM policy from ROCKNIX host packaging into the Nix guest so ALSA and WirePlumber can resolve speaker/headphone/DisplayPort routes natively.

**Requirements:** R1, R3, R4, R7

**Dependencies:** None for packaging; hardware/runtime validation depends on U2.

**Files:**
- Create: `rocknix-nix-guest: packages/audio/ayn-odin2-ucm/default.nix`
- Create: `rocknix-nix-guest: packages/audio/ayn-odin2-ucm/README.md`
- Create: `rocknix-nix-guest: packages/audio/ayn-odin2-ucm/ucm2/AYN/Odin2/AYN-Odin2.conf`
- Create: `rocknix-nix-guest: packages/audio/ayn-odin2-ucm/ucm2/AYN/Odin2/HiFi.conf`
- Create: `rocknix-nix-guest: packages/audio/ayn-odin2-ucm/ucm2/conf.d/sm8550/AYN-Odin2.conf`
- Create: `rocknix-nix-guest: packages/audio/ayn-odin2-ucm/ucm2/conf.d/sm8550/ayn-AYNOdin2-.conf`
- Modify: `rocknix-nix-guest: flake.nix`
- Modify: `rocknix-nix-guest: modules/audio.nix`
- Modify: `rocknix-nix-guest: scripts/static-checks.sh`

**Approach:**
- Import the current ROCKNIX AYN Odin2 UCM content with provenance from the SM8550 `alsa-ucm-conf` patches.
- Preserve both card-name matching paths that ROCKNIX carries today.
- Include the required Qualcomm/include tree dependencies by depending on, extending, or composing with the guest `alsa-ucm-conf` package rather than copying an incomplete isolated subset.
- Make the guest audio services see the guest-owned UCM tree through a standard ALSA UCM mechanism. Choose and document the mechanism before implementation: composing with the guest `alsa-ucm-conf` package is preferred; setting `ALSA_CONFIG_UCM2` for PipeWire/WirePlumber is acceptable as a transitional validation step; binding host ALSA config is not allowed.

**Execution note:** Validate UCM directly with ALSA tools before debugging PipeWire policy.

**Patterns to follow:**
- ROCKNIX source UCM patches in `projects/ROCKNIX/packages/audio/alsa-ucm-conf/patches/SM8550/`.
- `rocknix-nix-guest` package exposure patterns in `packages/cemu`, `packages/steam`, and `flake.nix`.

**Test scenarios:**
- Happy path: `alsaucm` resolves the AYN Odin2 card in the guest and shows HiFi/Speaker/Headphones/DisplayPort policy from the guest-owned UCM tree.
- Edge case: the kernel exposes the EFI-compatible card-name variant; UCM still resolves through the alternate compatibility file.
- Error path: removing or breaking the UCM package causes static checks or validation to fail with a clear missing-UCM signal.
- Regression: no guest audio module references host `/usr/share/alsa` or host `/host/usr/share/alsa`.

**Verification:**
- `aplay -l` shows `AYNOdin2` and `alsaucm` can dump the AYN Odin2 configuration inside the guest.
- Guest package outputs include the UCM package and the audio module consumes it.
- Static checks prove the UCM files and card-name compatibility path are present.

---

### U4. Replace manual sink workaround with UCM-backed WirePlumber policy

**Goal:** Make PipeWire/WirePlumber in the guest expose a real non-dummy default audio route from UCM-backed ALSA discovery, then remove the permanent manual `thor_hw0` sink workaround.

**Requirements:** R1, R4, R7

**Dependencies:** U2, U3

**Files:**
- Modify: `rocknix-nix-guest: modules/audio.nix`
- Modify: `rocknix-nix-guest: profiles/main-space.nix`
- Modify: `rocknix-nix-guest: scripts/static-checks.sh`

**Approach:**
- Use the NixOS-supported system-wide or root-compatible PipeWire model instead of ad hoc per-user assumptions, because the kiosk session intentionally bypasses PAM/user systemd. Ensure the service environment uses the UCM mechanism selected in U3.
- Keep PipeWire, PipeWire Pulse, and WirePlumber inside the guest and anchored to the guest runtime environment consumed by Sway-launched apps.
- Configure WirePlumber to use ALSA ACP/UCM discovery; avoid disabling ACP or bypassing UCM.
- Add a narrow guest profile/route activation step only if WirePlumber sees the card but leaves it off after UCM is present. That step should discover the AYN card by device identity, not hard-code a Pulse sink created by a workaround.
- Remove the manual `module-alsa-sink` path once the UCM-backed route is validated. If retained temporarily, mark it as diagnostic fallback with static checks ensuring it is not the preferred normal path.

**Execution note:** Use characterization-first validation: record current `wpctl status`, `pactl list cards`, and `pactl list short sinks` before changing the guest audio module, then compare after UCM integration.

**Patterns to follow:**
- Existing guest root-session environment in `profiles/main-space.nix`.
- NixOS PipeWire module conventions for system-wide PipeWire when no user manager exists.
- WirePlumber ALSA monitor defaults using ACP/UCM.

**Test scenarios:**
- Happy path: after guest boot, WirePlumber lists `Built-in Audio` and at least one non-dummy sink without manual `pactl load-module module-alsa-sink`.
- Happy path: default sink routes app audio to the AYN speaker path and volume state is visible through `wpctl` or `pactl`.
- Edge case: headphones or DP jack state is unavailable; WirePlumber keeps a usable speaker route instead of falling back to dummy output.
- Error path: UCM is missing or unresolved; audio service logs identify UCM/profile failure rather than silently creating only dummy output.
- Regression: host PipeWire/Pulse sockets are not used by guest apps.

**Verification:**
- Guest cold boot produces a non-dummy PipeWire sink from the ALSA card.
- `pactl list cards` shows an active non-off profile appropriate for AYN Odin2 audio.
- `wpctl status` no longer depends on the manual `thor_hw0` sink as the only useful output.

---

### U5. Finish guest-owned hardware volume, power, and lid behavior

**Goal:** Make physical volume/power/lid controls act on the guest-owned audio/session stack and avoid host/logind races.

**Requirements:** R1, R5, R7

**Dependencies:** U4 for a reliable default audio sink

**Files:**
- Modify: `rocknix-nix-guest: modules/lid.nix`
- Modify: `rocknix-nix-guest: modules/audio.nix`
- Modify: `rocknix-nix-guest: scripts/static-checks.sh`

**Approach:**
- Keep input discovery by kernel device name: `pmic_pwrkey`, `pmic_resin`, and `gpio-keys`.
- Keep logind configured to ignore lid/power/suspend keys so it cannot race the guest handler.
- Route volume changes to the UCM-backed guest default sink rather than a temporary manually loaded sink.
- Keep fake suspend/resume guest-native: display DPMS, application SIGSTOP/SIGCONT, guest audio stop/start, radios, and governors remain in the guest handler where reachable.
- Ensure audio restart on resume brings back the WirePlumber-selected route/profile before apps continue producing audio.

**Patterns to follow:**
- Existing `modules/lid.nix` fake suspend state directory, kill switch, and input-device-name discovery.
- Host ROCKNIX `input_sense` behavior only as behavior reference, not as a runtime dependency.

**Test scenarios:**
- Happy path: pressing volume up/down changes the guest default sink volume and logs the event from the guest handler.
- Happy path: pressing power once fake-suspends the guest session; pressing power again resumes it and restores displays/audio.
- Happy path: lid close/open continues to run the same fake suspend/resume path.
- Edge case: audio service is not ready when a volume key is pressed; handler logs a clear failure and continues watching inputs.
- Error path: the input event device disappears or is renumbered; handler rediscovery/restart behavior avoids permanent failure tied to an event number.
- Regression: `systemd-logind` does not handle power/lid events in parallel with the guest handler.

**Verification:**
- Live button validation shows `KEY_VOLUMEUP`, `KEY_VOLUMEDOWN`, and `KEY_POWER` events handled in the guest.
- Volume changes are observable through the guest audio stack after each button press.
- Power/lid fake suspend leaves DSI outputs and audio in the expected state after resume.

---

### U6. Prevent recovery reclaim from racing guest restart

**Goal:** Ensure host recovery audio/input services cannot start and then immediately fight an auto-restarted guest for `/dev/snd` or `/dev/input`.

**Requirements:** R2, R6, R7

**Dependencies:** U1, U2

**Files:**
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-host-reclaim`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-soak-checklist.md`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Define when reclaim is allowed to start host fallback audio/input services: deliberate recovery mode, guest disabled, or start-limit failure rather than every transient guest crash.
- Adjust guest restart/reclaim sequencing so `Restart=on-failure` cannot immediately relaunch the guest after host fallback services have reclaimed devices.
- Keep recovery one-command or one-toggle friendly; the goal is not to remove fallback, only to avoid split-brain ownership.
- Add a guardrail proving that guest normal path and host recovery path are mutually exclusive states.

**Patterns to follow:**
- Existing `rocknix-host-reclaim` fallback behavior.
- Existing recovery-toggle and Layer 14 fallback documentation.

**Test scenarios:**
- Happy path: guest exits intentionally for recovery; host reclaim starts fallback services and guest does not immediately restart over them.
- Error path: guest crashes once but is expected to restart; host reclaim does not create a lasting device fight before the restart.
- Start-limit path: repeated guest failures move the system to recovery/fallback state with host services active and guest stopped.
- Regression: `ExecStopPost` plus automatic restart cannot create simultaneous host/guest audio ownership.

**Verification:**
- Host process list after guest failure shows either guest-owned audio or host fallback audio, not both claiming the same device path.
- Layer 14 docs describe the normal, recovery, and repeated-failure states unambiguously.

---

### U7. Add cross-repo validation gates and documentation for the audio ownership boundary

**Goal:** Make the new boundary hard to regress and easy to validate during cold-boot, PR, and recovery testing.

**Requirements:** R2, R3, R6, R7

**Dependencies:** U1, U2, U3, U4, U5, U6

**Files:**
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md`
- Modify: `rocknix: projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-soak-checklist.md`
- Modify: `rocknix-nix-guest: scripts/static-checks.sh`
- Modify: `rocknix-nix-guest: README.md`

**Approach:**
- Add host static checks that preserve narrow device/udev pass-through and forbid host audio policy binds.
- Add guest static checks that require the UCM package, root/system-wide PipeWire ownership, WirePlumber policy, logind-ignore settings, and hardware button handler ownership.
- Update docs to describe host audio services as recovery-only under `THIN_HOST=yes`.
- Add a soak checklist section for audio: UCM resolution, non-dummy sink, volume button behavior, power/lid resume, guest crash/reclaim, and no host/guest device fight.

**Patterns to follow:**
- Existing static-check architecture guardrails in both repositories.
- `layer14-soak-checklist.md` style for manual validation gates.
- Cemu peelback plan responsibility-matrix language for normal path vs recovery vs temporary adapter.

**Test scenarios:**
- Happy path: static checks pass only when guest-owned UCM/audio/button contracts are present.
- Regression: adding `--bind-ro=/usr/share/alsa`, host PipeWire socket binds, or raw `/run/udev` fails host checks.
- Regression: removing UCM files, removing logind ignore settings, or removing the guest button handler fails guest checks.
- Regression: reintroducing host `input_sense` or host button ownership fails host checks.
- Integration: soak checklist can be followed on Thor from a cold boot and records enough evidence to prove ownership.

**Verification:**
- Both repos' static checks pass.
- Documentation clearly identifies what is normal path, recovery-only, transitional, and deferred.
- A cold-boot validation run can prove the audio path without relying on live manual staging reruns or temporary PipeWire processes.

---

## System-Wide Impact

- **Interaction graph:** Host nspawn launches the guest with `/dev/snd` and scrubbed udev; guest WirePlumber discovers the ALSA card through UCM; guest apps use PipeWire/Pulse; guest hardware-button handler adjusts audio and fake suspend state.
- **Error propagation:** Udev staging failures should be visible before or during guest startup; UCM/profile failures should appear in guest audio service logs; button-handler failures should not kill the whole guest session.
- **State lifecycle risks:** Fake suspend stops/restarts audio and pauses app processes; resume must restore audio policy before apps continue producing sound.
- **API surface parity:** Steam, Cemu, desktop apps, and CLI audio tools should all see the same guest Pulse/PipeWire default route.
- **Integration coverage:** Unit/static checks are insufficient; cold-boot live validation on Thor is required for udev timing, WirePlumber profile selection, and physical button events.
- **Unchanged invariants:** Host remains the recovery plane; nspawn remains `--register=no`; staged udev remains scrubbed for InputPlumber-hidden devices; no broad host filesystem binds are introduced.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| UCM import misses required Qualcomm include files | Compose with or extend the guest `alsa-ucm-conf` package instead of copying only AYN leaf files. Validate with `alsaucm` before PipeWire. |
| WirePlumber sees the card but leaves profile off | Add a narrow guest profile/route activation service after UCM is present, discovering the AYN card by identity. |
| Volume remains ineffective on the selected route | Treat as an implementation-time audio-policy issue; prefer UCM-backed route/software volume before considering a dedicated filter sink. |
| Host and guest fight over `/dev/snd` | Keep host audio services normal-path disabled under `THIN_HOST=yes`; document reclaim as recovery-only. |
| Udev staging waits too long or races boot | Use a bounded wait and clear diagnostics; keep staging idempotent and safe to rerun. |
| Button handler accidentally depends on event numbers | Keep kernel-name discovery and add static checks for the expected device-name lookups. |

---

## Documentation / Operational Notes

- Update Layer 14 contract docs to state that guest audio policy is authoritative and host audio is recovery-only.
- Add a Thor audio validation checklist covering direct ALSA, UCM, WirePlumber, app audio, volume buttons, power/lid fake suspend, and reclaim.
- After implementation lands and is validated, capture a `docs/solutions/` learning for guest-owned SM8550 audio policy and udev staging timing.

---

## Sources & References

- Related plan: `docs/plans/2026-05-11-001-refactor-cemu-guest-owned-runtime-peelback-plan.md`
- Host nspawn unit: `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service`
- Host udev staging: `projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-guest-udev-stage`
- Host static checks: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Host Layer 14 contract: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md`
- Host soak checklist: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-soak-checklist.md`
- AYN Odin2 UCM source patch: `projects/ROCKNIX/packages/audio/alsa-ucm-conf/patches/SM8550/0001_Add-AYN-Odin2.patch`
- AYN Odin2 UCM compatibility patch: `projects/ROCKNIX/packages/audio/alsa-ucm-conf/patches/SM8550/0002_AYN-Odin2---Add-EFI-boot-compatibility.patch`
- Guest audio module: `rocknix-nix-guest: modules/audio.nix`
- Guest hardware button module: `rocknix-nix-guest: modules/lid.nix`
- Guest profile: `rocknix-nix-guest: profiles/main-space.nix`
- Guest static checks: `rocknix-nix-guest: scripts/static-checks.sh`
- ALSA UCM docs: `https://github.com/alsa-project/alsa-ucm-conf/blob/master/ucm2/README.md`
- WirePlumber ALSA docs: `https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html`
