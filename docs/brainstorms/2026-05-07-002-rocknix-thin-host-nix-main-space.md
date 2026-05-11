---
title: "explore: ROCKNIX as thin host, Nix space as main system"
type: explore
status: captured
date: 2026-05-07
branch: feat/rocknix-declarative-modules
---

# ROCKNIX as thin host, Nix space as main system

This document captures a live brainstorm/exploration session about reframing
the ROCKNIX + Nix nspawn experiment from "guest as app sandbox" to
"ROCKNIX as a thin boot/recovery supervisor with the Nix space as the
primary interactive system." It also records the high-level milestone path
toward that goal so the work can be resumed in a fresh session.

It is intentionally a captured conversation/decision record. It is not
itself a plan in the `docs/plans/` sense; each milestone below should later
get its own brainstorm/plan/handoff cycle.

---

## Starting context

Captured during work on branch `feat/rocknix-declarative-modules`, after
landing Layer 13 declarative modules and live-validating Layer 10/12 fixes
on Thor (`AYN Thor` / SM8550). Earlier in the session:

- Built and flashed `ROCKNIX-update-SM8550-20260507` to Thor.
- Validated cgroup v2, Layer 13 host module workflow, Layer 13 guest
  workspace workflow, and the Layer 12 SSH key path on `2222`.
- Pushed forward-only fix commit `8b3c38a6f1` to ratchet guest boot and SSH
  module behavior, dispatched build `25523107940`.
- Live UI bridge experiment proved guest could drive host Sway/Wayland:
  - `wayland-info` from inside guest worked
  - `xeyes` rendered, was visible/focused via `swaymsg`
- Live BOTW launcher experiment ran `/storage/bin/botw-1080p-native.sh`
  from inside the guest namespace via broad bind-throughs; observed
  performance was indistinguishable from the host launch of the same
  script. This is the trigger for reframing the milestone direction.

Key constraints carried over from earlier work:

- ROCKNIX remains the base OS / recovery plane.
- Host SSH on `root@thor:22` must remain untouched.
- Runtime state under `/storage`; avoid mutating `/usr`, `/flash`, `/boot`,
  host `/etc`.
- No guest autostart unless separately validated.
- No default guest credentials or password login.
- Layer 12 SSH must be opt-in, key-only, alternate port only; never `22`.
- Do not support earlier/lower "layer" forms once superseded.
- Do not silently bind full host `/storage` into the guest.
- UI/display passthrough must be explicit.
- Keep unrelated untracked file
  `projects/ROCKNIX/packages/hardware/quirks/devices/AYN Thor/500-disable-joystick-led`
  untouched.

---

## Hardware scope

**Target devices: AYN Odin 2 Portal and AYN Thor only.**

Both are SM8550 (Snapdragon 8 Gen 2) handhelds from the same vendor with
nearly identical firmware/kernel paths. This is a deliberate, important
scoping decision and it materially changes the project shape:

- One SoC family, one Mesa/Adreno driver target, one suspend story,
  one audio routing graph (`lpass → q6 → codec`), one BT/Wi-Fi pair,
  one InputPlumber configuration shape.
- Two device DTS variants and a small set of per-device quirks
  (display panel, gamepad layout, lid sensor presence).
- No need to support older RK3326/RK3399/RK3566/RK3576/RK3588/H700/
  S922X/SDM845/SM6115/SM8250/SM8650/RPi paths in the main-space
  experiment.

### Implications for the brainstorm

1. The biggest single risk in earlier feasibility estimates was
   “multi-device, releasable architecture (35–50%).” That risk now
   collapses substantially. The “multi-device” outcome we care about
   is **two devices on the same SoC**, not the full ROCKNIX matrix.

2. ROCKNIX upstream churn risk drops: we no longer need to track every
   board they support. We track SM8550, period. Other devices keep
   running stock ROCKNIX and are out of scope for main-space.

3. CI scope shrinks dramatically: one toolchain, one rootfs target,
   one guest closure target (`aarch64-linux`, SM8550-tuned).

4. The “what to remove from ROCKNIX” candidate list (later in this
   doc) is now safer to act on — we don’t have to worry about another
   device needing the userland we cut.

5. The eventual main-space distribution can be branded distinctly from
   ROCKNIX (e.g. “ROCKNIX-Nix” or a separate name) and need not
   pretend to be a drop-in replacement for all ROCKNIX targets.

### Implications for live work

- All Layer 14+ unit work, guest module work, and validation runs are
  done on Thor first. Odin 2 Portal becomes the second-device check
  *only after* Thor is solid.
- Differences between Odin 2 Portal and Thor are captured as
  per-device modules/quirks rather than separate code paths.
- Anything that requires SoC-specific kernel patches is acceptable;
  we are not constrained by mainline upstreamability.

### Out of scope (explicitly)

- Generic NixOS for handhelds.
- Other ROCKNIX-supported devices (RK*, H700, S922X, SDM845, SM6115,
  SM8250, SM8650, RPi, Allwinner, Amlogic, Samsung, NXP).
- Non-handheld form factors.
- Mainlining the SM8550 vendor stack.

---

## Reframing: from sandbox to main space

Earlier "layers" treated the Nix space as a sandbox/app environment on top
of ROCKNIX. The BOTW perf result + UI bridge proof shifted the target:

> ROCKNIX = thin hardware/boot/recovery supervisor.
> Nix space = primary interactive OS.

Layers are now treated as **forward-only ratchets / milestones**, not
compatibility strata. We do not preserve old forms once superseded.

### What this is not

- Not "safe bridge mode" as the product. Safe bridge is a stepping stone
  for live testing, not the long-term UX.
- Not full NixOS replacement of ROCKNIX. ROCKNIX retains kernel/boot/
  recovery.
- Not "guest as app sandbox" anymore.

### What ROCKNIX should keep

- Boot chain, kernel, drivers, firmware loading, hardware quirks
- Update/recovery
- Starting/stopping the Nix space
- Last-resort power/lid watchdog
- Recovery shell / rollback authority
- Disk partitioning / image update system

### What the Nix space should own

- App/userland environment
- Networking (Wi-Fi, NetworkManager, DNS)
- Display session and main UI (e.g. EmulationStation)
- Input/audio surfaces (via passthrough)
- Package management / declarative config
- User shell / Home Manager-style environment
- Fake-suspend UX (later milestone)

---

## What we proved live during this session

These are observed facts on Thor, not aspirations:

- `systemd-nspawn` from the guest closure (systemd 258.7) successfully
  boots the guest rootfs.
- The guest can be made the launcher of host-native binaries via explicit
  bind-throughs (`/storage`, `/usr`, `/lib`, `/etc/profile`,
  `/etc/profile.d`, `/dev/dri`, `/dev/input`, `/dev/shm`,
  `/run/0-runtime-dir`, `/tmp/.X11-unix`, `/var/log`,
  `/sys/devices/system/cpu/cpufreq`, `/sys/class/devfreq`).
- `wayland-info` and `xeyes` from inside the guest rendered against host
  Sway.
- BOTW launched via `/storage/bin/botw-1080p-native.sh` from inside the
  guest namespace ran with no perceptible performance difference vs
  launching the same script on the host.
- Sysfs is read-only inside the container, so GPU/CPU clock writes from
  inside the guest fail; today these caps must be applied from host side
  after launch.
- SSH into the wider game-bridge guest can break when host `/usr` is
  bind-mounted in (NixOS-owned `/etc/ssh/...` paths stop matching), but
  `nsenter` from host into the guest namespace still works.

---

## What is fundamentally unavailable in the guest

Even with full main-space ambitions, the guest cannot have:

- A different kernel
- Different kernel drivers/firmware
- An independent bootloader/initramfs
- True VM-style isolation (this is namespaced containers)
- Kernel features/devices the host kernel doesn't expose
- True hardware suspend independent of the host kernel state

This is acceptable because the goal is "main userland," not "main kernel."

---

## Networking direction (decided)

Wi-Fi is owned by the guest. The mechanism, refined after Tier C, is
*shared-netns single-manager*, not netns handoff.

- Guest and host share the kernel root netns (this is already the
  case with the current `rocknix-guest.service` unit — no
  `--private-network`). The guest can already see `wlan0`, `phy0`,
  `nl80211`, `/dev/rfkill`, etc.
- Guest runs the actual network manager (NetworkManager or iwd) from
  its closure. User uses real `nmtui` / `iwctl` inside the guest.
- Host runs **no** network manager in main-space mode: no iwd, no
  connman, no NetworkManager, no host wpa_supplicant, no host
  tailscaled.
- Because there’s only one manager (the guest’s) and one radio,
  there’s no contention. No netns move, no veth, no NAT.
- Host loses direct Wi-Fi/SSH-over-Wi-Fi during main-space mode.
  This is a known accepted tradeoff, not a bug.

**Why not netns handoff:** the SM8550 ath12k driver supports the
`set_wiphy_netns` move at the cfg80211 layer but cannot create a
netdev on the moved phy in the new netns (Tier C, C3). This rules
out *physically moving* `wlan0` into a separate guest netns. It does
**not** affect the shared-netns design above, which never moves the
phy.

**Why not a bridge with NAT:** the only reason to use a veth + NAT
bridge would be to keep the guest in its own netns. We don’t need to.
With only one manager (the guest’s) there’s no isolation problem to
solve. We’ll keep the C2 veth+NAT pattern in our toolbox for *secondary*
guests (sandbox/test guests running alongside main-space), not for
main-space itself.

We deliberately reject "wrapper TUIs that talk to host network manager"
as the long-term path, because that's the safe-bridge model the user
explicitly does not want.

A reclaim/rollback path is still required (reboot, local recovery, or an
explicit reclaim command). For Wi-Fi specifically: if the guest fails
to come up, the host should be able to bring up `wlan0` itself (a
tiny one-shot fallback `wpa_supplicant -B` triggered only when the
guest does not signal ownership within N seconds of boot).

---

## Sleep / fake-suspend (preserved, eventually moved)

ROCKNIX SM8550 today does not use real hardware suspend. Evidence:

- `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/030-suspend_mode`
  runs `/usr/bin/suspendmode off` and sets
  `HandlePowerKey=ignore` / `HandleSuspendKey=ignore`.
- `projects/ROCKNIX/packages/rocknix/sources/scripts/rocknix-fake-suspend`
  is the actual sleep behavior. It:
  - turns display off (Sway DPMS or backlight)
  - mutes audio
  - sets CPU/GPU governors to powersave
  - parks CPU cores (optional)
  - blocks input (`evtest --grab`)
  - turns LEDs off
  - shuts down after a delay unless HDMI/charger or game running
- `projects/ROCKNIX/packages/sysutils/system-utils/sources/scripts/input_sense`
  binds `KEY_POWER` and `SW_LID` events to `rocknix-fake-suspend`.
- DTS confirms Thor uses the PMIC power key + Hall lid sensor with
  `wakeup-source` properties.

What "sleep" really means on Thor today is therefore a userspace UX, not a
true `mem`/`s2idle` cycle. So:

- The Nix space CAN own the fake-suspend UX.
- But `/sys/power/state` is global to the host kernel, not namespaced.
- And if the guest owns sleep and hangs while screen is off, we can get
  stuck (black screen, input blocked, sleep daemon dead).

Therefore the target is:

```text
Nix space owns the sleep behavior.
ROCKNIX host keeps a last-resort power/lid watchdog.
```

---

## Comparable projects (precedents)

Closest analogs to this architecture:

- ChromeOS + Crostini
- Fedora Silverblue / Bazzite + Toolbox/Distrobox
- SteamOS + Distrobox
- Proxmox / LXC appliance hosts
- NixOS containers / `nixos-container`
- NixOS in `systemd-nspawn` on non-Nix hosts
- NixOS-WSL
- nix-on-droid
- Bluefin / uBlue
- Bedrock Linux (philosophically)
- Jovian-NixOS (different path: replace, not layer)
- Bazzite on handhelds

Closest single mental model:

```text
ChromeOS Crostini + SteamOS/Distrobox + NixOS-WSL
```

Our version is novel mainly because it adds gaming/display/input/Wi-Fi
device passthrough into the Nix space on a Qualcomm handheld with a vendor
kernel.

---

## How close to "real NixOS tooling" we can get

For userspace tooling: very close. For kernel/boot/hardware ownership:
not full.

Real and usable inside the space:

- `nix`, `nix-shell`, `nix develop`, `nix run`, flakes
- The actual `nixos-rebuild` command
- NixOS modules and Home Manager
- Real `nmtui` via NetworkManager
- Real systemd inside guest

Important caveats:

- `nixos-rebuild switch` would switch the **guest NixOS system**, not the
  ROCKNIX host kernel/bootloader.
- Some NixOS modules assume kernel/boot ownership and need to be disabled
  or adapted (bootloader, kernel modules, suspend/hibernate, low-level
  hardware).
- Guest udev cannot load drivers the host kernel does not provide.

Practical closeness:

- Daily interactive use: ~8–9/10 NixOS feel.
- Low-level OS ownership: ~4–6/10.
- Gaming/app performance: near-native (proven with BOTW today).

---

## High-level milestone path

These are forward-only ratchets. Each should later get its own brainstorm
+ plan + handoff. Earlier "layers" 0–13 are assumed in place.

### Milestone 14 — Main-space canary (no-black-screen guard)

Goal: prove we can visibly live in the guest.

- Start guest as primary space.
- Launch a visible guest-owned terminal and/or EmulationStation.
- Pass through display/GPU/input/audio enough to interact.
- Keep host recovery available.
- Gate: never black screen; either guest UI appears or ROCKNIX recovery
  UI remains.

### Milestone 15 — Guest owns networking

Goal: use the guest like a real online system.

- Move Wi-Fi interface into guest netns.
- Run NetworkManager inside guest.
- Use real `nmtui`.
- Prove guest internet, DNS, reconnect, resume.
- Accept that host Wi-Fi is unavailable while guest owns it.
- Gate: guest can connect/reconnect Wi-Fi without host wrappers.

### Milestone 16 — Guest-owned session

Goal: make guest the normal interactive environment.

- Launch EmulationStation from guest.
- Move app/game launchers into guest context.
- Pass input/audio/display as main-space devices.
- Stop duplicate host UI/services where safe.
- Gate: user can navigate ES, launch games/apps, return cleanly.

### Milestone 17 — Real NixOS management loop

Goal: administer the space like NixOS.

- Include real `nixos-rebuild` inside guest.
- Place guest config in a durable editable location.
- Support `nixos-rebuild switch` (guest only).
- Make guest systemd services declarative.
- Optionally add Home Manager.
- Gate: user can edit config, switch, restart guest, keep changes.

### Milestone 18 — Guest-owned sleep UX

Goal: preserve handheld feel while living in guest.

- Port fake-suspend policy into guest.
- Guest handles power/lid sleep actions.
- Host keeps last-resort recovery watchdog.
- Validate display off/on, audio mute, clocks down/up, LEDs off/on.
- Gate: power button/lid behaves like ROCKNIX today, no stuck black
  screen.

### Milestone 19 — Thin host reduction

Goal: make ROCKNIX mostly invisible.

- Host boots directly into main-space.
- Host starts only supervisor/recovery services.
- Host stops duplicated network/UI/audio services after handoff.
- Add recovery mode / disable-main-space flag.
- Gate: normal boot lands in Nix space; recovery boot lands in ROCKNIX.

### Milestone 20 — Polish and permanence

Goal: make it daily-drive-safe.

- Main-space health checks.
- Device reclaim commands.
- Crash recovery flow.
- Logs surfaced from both host and guest.
- Declarative main-space module.
- Update/recovery documentation.
- Gate: safe enough to daily-drive.

Core principle:

```text
ROCKNIX owns boot, kernel, firmware, update, recovery.
Nix space owns userland, network, session, apps, and eventually sleep UX.
```

---

## First validation ladder when device is back online

Run live, in order, so we never end up at a black screen:

1. Start guest with current bind set; do not switch display ownership yet.
2. Launch a visible guest-owned terminal (foot/kitty inside guest) on host
   compositor.
3. Launch EmulationStation from inside the guest namespace using existing
   host Cemu/launcher binaries (re-using the BOTW pattern).
4. From within guest, run `hostname`, `nix --version`, `nmtui --version`,
   `ip addr`, and a small GUI test app.
5. Only after visible interactive guest UI is proven, start Wi-Fi
   passthrough experiments.
6. Bake the no-black-screen contract into the next build:
   either guest "Nix Main Space Ready" UI is up,
   or ROCKNIX recovery UI is up.

Live cleanup notes for the resuming session:

- Live unit was hand-edited at `/storage/.config/system.d/rocknix-guest.service`
  with broad bind-throughs (`/usr`, `/lib`, `/etc/profile`,
  `/etc/profile.d`, `/dev/dri`, `/dev/input`, `/dev/shm`, etc.).
- Authorized keys were copied to
  `/storage/machines/rocknix-guest/root/.ssh/authorized_keys` for the
  experiment.
- Live `xeyes` and BOTW guest launches were used as canaries; clean up
  state before formalizing modules.
- Guest nspawn binary path proven good:
  `/storage/machines/rocknix-guest/nix/store/11yzh5vk22ybx1abvs42184ydf2hpdj3-systemd-258.7/bin/systemd-nspawn`

---

## Open questions to resolve in fresh session

- Which guest terminal/UI is the canary for Milestone 14? `foot` is the
  cheapest closure on Wayland; ES is the most useful real canary.
- How to express device handoff declaratively (per-device module options
  vs a single "main-space" mode flag).
- How to package the "Nix Main Space Ready" canary so a failed boot leaves
  ROCKNIX UI visible instead of a blank screen.
- Where to put the host watchdog: as a ROCKNIX systemd unit, or extend
  `rocknix-fake-suspend` to act as a guest-aware watchdog.
- How `nixos-rebuild switch` interacts with ROCKNIX's image update
  cadence; we need a clear rule that guest switches do not require a
  ROCKNIX rebuild.
- Whether/how to allow the guest to request host poweroff/reboot safely
  (one-shot bridge command vs DBus path vs a privileged `nixctl host`
  helper).
- Recovery story: how a user with a misconfigured guest reaches a
  working ROCKNIX shell (boot flag? hold-key? local TTY?).

---

## Status snapshot at capture time

- Branch: `feat/rocknix-declarative-modules`
- Last pushed head: `8b3c38a6f1`
- In-flight build: `25523107940` (head `8b3c38a6f1`)
- Thor currently running: build flashed from
  `f9460a508c04594cff49880ce973467a66db3bff` with live experimental guest
  unit edits and live BOTW/xeyes/etc passthrough state present.
- Layers 0–13 considered in place.
- Layer 14+ as defined in this document is not yet implemented.

---

## What we could remove from the ROCKNIX build

If this direction lands, ROCKNIX shrinks dramatically. The bulk of today's
image is the emulation/media userspace, which moves into the guest.

### Keep on host (non-negotiable)

These define the "thin host" — they cannot move:

- Kernel + DTS + patches (`projects/ROCKNIX/devices/SM8550`,
  `packages/linux*`)
- Bootloader / `rocknix-abl` / `u-boot*`
- `linux-firmware` / `firmware-dragonboard` / `wlan-firmware`
- Hardware quirks (`projects/ROCKNIX/packages/hardware/quirks`)
- Update/recovery (`rocknix-update`, image, partition tools)
- `systemd`, `udev`, `busybox`, `util-linux`
- A minimal Wayland compositor for the recovery UI (probably keep `weston`
  or a stripped Sway, drop the full desktop session)
- Audio kernel side: `alsa-ucm-conf`, `alsa-topology-conf`, `alsa-lib`
  (kernel surface, not the whole stack)
- Sleep/input plumbing: `input_sense`, `rocknix-fake-suspend` (or its
  successor)
- nix-integration tooling
- `openssh` host on port 22 for recovery access
- nspawn binary path / guest launcher

### Candidates to remove or shrink dramatically

#### Whole gaming/userland stack — move to guest

This is the biggest win. ROCKNIX today is mostly an emulation distro; in
main-space mode the guest owns this:

- `projects/ROCKNIX/packages/ui/emulationstation`
- `projects/ROCKNIX/packages/ui/themes`
- `projects/ROCKNIX/packages/emulators/libretro/*` (dozens of cores)
- `projects/ROCKNIX/packages/emulators/standalone/*`
- `packages/emulation/libretro-*` (mainline libretro cores in `packages/`)
- `projects/ROCKNIX/packages/apps/{commander,fileman,qterminal,gamecontrollerdb,gamepadtester,jstest-sdl,m8c,mangohud,moonlight,portmaster,sdljoytest,sdltouchtest,sdl2text,gamescope,...}`
- RetroArch assets, joypads, overlays, libretro-database
- `packages/mediacenter/kodi` and all `kodi-binary-addons` (huge)
- `packages/addons/*` Kodi addon packaging

This alone is the dominant share of the build size and build time.

#### Network userspace — move to guest

- `connman` (currently host)
- `networkmanager` (lives in guest)
- `iwd`
- `bluez` userspace (keep kernel + firmware on host, move user daemon)
- `avahi`, `nss-mdns`
- `samba`, `nfs-utils`, `wsdd2`, `cifs-utils`, `rpcbind`, `libnfs`
- `openvpn`, `wireguard-tools`, `tailscale`, `zerotier-one`
- `rclone`, `syncthing`, `speedtest-cli`, `sshpass`, `simple-http-server`
- `rsync` (keep a small one on host for recovery)

#### Audio userspace — move to guest

Keep ALSA UCM/topology/firmware on host. Move the daemons:

- `pipewire`
- `pulseaudio`
- `wireplumber`
- `alsa-utils` user tools
- `espeak-ng`, `fluidsynth`, `SDL2_mixer`, `libxmp`, codecs (`fdk-aac`,
  `flac`, `lame`, `ldacBT`, `libldac`, `libmodplug`, `libopenmpt`,
  `libsamplerate`, `libsndfile`, `libvorbis`, `openal-soft`, `opus`,
  `sbc`, `sidplay-libs`, `soxr`, `speex`, `speexdsp`, `taglib`, `wavpack`)

#### Multimedia / graphics userspace — mostly move to guest

Host needs DRM/Mesa for the recovery compositor only. Most of the rest is
gaming-only:

- `ffmpeg` (huge), `aom`, `dav1d`, `gstreamer`, `intel-vaapi-driver`,
  `media-driver`, `nvidia-vaapi-driver` (irrelevant on Thor anyway),
  `libva-utils`, `vdpauinfo`
- `libbluray`, `libdvdcss`, `libdvdnav`, `libdvdread`, `libaacs`,
  `libbdplus`, `rtmpdump`, `zvbi`
- Graphics libs that only matter to apps: `assimp`, `cairo`, `exiv2`,
  `gdk-pixbuf`, `glew`, `glm`, `glmark2`, `harfbuzz`, `jasper`, `lcms2`,
  `libde265`, `libheif`, `libjpeg-turbo`, `libpng`, `libprojectM`,
  `libraw`, `pango`, `tiff`, `kmscube`, `kmsxx`
- `freetype` (host might need a stub for recovery text — keep tiny)

#### Browser / web stack — remove from host

- `packages/addons/browser/*`, any chromium/electron flavors
- `nghttp2`, `libmicrohttpd` if only used by user apps
- Keep just `curl`/`openssl` for recovery/update

#### Languages / runtimes in target image — remove

Anything ending up in the runtime image that isn't required by recovery:

- `lang/Python3` runtime (host scripts that need it should move to
  busybox/sh; user Python lives in guest)
- `lang/lua52`, `lang/lua54` runtime (only RetroArch/ES need it, both in
  guest)
- `lang/nasm` — build-only anyway, keep
- `rust/cargo`, `rust/rust*`, `rust/cbindgen`, `rust/bindgen-cli` —
  build-only
- `devel/groovy`, `commons-lang3`, `commons-text` — only for
  kernel-config doc tooling

#### Misc removable from runtime

- Steam-related leftovers from prior layer experiments
- `box86` (if not needed)
- Most `python/*` runtime modules
- `mangohud`, `gamescope` (move to guest if used)
- `m8c`, `moonlight`, `portmaster`, etc. (clearly app-shelf)
- `bkeymaps`, `eventlircd`, `evrepeat`, `lirc`, `ir-bpf-decoders` (only if
  device doesn't need IR remote)
- `samba` and `nfs-utils` — guest

### Order-of-magnitude savings

The two biggest wins are:

1. Removing the entire emulator + EmulationStation + libretro + Kodi tree.
   This is the bulk of the ROCKNIX image by size and by build time. It
   moves to the guest.
2. Removing the multimedia/codec/audio userspace tree. Second biggest.

After that, removing browsers, NetworkManager-class userspace, and
language runtimes is meaningful but smaller.

Rough mental model:

```text
Today's ROCKNIX image ≈ kernel + drivers + systemd + ES/RA/Kodi/cores/ffmpeg/codecs/UI
Thin-host ROCKNIX     ≈ kernel + drivers + systemd + recovery UI + sleep/input + nix-integration
```

Likely 60–80% smaller image, dramatically faster CI builds, far fewer
per-device userspace bugs to maintain.

### What still needs to live on host even after stripping

- A small recovery compositor (Weston or a stripped Sway)
- A minimal recovery shell + `nixctl` + image-update tools
- `openssh` host (port 22) for recovery access
- Enough networking on host to fetch updates if guest is broken (or skip
  this and require ethernet/USB recovery)
- Sleep/input watchdog
- nspawn binary path / guest launcher

### Caveats

- This list is by package directory, not by final image content. Some
  packages are already build-only and don't appear in the runtime image;
  they're listed here to flag them as "don't bother building anymore" if
  no remaining package depends on them.
- Migration order matters. Don't strip a package from host until the
  guest demonstrably owns the equivalent (e.g. don't drop host audio
  userspace until guest audio is proven through PipeWire passthrough).
- The shrinking should be staged behind a build flag (e.g.
  `THIN_HOST=yes`) so existing ROCKNIX images stay buildable during the
  transition.

---

## Live findings (2026-05-07 evening session)

Device was back online; ran the two-canary plan and one bonus spike at
guest-owned compositor.

### Canary 1 — visible guest terminal ✅

Footprint: launched a Wayland terminal *from inside the guest closure*
against host Sway.

What happened:

- Started experimental `rocknix-guest.service` (the broad-bind unit).
- Inside guest namespace, the system closure has real `nix`,
  `nixos-rebuild`, `nixos-option`, etc. (683 binaries in the system
  profile). No terminal/Wayland tool is in the closure by default —
  `xterm` was only present as a `.drv`, not built.
- Ran `nix run nixpkgs#hello` from inside guest — fetched and ran
  successfully (proved Nix tooling works on-device against
  `cache.nixos.org`).
- Ran `nix run nixpkgs#foot --title=NIX-MAIN-SPACE -e … sleep 600` — foot
  fetched fresh from cache, opened on host Sway, visible/focused as
  `app_id=foot`, title `NIX-MAIN-SPACE`.

Result: First real “guest closure pixels on screen” canary, not just a
rebound host binary.

### Canary 2 — guest-launched EmulationStation ✅

What happened:

- Found ES is started by `essway.service` on the host (`Restart=always`),
  not autostart — our earlier `pkill` attempts were instantly respawned
  by host systemd.
- Stopped `essway.service` cleanly.
- Launched ES from the guest mount+PID namespace via
  `systemd-run --scope` + `nsenter`, executing host’s
  `/usr/bin/emulationstation --log-path /var/log --no-splash` directly
  (skipping `start_es.sh` which depends on `/bin/bash`).
- Verified ES (PID 26339) was inside the guest’s `mnt:[4026532955]` and
  `pid:[4026532958]` namespaces, *not* host’s.
- ES appeared in Sway tree as `app_id=emulationstation`; host
  `essway.service` remained `inactive`.

Result: ES can be moved into guest namespace *while still using host
binaries via `/usr` bind*. The harder step is cutting the dependency on
host `/usr` and getting ES into the guest closure proper.

### Bonus spike — guest-owned Sway compositor ⚠️ partial

Goal: have the guest run its own Sway, owning DRM master, instead of
just drawing into host Sway.

What happened:

- `nix build nixpkgs#sway` from inside guest succeeded:
  `/nix/store/177qnw3n09799g8gq2dmr53hgsn3mx3m-sway-1.11`
- Stopped `essway.service` and `sway.service` on host (host SSH on
  port 22 unaffected).
- First sway run failed at libseat: no `/run/seatd.sock`, no logind
  primary session.
- Switched to `LIBSEAT_BACKEND=builtin`; libseat opened, but failed
  to open `/dev/tty0` because the guest’s nspawn-synthesized `/dev`
  has no real TTY nodes.
- `mknod` inside the guest mount namespace for `/dev/tty0`,
  `/dev/tty1`, `/dev/console` succeeded. (Host bind-mount approach
  failed because the underlying host path doesn’t exist before
  nspawn’s synthesized `/dev` is overlaid.)
- Sway then opened `/dev/dri/card0` as `msm`, found 4 CRTCs and 10
  planes, atomic + ADDFB2 modifiers supported.
- Sway died at renderer init:
  - GLES2: `EGL_EXT_platform_base not supported`
  - Vulkan: `ERROR_INCOMPATIBLE_DRIVER`
- Root cause: guest closure has only `mesa-libgbm`, not the full Mesa
  userspace + Adreno (`freedreno`/`turnip`) DRI driver. Guest config
  lacks anything equivalent to `hardware.graphics.enable = true`.
- Tried grafting host Mesa via `LD_LIBRARY_PATH=/usr/lib`. That
  poisoned sway’s own libwayland-server etc., causing immediate exit.
- Restored host display cleanly using a pre-staged
  `/tmp/restore_host_display.sh` (start `sway.service`, then
  `essway.service`).

Result: guest Sway gets all the way to DRM master + atomic display.
Missing piece is graphics drivers in the guest closure.

### Other live observations

- Guest had no DNS — `/etc/resolv.conf` in the guest rootfs was empty.
  Wrote `nameserver 1.1.1.1` / `nameserver 8.8.8.8` to fix.
- Guest had no `/bin/bash` — fixed with a symlink
  `/bin/bash → /usr/bin/bash` in the guest rootfs.
- ROCKNIX `start_es.sh` shebang is `#!/bin/bash`, so without the
  symlink it dies with `bad interpreter`.
- `getcwd: cannot access parent directories` errors are harmless
  artifacts of the outer host shell after `nsenter` enters the guest
  mount namespace; they do not affect the inner program.
- `pgrep -f` with carat anchor (`'^emulationstation'`) sometimes
  missed the process; `pgrep -af` then filtering by `awk` is more
  reliable.
- Host `essway.service` has `Restart=always` and `WantedBy=rocknix.target`
  — needs explicit `systemctl stop` (and ideally a no-respawn flag)
  before any handoff.
- Host `sway.service` is also `Restart=always`; same caveat.
- Both canaries used `systemd-run --scope --no-block` to keep the
  launch alive after the SSH session closed; this is the durable
  pattern for any later Layer 14 “guest-owned X” unit.
- `/dev/tty0`/`/dev/tty1`/`/dev/console` need to be present in the
  guest — either mknod’d at unit start, or added to the nspawn unit as
  explicit `--bind=/dev/tty0:/dev/tty0` etc., or via a guest
  `tmpfiles.d` rule that mknods them on boot.

### Performance / risk reality check

- nspawn overhead remains negligible (consistent with the BOTW result).
- Host SSH on port 22 stayed up throughout, including during the sway
  spike. SSH-as-recovery is real and reliable.
- The biggest practical risk for Layer 14 is **graphics driver
  packaging in the guest closure**, not namespacing or sleep.

### Feasibility assessment

Revised odds based on what we observed live, not just from theory:

```text
Working main-space prototype on Thor:                       80–90%
Daily-driver on Thor (single device):                       60–75%
Releasable for SM8550 handhelds (Thor + Odin 2 Portal):     50–70%
```

Note: “multi-device” is now defined as just Thor + Odin 2 Portal, both
on SM8550. The earlier 35–50% figure was for arbitrary handhelds
across the full ROCKNIX matrix; that problem is no longer in scope.

What raises odds:

- Target Thor only first.
- Treat ROCKNIX userland as removable, not preserved.
- Bake the canary + reclaim contract in from the start.
- Get Mesa/Adreno into the guest closure properly (not via host bind).

What lowers odds:

- Trying to keep ROCKNIX userland as a parallel fallback.
- Scope creep beyond Thor + Odin 2 Portal.
- Underestimating Mesa/Adreno driver compatibility work.
- Letting the experimental broad-bind unit drift further before
  formalizing a Layer 14 module.

### What changed in the next-step list

- **Milestone 14 (canary)** is now *partially proven*:
  - Guest-closure Wayland client on host display: ✅
  - Guest-launched ES (still using host binaries): ✅ with caveats
  - Guest-owned compositor: still ahead, blocked on graphics packaging.
- **New explicit prerequisite for guest-owned Sway:**
  - Add `hardware.graphics.enable = true` (or 25.11 equivalent) to the
    guest NixOS config.
  - Pin freedreno/turnip in the closure.
  - Provide `/dev/tty*` and `/dev/console` to the guest declaratively.
  - Provide a tested host-display reclaim path; do not rely on hand-
    pasted `/tmp/restore_host_display.sh`.
- **DNS contract**: guest must have a working `/etc/resolv.conf` from
  the unit (bind-mount `/run/rocknix/resolv.conf` ro, or generate
  declaratively).
- **`/bin/bash` contract**: any host script we want to run unmodified
  inside the guest namespace assumes `/bin/bash`. Either keep that
  symlink in the guest rootfs declaratively, or stop relying on host
  scripts — prefer the latter as we move toward main-space.

---

## Tier-A spike batch (2026-05-07 late evening)

Nine targeted, low-risk validations against the live device. Host SSH
on port 22 stayed up throughout. Host display restored cleanly
between/after spikes.

### ✅ Spike 1 — `nixos-rebuild switch`-equivalent inside guest (Milestone 17 proof)

**Result: PASS.** This is the single biggest result of the spike batch.

What we did:

1. Staged the guest flake (`flake.nix`, `flake.lock`,
   `rocknix-guest.nix`) into `/etc/nixos` inside the guest.
2. From inside guest namespace, ran:
   ```sh
   nix --extra-experimental-features 'nix-command flakes' eval --raw \
       .#nixosConfigurations.rocknix-guest.config.system.build.toplevel.outPath
   ```
   Output matched the running system path *exactly* — evidence the
   running closure is reproducible from the flake.
3. Modified `rocknix-guest.nix`: added `htop` to `systemPackages` and
   set `environment.sessionVariables.ROCKNIX_GUEST_REV = "rev2"`.
4. Ran `nix build --option sandbox false` for
   `.#nixosConfigurations.rocknix-guest.config.system.build.toplevel`.
   Build succeeded after one work-around (see below).
   New path: `dlsz2rf3avscsblsymwpgyz0i3r0d7n3-nixos-system-...`
5. `switch-to-configuration test` activated the new system inside the
   guest. `/run/current-system` advanced to the new store path.
   `htop --version` ran from the new closure.
6. Host kernel still `7.0.2`, host `BUILD_ID=f9460a508c…` unchanged,
   host services `sway.service`, `essway.service`,
   `rocknix-guest.service`, `sshd.service` all active.

**Implication for Milestone 17:** the management loop already works on
device. We can iterate guest config, build, switch — with zero impact
to host kernel/bootloader/initramfs. This validates the entire
“main-space” management story at the closure level.

**Two real gotchas surfaced:**

- `--no-flake-update` is **not** an option in `nixos-rebuild-ng` 25.11.
  Drop it from any wrapper.
- Build aborts with
  `cannot unlink …etc-ssh-authorized_keys.d-root: Device or resource busy`
  whenever the new config produces an *identical* store path for a
  file that’s currently bind-mounted by the broad-bind unit. Two such
  paths today: `etc-ssh-authorized_keys.d-root` and `etc-profile`.
  Cause: the rocknix-guest.service unit binds `/etc/profile` and
  similar from the host, and inside the guest those paths resolve
  through symlinks into `/nix/store/<hash>-etc-...`, pinning the store
  path as a mount.
  Workaround for now: change config so a different hash is produced
  (different content) on those files. Real fix in Layer 14: the
  guest unit must **not** bind host `/etc/profile` and similar onto
  guest store paths.

**One additional gotcha for cold restart (see Spike 7):**
`/run/current-system` did not survive the restart, because /run is
tmpfs and the symlink we wrote was ephemeral. Layer 14 must seed
`/run/current-system` (and `/run/booted-system`) at unit start from
`/nix/var/nix/profiles/system`.

### ⚠️ Spike 2 — backlight write blocked (sleep-UX primitive)

**Result: blocked by default `/sys` ro mount.**

- Two backlight nodes visible: `ae94000.dsi.0` (max 255, current 12)
  and `ae96000.dsi.0` (max 4096, current 204).
- Reads work from guest.
- Writes fail with `Read-only file system`.
- Cause: `systemd-nspawn` mounts `/sys` read-only by default.
- Fix: explicit `--bind-rw=/sys/class/backlight/ae96000.dsi.0` (or
  `BindReadWritePaths=`) in the unit. Same fix unblocks LEDs and
  cpufreq governor writes.

### ✅ Spike 3 — telemetry visibility

**Result: PASS.** Full UI surface available read-only:

- `power_supply`: battery (capacity/status/voltage/current),
  qcom-battmgr-usb, qcom-battmgr-wls, ucsi-source PSY.
- `thermal_zone0–20+`: aoss0/1, cpuss0/1, cpu0–7 multi-tier
  (top/middle/bottom), gpu, mem, video.
- `devfreq`: `1d84000.ufshc` and `3d00000.gpu`, governors readable.
- `cpufreq`: policy0 with `ondemand` governor, `1228800` Hz visible.
- `leds`: 4 LED groups (`l:b1…b4`, `l:g1…g4`, `l:r1…r2`).

Guest UI can render battery, charging, temp, freqs, RGB lighting.

### ⚠️ Spike 4 — audio: sees cards, missing `/dev/snd`

**Result: partial.**

- `/proc/asound/cards` inside guest correctly shows `AYNOdin2 [sm8550]`.
- `/dev/snd` is **not** bound — `aplay -l` reports “no soundcards”.
- Fix: add `--bind=/dev/snd` (and read/write device permissions) to the
  guest unit. After that we can spike PipeWire/Pulse in guest.
- Open question for Layer 14: ALSA can’t be opened by host PipeWire
  *and* guest at the same time. Audio is exclusive; whoever holds it
  must hand off cleanly. Likely answer: guest owns audio entirely,
  host has no PipeWire.

### ⚠️ Spike 5 — bluetooth: sees hci0, missing `/dev/rfkill`

**Result: partial.**

- `/sys/class/bluetooth/hci0` visible, but DOWN at the moment.
- `/dev/rfkill` not bound — cannot soft-block/unblock.
- bluez tools (`hciconfig`, `bluetoothctl`) only present via host
  `/usr` leak; the guest closure has none yet.
- Fix: bind `/dev/rfkill`, add bluez to the guest closure, and
  arbitrate ownership of `bluetoothd` (host vs guest).

### ✅ Spike 6 — input event passthrough

**Result: PASS with caveat.** 11 of 12 input devices visible.

Host has 12 event devices including:
- `event0` pmic_pwrkey, `event1` pmic_resin, `event2` haptics
- `event3` **AYN Odin2 Gamepad** (physical)
- `event4`/`event5` ft5x06 touch
- `event6` gpio-keys
- `event7` `InputPlumber Keyboard` (virtual)
- `event8` `InputPlumber Mouse` (virtual)
- `event9` Microsoft Xbox Series S|X Controller

Guest sees `event0,1,2,4,5,6,7,8,9,10,11` — **`event3` is missing**
because `InputPlumber` exclusive-grabs the physical gamepad and exposes
it only as virtual events `event7`/`event8`.

**Implication for Milestone 14+:** real controller passthrough on
this hardware means guest must either:
- Consume InputPlumber’s virtual devices (cleanest), or
- Take over InputPlumber itself.

We should not try to grab the raw `event3` from guest while host
InputPlumber holds it.

### ✅ Spike 7 — cold guest restart timing

**Result: PASS.**

- `systemctl stop rocknix-guest.service`: 0.69s
- `systemctl start rocknix-guest.service`: 0.11s (returned
  immediately; nspawn forks).
- New MainPID/innerPID re-acquired cleanly.
- `nsenter` into the new namespace works on first try.

**Caveat:** the manually-symlinked `/run/current-system` did **not**
persist (as expected; /run is tmpfs). Layer 14 must seed it from
`/nix/var/nix/profiles/system` on startup, e.g. via an
`ExecStartPre` or a `tmpfiles.d` rule executed early in guest boot.

Observed cleanup quirk: `systemd-nspawn` PID lingers a few hundred ms
after `is-active=inactive` is reported. Not a blocker, but worth a
note when scripting handoffs.

### ✅ Spike 8 — NTP / time

**Result: PASS at the kernel level.** Same wall clock host-vs-guest
(host EDT 22:44:42 ≡ guest UTC 02:44:42). Kernel clock is global;
guest doesn’t need its own NTP daemon.

Gap: guest has no `/etc/localtime`; everything reads UTC. Fix in
guest config: set `time.timeZone = "America/New_York";` (or
appropriate). Trivial.

### ✅ Spike 9 — GC scope

**Result: PASS.**

- Total store paths: 1423; size 2.9G.
- Reachable from `/run/current-system`: 462 paths.
- GC dry-run dead set: 2218 entries (includes `.drv`s from our build).
- All listed dead paths are under `/nix/store` — GC does **not** see
  any host path. No leakage.

Note: nix-store reports liveness based on `/proc/*/environ` and other
running-process closures, which is correct behavior — the guest’s GC
respects what’s currently live in the namespace.

### Cross-cutting takeaways from the Tier-A batch

1. **Milestone 17 (real `nixos-rebuild` loop in guest) is proven on
   device today.** This was the single biggest unknown from before;
   it now becomes a build-out task, not a research task.

2. **The broad-bind unit is the main source of friction.** It causes
   five separate observed problems:
   - Host /usr/lib/systemd units leaking into guest (sshd, tz-data,
     etc.) and failing on activation.
   - `etc-profile`, `etc-ssh-authorized_keys.d-root` getting pinned
     as bind-mounts onto guest store paths, blocking nixos-rebuild.
   - Host `htop`/`bash`/etc. shadowing the guest closure on PATH.
   - Mesa userspace mismatch when the guest tries graphics
     (precondition for guest-owned sway).
   - General hybrid “whose `/etc/profile` is this?” ambiguity.
   Layer 14 should replace this unit with a tightly scoped one whose
   binds are: device nodes only, not host filesystems.

3. **Sysfs writes are the second-largest blocker.** `/sys` is read-only
   by nspawn default. Owners of backlight, LEDs, governors, devfreq
   need explicit `BindReadWritePaths=` in the unit.

4. **Device-node binds are the third gap.** `/dev/snd`, `/dev/rfkill`,
   and possibly `/dev/uinput` (for InputPlumber-class virtual devices)
   need explicit binds.

5. **`/run/current-system` must be seeded at unit start** for `nix`
   tooling and any “current system” UI to work after restart.

6. **Audio and Bluetooth are exclusive resources.** No safe shared
   ownership; in main-space mode, guest takes them and host has none.

7. **InputPlumber owns the physical gamepad on Thor.** Layer 14 must
   either move InputPlumber into the guest, or have guest consume
   InputPlumber’s virtual devices, not physical `event3`.

8. **Time & GC behave correctly** — no work needed beyond a timezone
   setting.

### Updated explicit Layer 14 unit requirements (from this batch)

The replacement guest unit should:

- Bind no host filesystems except where necessary (no `/usr`, no
  `/lib`, no `/etc/profile`).
- Bind device nodes: `/dev/dri`, `/dev/input`, `/dev/snd`,
  `/dev/rfkill`, `/dev/tty0..N`, `/dev/console`, `/dev/uinput`.
- Mount `/sys/class/backlight/<panel>`, `/sys/class/leds`,
  `/sys/class/devfreq/*/governor`, `/sys/devices/system/cpu/cpufreq`
  read-write.
- Seed `/run/current-system` and `/run/booted-system` at start.
- Provide `/etc/resolv.conf` (declarative, not handwritten).
- Set `time.timeZone` in guest config.
- Not assume `/bin/bash` is present unless the closure provides it.
- Include a recovery contract: if guest fails to come up within N
  seconds, host owns display/audio/input again.

### Confidence updates

Based on the live evidence:

- **Real `nixos-rebuild switch` in guest:** moved from “theoretical” to
  **proven**. Confidence ~95%.
- **Telemetry / battery / thermal UI:** moved to **trivial**. ~98%.
- **Backlight / LED / governor control:** simple unit fix. ~90%.
- **Audio / Bluetooth in guest:** plausible, requires unit binds plus
  exclusivity dance. ~75–85%.
- **Controller passthrough:** depends on how we treat InputPlumber.
  ~70–85%.
- **Cold guest restart UX:** fast and clean once `/run/current-system`
  is seeded. ~90%.
- **NTP/time:** ~98%.

The earlier estimate stands but is now better-grounded:

```text
Working main-space prototype on Thor:                       85–90% (was 80–90%)
Daily-driver on Thor (single device):                       65–75% (was 60–75%)
Releasable for SM8550 handhelds (Thor + Odin 2 Portal):     55–70% (was 35–50%; scope narrowed)
```

---

## Tier B live findings (2026-05-07 night session)

Followed up the Tier-A spikes with the harder, higher-leverage Tier-B
set. **All three landed.** The main result: guest-owned Sway compositor
on Adreno is real and rendering, end-to-end, from a guest-only Mesa
closure.

### Spike B1 — GPU access from guest closure ✅

Goal: prove Mesa from `nixpkgs#mesa` can drive the SM8550 Adreno via
the vendor `msm` kernel driver, before risking another compositor
spike.

What worked:

- Built `nixpkgs#mesa-demos`, `nixpkgs#libdrm`, `nixpkgs#vulkan-tools`,
  and `nixpkgs#mesa` from inside the guest with `--option sandbox false`
  (host kernel lacks user-namespace sandbox setup nix expects).
- `modetest -M msm` from the guest enumerates the full DRM topology
  *without* needing DRM master:
  - Driver: `MSM Snapdragon DRM` v1.13.0
  - Encoders: 33 DSI, 36 DSI, 38 TMDS, 41 Virtual
  - Connectors: DSI-1 (the handheld panel) at 1080x1240@60, DSI-2 (the
    HDMI/external surface) at 1920x1080.
- Vulkan loader from guest closure successfully loads
  `freedreno_icd.aarch64.json` against `libvulkan_freedreno.so` from
  guest Mesa, *not* the host’s `/usr/lib/libvulkan_freedreno.so` (which
  is reachable but blocked by missing host libs in the guest):
  ```text
  vendorID  = 0x5143  (Qualcomm)
  deviceName = Turnip Adreno (TM) 740
  driverID   = DRIVER_ID_MESA_TURNIP
  driverName = turnip Mesa driver
  driverInfo = Mesa 25.2.6
  ```
- EGL surfaceless platform initialized cleanly: `EGL driver name: msm`,
  `EGL_EXT_platform_base` advertised — the very extension whose
  absence killed the first sway spike.
- EGL GBM platform initialized after wiring NixOS’s standard
  `/run/opengl-driver` layout manually:
  - `/run/opengl-driver/lib/dri → mesa/lib/dri`
  - `/run/opengl-driver/lib/gbm → mesa/lib/gbm` (note: `lib/gbm`,
    not `lib/dri` — first attempt symlinked the wrong dir, easy mistake)
  - `/run/opengl-driver/share/glvnd → mesa/share/glvnd`
  - `/run/opengl-driver/share/vulkan → mesa/share/vulkan`
- Required env vars to hide host-leaked Vulkan/EGL config and pin the
  guest closure:
  ```sh
  __EGL_VENDOR_LIBRARY_FILENAMES=$MESA/share/glvnd/egl_vendor.d/50_mesa.json
  LIBGL_DRIVERS_PATH=$MESA/lib/dri
  __GLX_VENDOR_LIBRARY_NAME=mesa
  VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/freedreno_icd.aarch64.json
  LD_LIBRARY_PATH=$MESA/lib
  ```

Result: **GPU access from guest closure is fully working** — OpenGL
ES via GBM and Vulkan via Turnip both target the Adreno 740. This
directly mirrors what `hardware.graphics.enable = true` does on a
standard NixOS install; it just needs to be declarative in the guest
NixOS config rather than wired by hand.

### Spike B2 — Guest-owned Sway compositor ✅

Goal: replay the original sway spike with proper Mesa wiring and see
if the renderer comes up.

Setup carried over from B1:

- `/run/opengl-driver` layout from B1.
- `/dev/tty0`, `/dev/tty1`, `/dev/console` `mknod`’d in the guest
  mount namespace (lost across host reboots; need a declarative
  source in Layer 14).
- `LIBSEAT_BACKEND=builtin`, `WLR_LIBINPUT_NO_DEVICES=1` (skip
  libinput probe so we don’t fight host InputPlumber for `event3`).
- Stopped `essway.service` and `sway.service`, masked `sway.service`
  via runtime mask (`/run/systemd/system/sway.service → /dev/null`)
  so `Restart=always` doesn’t fight us. *(Also `essway.service`
  picked up a runtime mask during the spike and had to be unmasked
  at the end — see notes below.)*
- Guest sway launched via `systemd-run --unit=guest-sway.scope --scope`
  + `nsenter` into the guest mnt+pid+net+ipc+uts+pid namespaces.

What happened:

- Sway started, spawned a `dbus-run-session` automatically, then forked
  the actual compositor.
- DRM master taken on `/dev/dri/card0`. `fuser` confirmed sway PIDs
  95336/95338 owning the device.
- Both panels lit up:
  - DSI-1 1080x1240 (handheld panel) with workspace `2`
  - DSI-2 1920x1080 with workspace `1`
- GBM allocated framebuffers with format XR24 modifier `COMPRESSED`
  (`0x0500000000000001`) — UBWC compression on Adreno is being used.
- GLES2 renderer created GL FBOs against the GBM buffers.
- `swaybg` rendered the configured `#000033` background as a layer-
  shell wallpaper surface.
- `foot` (from guest closure, `dbc6mwx7rvm8wvswxaqv1n0lyfg8qd12`)
  attached as `app_id: foot`, title `GUEST-MAIN-SPACE-OK`. Tree
  representation: `H[foot]` on DSI-2.
- All sway/swaybg/foot processes verified inside guest mount
  namespace `mnt:[4026532955]`, PID namespace `pid:[4026532958]` —
  *not* host’s.

Notable detail — first foot from `exec` in `sway-minimal.conf` died
immediately with `failed to get current working directory: No such
file or directory`. Cause: we had nsenter’d with `--wd=/`, sway was
launched from there, sway forwarded that cwd to the exec’d child,
and foot tried to call `getcwd()` and failed. Fix: launch foot from
a real path (we used `--wd=/tmp` for the second attempt), or set
workingdir in the spawning unit. Trivial issue, but worth baking
into Layer 14 unit (`WorkingDirectory=`).

Recovery: stopped `guest-sway.scope`, ran `/tmp/restore_host_display.sh`,
had to clean up the runtime mask of `essway.service` (a previous
session had left it masked at `/run/systemd/system/essway.service →
/dev/null`; required `rm` and `daemon-reload`). Layer 14 reclaim
path must explicitly *not* leave services masked.

Result: **the original Layer 14 unblocker is real**. A Mesa-equipped
guest closure renders a full sway compositor on Adreno hardware,
including both Thor display panels, with GLES2 + UBWC. Vulkan/Turnip
is available too. This is the central technical risk for the
main-space architecture, and it is now retired.

### Spike B3 — Second guest alongside the existing one ✅

Goal: confirm we can run a second nspawn from the same rootfs, useful
for a sandbox/canary instance later.

What worked:

- Direct second `systemd-nspawn` invocation against the live rootfs
  fails with `Directory tree /storage/machines/rocknix-guest is
  currently busy` (rootfs lock) — expected.
- `--ephemeral` mode (overlay snapshot semantics, even on ext4)
  allowed a second guest to boot with hostname `rocknix-canary`,
  separate PID namespace, separate mount namespace.
- The main guest’s namespaces `mnt:[4026532955]` /
  `pid:[4026532958]` were untouched throughout.
- Verified isolation: writes inside the ephemeral guest (e.g.
  `/tmp/canary` placeholder file) did *not* surface in the
  underlying `/storage/machines/rocknix-guest/tmp/`.

Result: **multi-guest co-existence is supported** for free via
`--ephemeral`. This unlocks future patterns:

- A throwaway “canary” guest for testing config changes before
  applying them to the main guest.
- A sandboxed `nixos-rebuild build`-side environment.
- A safe staging area for module experiments.

### Composite implications

With Tier-A and Tier-B together, the Layer 14 design space looks
like this:

```text
Proven possible from a guest closure on Thor:
  ✅ Real `nixos-rebuild`-equivalent activation in guest
  ✅ Read all telemetry (battery, thermal, devfreq, leds)
  ✅ See input devices (need IP arbitration story)
  ✅ Cold restart in <1s
  ✅ Real Vulkan on Adreno 740 (Turnip + Mesa 25.2.6)
  ✅ Real EGL/GLES on Adreno 740 (msm + GBM)
  ✅ Sway compositor on both DSI panels
  ✅ Side-by-side ephemeral guest

Still open / needs work:
  ⚠️ /sys writable for backlight, leds, governors
  ⚠️ /dev/snd, /dev/rfkill, /dev/uinput passthrough
  ⚠️ InputPlumber arbitration (consume virtual events vs. take over)
  ⚠️ Declarative /dev/tty*, /run/opengl-driver, resolv.conf
  ⚠️ Reclaim path that doesn't leave services masked
  ⚠️ Strip host network userland; move iwd/NM/tailscaled to guest
     (Tier C, shared-netns design)
```

### Updated feasibility odds

The single biggest risk — “can the guest actually drive the screen?” —
just got answered yes. Updating:

```text
Working main-space prototype on Thor:        90–95%   (was 80–90%)
Daily-driver on Thor (single device):        70–80%   (was 60–75%)
Daily-driver on Thor + Odin 2 Portal:        60–70%   (was 55–70%)
```

The remaining ~25–30% risk on daily-driver is now concentrated in:

1. Audio + Bluetooth ownership handoff (especially on suspend/resume
   races).
2. InputPlumber arbitration cleanly enough to keep gamepad/lid/power
   feel identical.
3. Wi-Fi reassociation behavior across resume and rfkill events with
   the guest as sole network manager (no netns move; see Tier C).
4. SM8550-specific firmware quirks not yet hit (camera, video, NPU).
5. Update/recovery contract that survives many switch cycles.

Not in the top risks anymore:

- Mesa/Adreno graphics packaging ✅
- Compositor on Adreno ✅
- GPU compute / Vulkan path ✅
- nspawn isolation / multi-guest ✅

### Recipe to bake into the Layer 14 unit

From what worked tonight, the `Layer 14` module should declare:

1. **Closure**: `pkgs.mesa`, `pkgs.libdrm`, `pkgs.vulkan-tools`,
   `pkgs.mesa-demos` (last two optional but cheap), `pkgs.sway`,
   `pkgs.foot`, `pkgs.swaybg`.
2. **NixOS-equivalent activation**:
   `hardware.graphics.enable = true;` (and the appropriate `extraPackages`
   list with `mesa.opencl` or `vulkan-loader` as needed). This
   automatically generates the `/run/opengl-driver` layout we wired
   manually.
3. **Device passthrough** in the nspawn unit (replacing the broad-bind
   horror):
   - `--bind=/dev/dri/card0` and `/dev/dri/renderD128`
   - `--bind=/dev/tty0`, `/dev/tty1`, `/dev/console` (the actual
     character devices, not host paths)
   - `--bind=/dev/input/event0..N` (or a curated subset; see InputPlumber
     arbitration story)
   - `--bind=/dev/snd` when guest takes audio
   - `--bind=/dev/rfkill` when guest takes Bluetooth/Wi-Fi
4. **Sysfs writes**: `/sys/class/backlight/<panel>/brightness`,
   `/sys/class/leds/*`, `/sys/class/devfreq/*/governor`,
   `/sys/devices/system/cpu/cpufreq` mounted RW. Default nspawn `/sys`
   is read-only; need explicit overrides.
5. **Compositor environment**:
   - `WLR_BACKENDS=drm,libinput`
   - `LIBSEAT_BACKEND=builtin`
   - `WLR_LIBINPUT_NO_DEVICES=1` until InputPlumber arbitration is
     decided.
   - `WorkingDirectory=/var/lib/sway` (or `/storage/sway`) so child
     processes never inherit a vanished cwd.
6. **Reclaim contract**: a `recovery.target` (or equivalent) that:
   - Stops the guest sway scope.
   - Verifies DRM master is released.
   - Unmasks `sway.service`/`essway.service` (idempotent).
   - Restarts host display stack.
   - Has a watchdog: if guest sway crashes within `N` seconds of
     start, host display reclaims.

### Caveat: graphics layer leak via host `/usr` bind

The broad-bind unit’s `/usr` bind exposes host’s
`/usr/share/vulkan/{icd,explicit_layer}.d/` and
`/usr/share/glvnd/egl_vendor.d/` to the guest. This mostly does’t hurt
because the host libs underneath fail to load (libz mismatch, runpath
mismatch), but it pollutes diagnostics and produces noisy errors. The
Layer 14 unit must drop the host `/usr` bind — already on the shopping
list from Tier A, now reinforced.

---

## Tier C live findings (2026-05-08, Wi-Fi)

Goal: validate that the guest can own Wi-Fi for the Layer 14+ main-space
design.

Run on Thor with all SSH via Tailscale (`100.104.158.120`), so SSH
survived brief Wi-Fi outages without dropping the agent.

> **Reframing note (added after the spike).** This section originally
> framed the problem as a *netns handoff* problem and concluded
> “veth+NAT recommended for Layer 14.” That recommendation was wrong.
> The main-space design does **not** need or want the guest in a
> separate netns from `wlan0` — it just needs the guest to be the
> only thing trying to manage the radio. The C3 ath12k limitation
> below is real but only matters for **side-by-side experimental
> guests** that need network isolation, not for main-space itself.
> The Layer 14 recommendation has been updated accordingly. The
> earlier spike work (C1 + C2) is preserved as evidence and remains
> useful for the side-by-side use case.

### C1 — guest-closure Wi-Fi tools ✅ PASS

Built `wpa_supplicant`, `networkmanager`, `iw`, `dhcpcd`, `nftables`
from guest closure via on-device `nix build nixpkgs#...`. Key paths:

- `/nix/store/5mnnvk51ijh046mfps90b9lq5kd63gys-wpa_supplicant-2.11`
- `/nix/store/py6h2i3hag4mnhxnx4rari0r4bklz4f4-networkmanager-1.54.3`
- `/nix/store/wxwbpc2vchsa26g754q4yiyv7lq2f7wf-iw-6.17`
- `/nix/store/s83a4yyxfr9c7gl1czv44lz5r6ssqbfi-dhcpcd-10.2.4`
- `/nix/store/7qg71z1qjlqmafk5azmvzpdandpql8dw-nftables-1.1.5`

All located under the **guest** rootfs at
`/storage/machines/rocknix-guest/nix/store/...` (not host’s `/nix/store`,
which does not have these). This matters: `ip netns exec` runs in the
host mount namespace, so anything we point at must use the guest store
prefix.

From inside the guest namespace, `iw dev wlan0 link` and
`nmcli device` cleanly read the active `vrackie` association without
disturbing host iwd. Confirms the guest can carry a complete Wi-Fi
userland without the host bind. **This, combined with the next
finding, is what unlocks main-space Wi-Fi.**

### C1.5 — the guest already shares the host netns ✅ (key insight)

Readlinks of `/proc/<host PID 1>/ns/net` and
`/proc/<guest PID>/ns/net` both return `net:[4026531833]`. The current
`rocknix-guest.service` unit does not pass `--private-network`, so the
guest is in the **same network namespace** as the host kernel’s root
netns.

This means:

- The guest can already see `wlan0`, `phy0`, `/dev/rfkill`,
  `/sys/class/net/wlan0`, and the `nl80211` socket.
- The only thing preventing the guest from running its own iwd /
  NetworkManager / wpa_supplicant against `wlan0` today is that the
  *host*’s iwd already holds the interface.
- For main-space, where we strip the host of network userland, that
  conflict goes away.

**Layer 14 main-space Wi-Fi design (correct version):** keep guest in
shared netns, move all network userland (iwd / NetworkManager /
connman / tailscaled / dnsmasq / etc.) into the guest closure, leave
the host with no network manager at all. The guest associates
`wlan0` directly. No netns move, no veth, no NAT.

### C2 — separate netns + veth + nft NAT ✅ PASS (still valuable, different use case)

This spike still passes and the result is still useful — just for the
*side-by-side experimental guest* use case, not for main-space.

What we proved:

- Host `ip` is busybox (no `netns` subcommand, no `nft`); used
  `iproute2` and `nftables` from guest closure paths.
- Created a `canary` netns, veth pair `canary-host` (host side,
  10.42.0.1/24) <-> `canary-guest` (in canary, 10.42.0.2/24), default
  route + nft NAT.
- DNS via `nslookup ... 1.1.1.1` resolved through NAT.
- TCP via `curl https://1.1.1.1` and `/dev/tcp/...` returned 301 / connected.
- conntrack table showed entries with NAT’d source
  `src=10.42.0.1 ... [UNREPLIED] src=<peer> ...`.

When this matters: any future *secondary* nspawn guest running
alongside main-space (sandbox guest, throwaway test guest, multi-user
slot, etc.) that needs its own network identity. For those cases,
veth + nft NAT is the correct pattern.

Kernel-side facts that fall out of this and matter regardless:

- **iptables-legacy is non-functional**: `ip_tables` module is missing
  from the kernel; `iptables -L` errors with “Table does not exist.”
  All firewall logic must be **nftables**.
- nftables nat path requires loading `nft_chain_nat`, `nft_nat`,
  `nft_masq` (modules present, not auto-loaded).
- `CONFIG_NF_NAT=y` and `CONFIG_NF_NAT_MASQUERADE=y` are built in.
- `rp_filter` per-interface defaults to `2` (loose) which is fine for
  netns NAT; no tweak needed.
- ICMP echo to public IPs (`1.1.1.1`, `8.8.8.8`) is filtered by the
  upstream network, but **TCP works fine** — ping is not a valid
  health probe on this network.

### C3 — ath12k phy netns move ⚠️ driver-limited (no longer a blocker)

This was the spike that originally led me astray. Recording the
finding because it matters for the side-by-side use case and because
it’s the kind of detail that’s easy to forget.

Driver: **`ath12k`** (Qualcomm Wi-Fi 7), wiphy attached via
`ath12k_wifi7_pci`. PCI ID `17cb:1107`, firmware
`ath12k/WCN7850/hw2.0/*`.

`iw phy phy0 info` lists `set_wiphy_netns` among supported commands.

What we observed:

- `systemctl stop iwd` removes the `wlan0` netdev *but leaves phy0
  intact* (visible in `iw phy`, in `/sys/class/ieee80211/phy0`,
  `rfkill` still shows `phy0: wlan` unblocked).
- `iw phy phy0 set netns name wifi-canary` returns `exit=0`. After
  the call, phy0 disappears from host’s `/sys/class/ieee80211/` and
  appears in the new netns’s `iw phy` listing. So the move command
  *itself* succeeds at the netlink level.
- However, inside the new netns,
  `iw phy phy0 interface add wlan0 type managed`
  fails with **“No such file or directory (-2)”, exit=254**.
- `wpa_supplicant -i wlan0` then logs
  `Could not read interface wlan0 flags: No such device`
  and exits.
- The reverse move `iw phy phy0 set netns 1` works from inside the
  netns; cleanup successfully restored host wlan0 + iwd reassociation
  + DHCP reissue + `vrackie` reconnect.

Likely root cause: ath12k netns support is partial. The phy descriptor
moves at the cfg80211 layer, but the driver doesn’t cleanly re-bind
its interface-creation path in the new netns. This is a driver-level
limitation we cannot fix in scope.

**What this rules out**: a side-by-side guest design that wants the
radio physically *moved* into the secondary guest’s netns. For
side-by-side, use C2 (veth + NAT) instead.

**What this does NOT rule out**: main-space. Main-space doesn’t move
the phy at all — it lets the guest manage the radio in the shared
netns where it already lives.

### Other operational findings (still valid)

- **Tailscale is a real safety net**: the SSH agent path went through
  `tailscale0`, which kept the *concept* of the connection alive
  through wlan0 outages. After the outage, the underlay reconnected
  automatically via DHCP and SSH resumed without re-prompting.
- A simple `systemd-run --on-active=Ns --unit=watchdog` timer is a
  reliable on-device watchdog pattern: 4 separate fires worked, all
  cleanly recovered the host network state.
- Detached scripts via `nohup ... </dev/null >/dev/null 2>&1 &; disown`
  let us run risky network operations without coupling them to the SSH
  session lifetime.
- `iwd` removes the `wlan0` netdev when stopped (only phy0 remains).
  Doesn’t matter for main-space (host iwd is gone), but matters for
  any test scenario that stops it midflight.
- Host has `/dev/rfkill` and the `rfkill list` tool, but **the guest
  unit currently does not bind `/dev/rfkill`** — add to Layer 14 unit
  if guest’s NM/iwd needs to control radio enable/disable.
- ROCKNIX kernel `7.0.2` lacks `ip_tables.ko` (legacy iptables);
  guest must use nftables. Ratchet implication: the host build
  doesn’t need iptables-legacy userland either.
- Host `ip` is busybox; full `iproute2` is only available via the
  guest closure today. The thin host ratchet doesn’t need to fix this
  — the guest brings its own `iproute2`/`nftables`.

### Updated feasibility odds (corrected)

```text
Working main-space prototype on Thor:        90–95%
Thor daily-driver (shared netns design):     75–85%
Thor + Odin 2 Portal releasable:             60–75%
```

Numbers up across the board because the apparent ath12k blocker turned
out not to apply to the design we actually want. Main-space Wi-Fi is
just “run NM/iwd in the guest, not the host” — which is exactly the
thin-host story we already wanted.

### Updated Layer 14 shopping list (Wi-Fi)

**For main-space (primary path):**

- Strip from the host build: `iwd`, `connman`, `NetworkManager`,
  `wpa_supplicant`, `dhcpcd`, `dnsmasq`, host-side `tailscaled`, and
  any host-side network UI shims.
- Add to guest closure: `iwd` (or `NetworkManager`), `wpa_supplicant`
  (transitively), `dhcpcd` (or `systemd-networkd`), `tailscale`,
  `iproute2`, `nftables`. Configure these declaratively in the guest
  NixOS module.
- Bind into the guest from host: `/dev/rfkill`, the `phy0` sysfs
  tree (already visible since shared netns + sysfs binds), and the
  Wi-Fi firmware path (`/lib/firmware/ath12k/...` if not already
  reachable from guest closure).
- Guest NixOS module turns on the matching `networking.*` /
  `services.tailscale.enable` / `networking.networkmanager.enable`
  knobs.
- Confirm guest sees `wlan0` and can call `iw dev wlan0 link` from
  within its own systemd unit context (already proven in C1).

**Recovery contract for main-space:**

- Host must keep enough network capability to come back if the guest
  fails to come up. Cheapest implementation: a tiny one-shot service
  on the host that runs `wpa_supplicant -B` against a recovery SSID
  (or the same SSID via a fallback config), only when the guest has
  not signaled “I own the radio” within N seconds of boot.
- Host `sshd` must be reachable on the recovery network. Tailscale
  on the host is *not* required for recovery if the underlay is up;
  the guest brings tailscaled in normal operation.

**For side-by-side experimental guests (secondary path, kept for
later):**

- Use C2’s veth + nft NAT pattern.
- Don’t attempt phy netns moves (ath12k blocked).
- Useful when you want a sandbox/test guest running concurrently with
  main-space, isolated from main-space’s network ownership.

### What not to carry forward from the original Tier C writeup

- The earlier draft’s recommendation “use veth + NAT for Layer 14
  main-space”. That was a reaction to the ath12k finding before I
  noticed the guest already shared the host netns. The correct
  answer for main-space is shared netns; veth + NAT is for secondary
  guests.
- The earlier draft’s implication that ath12k’s limitation slows the
  daily-driver milestone. It does not.

---

## Tier D live findings (2026-05-08, measurement batch)

Four measurement spikes on Thor (`100.104.158.120`), guest active, host
display running, no churn beyond what each spike required.

### D16 — host-path leak map for `rocknix-guest` ✅

Enumerated `/proc/self/mountinfo` from inside the guest mnt namespace:
48 mounts, 14 distinct sources.

**Content leaks (must remove or isolate in Layer 14):**

| Guest path | Host source | FS | Why it has to go |
| --- | --- | --- | --- |
| `/usr` | host `/usr` | squashfs | ROCKNIX userland; pollutes `PATH` |
| `/lib` | host `/usr/lib` | squashfs | host C libs poison Nix closure |
| `/etc/profile.d` | host `/etc/profile.d` | squashfs | env/PATH leakage |
| `/etc/profile` | `/nix/store/z5a5…etc-profile` | squashfs | pinned store path; breaks rebuilds |
| `/etc/ssh/authorized_keys.d/root` | `/nix/store/3cgj…keys` | ext4 | pinned store path; breaks rebuilds |
| `/storage` | host `/storage` | ext4 | broad shared filesystem, no isolation |

**Acceptable HW passthrough (keep, but spell out in Layer 14 unit):**

| Guest path | Host source | Reason |
| --- | --- | --- |
| `/dev/dri` | host `/dev/dri` | GPU |
| `/dev/input` | host `/dev/input` | controllers / lid |
| `/proc/asound` | host `/proc/asound` | audio metadata |
| `/var/log` | host `/var/log` | journals |

**Transitional (remove once guest owns its own display):**

- `/run/0-runtime-dir` ← host (host Wayland socket)
- `/tmp/.X11-unix` ← host (Xwayland socket)

**Nspawn-standard (untouched, fine):** `/run/host/*`, `/dev/shm`,
`/dev/pts`, `/dev/mqueue`, `/dev/hugepages`, masked `/proc/*` items.

**Missing today — Layer 14 should add:**

- `/dev/snd`, `/dev/rfkill`, `/dev/uinput`
- `/dev/tty0..N`, `/dev/console`
- `/sys/class/backlight/*` (RW)
- `/sys/class/leds/*` (RW)
- `/sys/class/devfreq/*` (RW)
- `/lib/firmware` (RO) for GPU/Wi-Fi firmware

Full dump archived at `/tmp/d16_findings.txt` on device.

### D17 — idle cost of running the guest ✅

Device plugged in, battery `Full`, so power-supply draw was unreliable.
Measured CPU/proc/memory cost over 30s windows instead.

| Metric | Guest UP | Guest DOWN | Delta |
| --- | --- | --- | --- |
| CPU busy | 2.52 % | 1.49 % | +1.0 pp |
| Process count | 259–260 | 243 | +16 procs |
| MemAvailable | ~14 026 MB | ~14 069 MB | ~ +35–40 MB used by guest |

Verdict: **idle guest is cheap.** Always-on rocknix-guest costs roughly
1 % of one core and ~40 MB RAM in the steady state on Thor. The cost
is dominated by guest systemd + journald + dbus.

Caveat: real idle *power* (watts on battery) was not measured because
the device was charging. Re-run on battery before declaring battery
impact safe. The CPU/RAM numbers strongly suggest battery cost will
be small but non-zero.

### D18 — host SSH stability under guest churn ✅

Ran five `systemctl stop` + `start` cycles on `rocknix-guest.service`
in a tight loop while probing `ssh root@thor true` every ~250 ms over a
25-second window.

| Probe | Value |
| --- | --- |
| Total connect attempts | 103 |
| Successful | 103 |
| Failed | 0 |
| `sshd` MainPID before churn | 772 |
| `sshd` MainPID after churn | 772 |
| `sshd` start-epoch before/after | identical |

Verdict: **port 22 sshd never blinked.** Host SSH is fully decoupled
from the guest lifecycle. This is the recovery contract we wanted:
no matter how badly Layer 14 work churns the guest, the device stays
reachable at `root@thor:22`.

### D19 — `nix copy` between guest and host stores ✅

**Setup discovery:**

- Host `/nix` is a real ext4 filesystem mounted from `/dev/sda19`,
  with 12 181 store entries.
- Guest store at `/storage/machines/rocknix-guest/nix/store` is
  separate, with 5 587 entries.
- Host has no `nix` CLI — only ROCKNIX helpers (`nix-doctor`,
  `nix-layer-activate`, `nixctl`). Guest closure has full `nix-2.31.5`
  at `/nix/store/10sajsl5…nix-2.31.5/bin/nix`.
- Some store paths are byte-identical between the two (deterministic
  Nix outputs), most are guest-only (additions from on-device builds
  during prior spikes).

**Bridging the stores:**

1. Bind-mount host `/nix` to a `/storage/host-nix-root/nix` location
   (visible inside the guest because `/storage` is bind-mounted).
2. Inside the guest, run
   `nix copy --no-check-sigs --to /storage/host-nix-root <guest-path>`
   using the chroot-store URI form.
3. Nix walks the closure and writes every path into the host store
   that is mounted underneath.

**Result:**

- Copied `mesa-25.2.6` (228 MB) and its full closure
  (`libdrm`, `libdrm-bin`, `libdrm-dev`, `mesa-libgbm`, `libxxf86vm`,
  `libxcb-keysyms`, `lm-sensors`, `libxshmfence`, `libpciaccess`)
  guest → host in one command.
- Verified persistence after unmount: `/nix/store/m79y8q4y…mesa-25.2.6`
  is now real on the host ext4 partition, not just visible through the
  bind.

Verdict: **guest can publish closures to host store without host
running a Nix daemon.** This unlocks a clean “guest builds, host
consumes” pattern for any future ROCKNIX image-build pipeline that
needs Nix outputs.

The reverse direction (host → guest) is easier still and uncontested:
ROCKNIX already seeds the guest rootfs from prebuilt closures in the
image, so the seed path is known to work.

### Combined Tier D takeaways for Layer 14

1. The guest has **6 host content leaks** that must end. Three are bind
   mounts (`/usr`, `/lib`, `/etc/profile.d`); two are *pinned Nix store
   path* binds (`/etc/profile`, `/etc/ssh/authorized_keys.d/root`)
   which are also the reason `nixos-rebuild switch` collapses today.
2. Idle cost of always-on guest is real but small (~1 % CPU, ~40 MB).
   No reason to gate Layer 14 on a “guest only on demand” UX.
3. Recovery contract is solid: port 22 sshd survives any reasonable
   guest churn. Build watchdogs around this assumption.
4. Two-store architecture (host store as “deployment target,” guest
   store as “build surface”) is mechanically possible without giving
   the host a Nix daemon. Useful as an option, not a requirement.

### Updated feasibility odds (post Tier D)

No material change. Tier D was confirmation, not breakthrough.

```text
Working main-space prototype on Thor:        90–95%
Thor daily-driver:                            70–80%
Thor + Odin 2 Portal releasable:              60–70%
```

The percentage moves from here on are about Layer 14 *implementation
quality*, not whether the architecture works. The architecture works.

---

## Tier E1 live findings (2026-05-08, host fake-suspend cycle)

First Tier E spike: 20× host-driven fake-suspend/resume cycles on Thor
while the rocknix-guest container was running. This is *not* guest-owned
fake-suspend (Milestone 18) — it tests whether ROCKNIX's existing
fake-suspend primitives stay reliable, and whether the guest survives
them cleanly while we plan the eventual handoff.

### How the test worked

Driver script: `/storage/e1-suspend-cycle.sh` (parameters `N=20`,
`SUSPEND_HOLD=2s`).

Each cycle did:

1. Snapshot pre state (≈20 metrics).
2. `rocknix-fake-suspend lid close` in background — invokes
   `do_suspend_actions` (DPMS off, audio mute, powersave governors,
   core parking, input grab via `evtest --grab`, LEDs off).
3. Sleep 2s, snapshot held state.
4. `rocknix-fake-suspend lid open` — invokes `do_resume_actions`
   (display on, unmute, restore governors, unpark cores, kill grabs,
   restore LEDs) and removes the lid-closed flag.
5. Sleep 1s, snapshot post state.
6. Pass criteria: held DPMS=Off, post DPMS=On, held governor=powersave,
   post governor=ondemand, post `cpus_active=8`, sway responsive, Wi-Fi
   still associated.

Lid open/close is the safest trigger — cleaner than `power` (no
shutdown-delay timer) and uses the production code path the firmware
actually invokes from `input_sense`.

### Results: 20 / 20 PASS

Every cycle, every metric, no anomalies. Host SSH stayed reachable
throughout.

Observed primitives behaving correctly each cycle:

- Display: `card0-DSI-1/dpms` toggled `On → Off → On`, same for DSI-2.
- CPU governor on `cpu0`: `ondemand → powersave → ondemand`.
- CPU online cores: `8 → 1 → 8` (core parking and unpark working).
- Input grabs: `evtest --grab` count `0 → 5 → 0`.
- ALSA PCM count steady at 2.
- Sway compositor responsive after every resume.
- Wi-Fi: `iw dev wlan0 link` showed `Connected to 14:21:03:fe:01:3d` in
  every snapshot — no reassociation, no drop.
- LEDs returned to colored state after each resume.

### Memory: no leak across 20 cycles

```text
baseline:  memused 2743 MB
pre  cycles 1–20:   2726–2742 MB band
post cycles 1–20:   2720–2737 MB band
final post-cycle:    2737 MB
```

Memory oscillates within a ~20MB band; *no monotonic growth*. Each cycle's
post is roughly equal to its pre. The fake-suspend cycle does not leak
over 20 iterations.

### Guest container: untouched

At end of run:

- Guest service still `active`, MainPID 156098.
- Guest inner uptime: 11525s (3h 12m) — the container did not restart.
- Guest mount/pid namespaces unchanged: `mnt:[4026532955]`,
  `pid:[4026532958]`.
- Guest hostname `rocknix-guest` intact.

The guest *rode through* 20 host fake-suspend cycles transparently.
Which makes sense: fake-suspend doesn’t actually suspend the kernel,
it just twiddles user-space (display, audio, governors, input grabs)
and parks all CPUs except cpu0. The guest, being scheduled by the host
kernel, simply sleeps when the host parks cores and resumes naturally.

### One quirk worth noting

Guest `/etc/resolv.conf` ended the run reset to:

```text
# Generated by resolvconf
options edns0
```

— i.e. without `nameserver 1.1.1.1` we wrote earlier. This is host’s
`resolvconf` re-running during the cycle and overwriting (because the
broad-bind unit doesn’t isolate `/etc` properly). Confirmed: the
DNS-bleed-from-host issue we already noted in earlier findings happens
in practice during operations like fake-suspend that touch network
userspace. **Layer 14 unit must own its own `/etc/resolv.conf`** — this
bug is now reproduced under load.

### Limitations of this test

- This is **host fake-suspend**, not guest-owned. Milestone 18 (guest
  owns the suspend UX) is still ahead.
- Real `PM_SUSPEND` (kernel suspend-to-RAM) is disabled on SM8550 by the
  ROCKNIX `030-suspend_mode` quirk. Not testable without DT/kernel work.
- No sustained workload was running. A game (BOTW, etc.) under load
  during cycles could behave differently.
- 20 cycles ≈ 1 minute of wall clock; not multi-hour stability.
- No Bluetooth controller was paired during the test, so BT-reconnect
  behavior is unmeasured here (covered in E5 plan).
- Wi-Fi was on cable-class link quality; degraded RF could expose
  reassociation timing issues invisible at strong signal.
- The script’s ping-based check had a regex bug (matched “1 received”
  but busybox prints “1 packets received”). The Wi-Fi pass criterion
  used `iw dev wlan0 link` instead, which worked correctly. Outcome
  unaffected.

### What this proves and doesn’t

Proves:

- ROCKNIX’s fake-suspend primitives (DPMS, governors, core parking,
  input grab, LEDs) all reliably toggle on/off in a tight loop.
- The guest container is **transparent** to host fake-suspend. Layer
  14+ does not need to coordinate the guest with host fake-suspend
  cycles — the guest just rides through.
- No memory or thread leak in fake-suspend over 20 cycles.
- Sway and Wi-Fi are robust to repeated DPMS/governor toggles.

Does not prove:

- Guest-owned fake-suspend (Milestone 18 still ahead).
- Behavior with a real game running.
- Behavior over hours of operation.
- Behavior with a paired BT controller present.
- Real kernel suspend (still disabled on SM8550).
- Behavior under degraded Wi-Fi signal.

### Implication for milestone path

- Milestone 18 (guest owns fake-suspend UX) gets *cheaper*: we now know
  the host’s primitives are solid, so when we move them into the guest
  they should be solid too. Risk is in handoff and watchdog, not in
  the primitives themselves.
- Layer 14 unit shopping list grows: must own its own
  `/etc/resolv.conf` (host clobbers it during normal operation,
  reproduced now).
- Adds confidence to the “guest is transparent to fake-suspend” claim
  we can lean on for Milestones 14–17 — they don’t need to wait for 18.

### Updated feasibility odds

Odds for the parts E1 is evidence about:

```text
Working main-space prototype (display+audio+wifi survive sleep): 90–95%
Thor daily-driver including handheld sleep UX:                   75–85%
```

Unchanged because Tier E is about *resilience* not *capability*; we
still need E2–E5 to move the daily-driver number further.

### Artifacts

- `/storage/e1-suspend-cycle.sh` — reproducible cycle driver
- `/var/log/e1-cycle.log` — ~660 lines of full per-cycle snapshots
- `/var/log/e1-cycle-summary.log` — trimmed pass/fail summary
- `/var/log/e1-cycle-stdout.log` — stdout from the run

---

## Tier E2–E5 + E3 live findings (2026-05-08, lifecycle batch)

Following E1's 20×20 fake-suspend cycle pass, ran the rest of Tier E
on the same Thor session.

### E2 — update / rollback workflow ✅

**E2a: switch to a deliberately broken config.** Built a new toplevel
from `/etc/nixos` with everything from `rev2` plus a `deliberate-fail`
systemd oneshot unit whose `ExecStart` is `/bin/false`. Used:

```sh
nix build .#nixosConfigurations.rocknix-guest.config.system.build.toplevel
nix-env -p /nix/var/nix/profiles/system --set $TL3
ln -sfn .../system-1-link /run/current-system   # seed first time
$TL3/bin/switch-to-configuration test
```

Result:

- Activation completed; `/run/current-system` advanced to gen 2.
- `deliberate-fail.service` ran, exited 1, was marked failed.
- Pre-existing `tz-data.service` ExecStart=`/bin/ln -sf /usr/share/zoneinfo/${TIMEZONE} ...` failed 203/EXEC (empty TIMEZONE) — same noise on every switch; needs `time.timeZone` in guest config.
- `sshd.socket` complained `Address already in use` because the existing rev2 sshd was still listening on port 22 (existing socket is fine; not a real failure).
- **Guest survived.** Hostname intact, shell still responsive, nsenter still works.

**E2b: rollback to gen 1.**

```sh
nix-env -p /nix/var/nix/profiles/system --switch-generation 1
$TL1/bin/switch-to-configuration test
```

Result:

- Profile flipped: `system → system-1-link`.
- `/run/current-system` advanced backwards to gen 1 store path.
- `deliberate-fail.service` symlink **removed** from
  `/etc/systemd/system/multi-user.target.wants/`.
- `systemctl is-failed deliberate-fail.service` → `inactive`.

Clean rollback. The activation script correctly reaps units that
existed only in the broken generation.

**E2c: GC and storage budget.**

```text
before deleting gen 2:    /nix/store = 3861 MB, 2333 dead candidates
after `nix-store --gc`:   /nix/store = 1282 MB
freed:                    2493 MB (2.4 GB)
```

Reachable closure for current `rocknix-guest` = 1.28 GB. Each
additional `nixos-rebuild` generation that diverges meaningfully
costs on the order of hundreds of MB to a couple of GB depending on
how much of the closure changes. **Plan for ~2GB headroom per
retained generation**, plus space for nixpkgs evaluation outputs.

### E5 — audio/BT ownership failure modes ✅ (partial)

Prep: bound `/dev/snd/{controlC0,pcmC0D0p,pcmC0D1p,pcmC0D2c,timer}`
and `/dev/rfkill` into the guest via `mknod` inside guest mount
namespace (host nspawn doesn’t bind these by default).

Wrote `/storage/who-holds-snd.sh` to enumerate /proc/*/fd holders by
device path — busybox `fuser` lacks `-v`.

**E5a: ALSA ownership swap.**

Process:

1. Stop host `pipewire.socket pipewire-pulse.socket pipewire wireplumber pipewire-pulse` → zero holders.
2. Inside guest, `nix build nixpkgs#alsa-utils`, then
   `aplay -D plughw:0,0 -d 30 /dev/zero` (background).
3. Confirm holder is the guest aplay (PID in guest's `pid:[4026532958]` namespace, exe = `/nix/store/...alsa-utils-1.2.14/bin/.aplay-wrapped`).
4. `kill -9` the guest aplay.
5. Holders → zero. ALSA released cleanly.
6. `systemctl start pipewire.socket pipewire-pulse.socket wireplumber` → host pipewire/wireplumber re-acquired `/dev/snd/controlC0`.

**Conclusion:** ownership of ALSA can swap host ↔ guest cleanly via
cgroup-level kill plus systemd socket-activation reclaim. No reboot
needed. PipeWire-pulse was inactive after restart — needs explicit
start in production handoff.

**E5b: Bluetooth ownership swap.**

- Built `nixpkgs#bluez` in guest closure.
- Host `bluetooth.service` was inactive at start (good).
- From guest: `hciconfig hci0 up` succeeded — `hci0` went to
  `UP RUNNING`.
- Guest `bluetoothd -d --noplugin=*` exited quickly because no D-Bus
  available inside guest — expected; full bluez stack needs the
  guest NixOS module to enable `services.dbus`.
- After stopping guest BT activity, `systemctl start bluetooth` on
  host: `bluetooth.service` came up, `hciconfig hci0` showed
  `UP RUNNING PSCAN` (page-scan accepting connections).

**Conclusion:** the kernel HCI socket ownership flips cleanly; the
userspace bluez stack needs a real NixOS environment in the guest
(D-Bus, PolicyKit) which Layer 14 will provide.

**E5c (graceful guest stop), E5d (controller drop), E5e (A2DP
latency)** — deferred. E5c is a minor variation of E5a; E5d needs a
paired BT controller (none available in this session); E5e requires
full PipeWire-in-guest stack which is Layer 14 work.

### E4 — InputPlumber arbitration ✅

Key finding (corrects earlier reading): **`event3` (the real AYN Odin2
Gamepad) is hidden from /dev/input on both host and guest.** Earlier
note said “exclusive-grabbed by host InputPlumber” — actually it’s
removed from the namespace entirely (likely via udev rule or input
filter), with InputPlumber consuming the raw device through a
different path and exposing virtual event7/event8.

Current device map:

```text
event0:  pmic_pwrkey                 (host + guest)
event1:  pmic_resin                  (host + guest)
event2:  qcom-hv-haptics             (host + guest)
event3:  AYN Odin2 Gamepad           (HIDDEN from /dev/input)
event4,5: ft5x06 touch               (host + guest)
event6:  gpio-keys lid               (host + guest)
event7:  InputPlumber Keyboard       (host + guest)
event8:  InputPlumber Mouse          (host + guest)
event9:  Microsoft Xbox Series       (host + guest)
event10: AYN-Odin2 Headset Jack      (host + guest)
event11: AYN-Odin2 DP0 Jack          (host + guest)
```

**E4b verified:** built `nixpkgs#evtest` in guest closure, ran
`evtest --grab /dev/input/event7` from inside guest namespace.

- Holder PID ns confirmed `pid:[4026532958]` (guest).
- Host concurrent readers (sway, seatd, systemd-logind) coexisted
  without fighting.
- Kill released cleanly.

**`/dev/uinput` is NOT bound to the guest.** This means a guest-side
InputPlumber cannot create virtual devices today. Layer 14 unit must
bind `/dev/uinput` if Strategy B (guest owns InputPlumber) is chosen.

**Strategy decision:** **Strategy A** (keep host InputPlumber, guest
reads virtual `event7`/`event8`) is the path of least resistance and
works today with no new bindings. Strategy B is feasible but demands
uinput plus moving rumble/force-feedback chain into the guest, which
is a larger undertaking. Recommend A for first cut, B as a later
optimization if guest needs richer arbitration.

### E3 — cold boot timing ✅ (with caveat)

One clean cold-boot data point captured (the second reboot took ~7
min to reach SSH because **host Tailscale doesn’t auto-start**;
user had to manually re-enable Tailscale to restore connectivity
— separate problem from the boot itself).

Clean boot:

```text
Kernel:        2.438s
Userspace:     8.820s
Total:        11.258s

multi-user.target:    ~2s into userspace
graphical.target:     ~2s into userspace
sshd Server listening: ~3s into userspace
rocknix.target:        7.302s into userspace (= 9.74s wall)
sway active:           9.765s into userspace (= 12.2s wall)
essway active:         9.767s into userspace (= 12.2s wall)
pipewire active:       2.937s into userspace
wireplumber active:    2.951s into userspace
inputplumber active:   3.254s into userspace
bluetooth active:      inactive (was stopped earlier; no auto-restart)
```

Critical chain:

```text
rocknix.target @7.302s
└─rocknix-autostart.service @2.065s +5.236s   <-- biggest single cost
  └─graphical.target @2.062s
    └─sway.service @7.314s +13ms
```

`rocknix-autostart.service` dominates the userspace timeline at 5.2s.
In a thin-host build it should shrink dramatically because most of
what it autostarts moves into the guest.

**Guest cold start:**

```text
systemctl start rocknix-guest.service → nsenter-reachable: 2.1s
```

So host + guest cold-boot to fully usable Nix space: roughly 13.4s
wall today. With thin-host shrink and parallel guest activation,
10–12s should be reachable.

**Caveat:** Tailscale not auto-starting on boot is a separate
operational issue independent of the architecture. Worth noting for
Layer 14 “daily-driver” definition: guest network stack must come up
autonomously after any cold boot, not depend on a human enabling
VPN.

### Side findings during E batch

- DNS bleed reproduces consistently: guest `/etc/resolv.conf` is
  re-clobbered by host’s resolvconf during normal operation. Layer 14
  unit must own its own resolv.conf (already in shopping list, now
  confirmed under load).
- After GC, the cached store path for the previous `nix` binary is
  gone — if you reference store paths by hash you must re-resolve
  through `/run/current-system/sw/bin/nix` after every GC.
- Guest `/run/current-system` is **not seeded on cold start** —
  ExecStartPre or tmpfiles.d in Layer 14 unit must `ln -sfn
  /nix/var/nix/profiles/system /run/current-system`.
- Multiple per-cycle `getcwd: cannot access parent directories`
  warnings remain harmless artifacts of the outer host shell after
  nsenter changes mount namespace; they affect *display only*.
- busybox `fuser` lacks `-v`, busybox `df` lacks `-B`, busybox
  `pgrep` lacks `-c` — prefer `/proc/*/fd` enumeration in tooling
  scripts.
- `nix-env -p` profile management works perfectly even with the
  broad-bind unit; all the rollback machinery exercised cleanly.

### Updated Layer 14 shopping list

Accumulated from E1–E5 + E3:

- Bind: `/dev/snd` (5+ nodes), `/dev/rfkill`, `/dev/uinput`
  (only if guest will own InputPlumber).
- Bind RW for sysfs already validated in earlier sessions.
- Bind: `/dev/tty0`, `/dev/tty1`, `/dev/console` for sway VT seat.
- Drop: host `/usr`, `/lib`, `/etc/profile`, `/etc/resolv.conf`,
  `/etc/ssh/authorized_keys.d/root` binds.
- Add `services.dbus.enable = true` in guest module (bluez and many
  modern services need it).
- Add `time.timeZone = "...";` in guest module to silence and
  succeed `tz-data.service`.
- ExecStartPre seeds `/run/current-system` and `/run/booted-system`
  from `/nix/var/nix/profiles/system`.
- Reclaim contract: if guest `nspawn` exits or hangs > N seconds,
  host re-starts pipewire/bluetooth/sway/essway via prepared
  `/etc/rocknix-reclaim.sh`.
- Pre-stage a guest `nixos-rebuild` runner that doesn’t depend on
  host bind-mounted /etc files (avoid the activation `Device or
  resource busy` traps from earlier session).
- Mandate `tailscaled` (or whatever VPN) is `enable = true` and
  `restartIfChanged = true` in either host or guest config so cold
  boots don’t silently lose VPN.

### Updated feasibility odds

```text
Working main-space prototype (display + audio + wifi + suspend):  92–95%
Thor daily-driver (rollback + cold boot + audio/BT handoff):       78–85%
Thor + Odin 2 Portal releasable architecture:                      62–75%
```

Main delta from previous estimate: rollback works, ALSA ownership
flips cleanly, BT ownership flips cleanly, cold-boot is fast.
Primary remaining unknowns are now operational (Tailscale
auto-restart, full bluez stack in guest, BT controller
reconnect across cycles), not capability.

### Artifacts

- `/storage/e1-suspend-cycle.sh`, `/var/log/e1-cycle*.log` — E1
- `/nix/var/nix/profiles/system-1-link`, `system-2-link` snapshots — E2
- `/etc/nixos/rocknix-guest.nix`, `.gen1`, etc. — E2
- `/storage/machines/rocknix-guest/dev/snd/*`, `/dev/rfkill` mknods — E5
- `/storage/who-holds-snd.sh` — generic /proc/*/fd holder lookup helper
- `/var/log/aplay.log`, `/tmp/bluetoothd.log`, `/tmp/evtest7.log` — inside guest tmpfs (gone after guest restart)

---

## Resume hint

When resuming in a fresh session:

1. Read this document.
2. Confirm device state (build flashed, branch, head).
3. Decide whether to clean up the live experimental guest unit edits or
   keep them for one more validation pass.
4. Start at Milestone 14 (main-space canary), specifically the
   "First validation ladder when device is back online" steps above.
5. After Milestone 14 is observed live, write a proper plan document for
   Milestone 14 under `docs/plans/` and proceed forward-only from there.
