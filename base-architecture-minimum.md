# Base Architecture Minimum: ROCKNIX as Substrate for SM8550

**Scope:** SM8550 only. Other devices (`H700`, `RK3xxx`, `S922X`, `SM6115`,
`SM8250`, `SM8650`) keep the legacy ROCKNIX monolith. The reduction described
here is gated by `[ "${DEVICE}" = "SM8550" ]` everywhere it is wired
(`projects/ROCKNIX/packages/virtual/image/package.mk`,
`projects/ROCKNIX/packages/sysutils/systemd/package.mk`,
`projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk`).

**Constraint:** Host SSH (`packages/network/openssh`) stays on the image
indefinitely. SSH is the only out-of-band lifeline the host owns once the
user-visible UI moves into the Nix guest, so it sets the floor for what the
host must always be able to do.

---

## 1. Architecture Overview (current state)

### 1.1 Two-plane runtime, already in place

The repo has already executed the first half of the reduction. SM8550 boots a
two-plane runtime:

| Plane | Owner | Entry point | Status |
|-------|-------|-------------|--------|
| Main-space (UI, emulators, sway, pipewire, NetworkManager) | NixOS guest fetched from `simonwjackson/rocknix-nix-guest` | `rocknix-main-space.target` → `rocknix-guest.service` → `systemd-nspawn` rooted at `/storage/machines/rocknix-guest` | Default on every SM8550 boot |
| Recovery plane (legacy ROCKNIX UI: essway/sway/EmulationStation/inputplumber/pipewire/etc.) | ROCKNIX host packages | `rocknix.target` (default.target if `/flash/rocknix.no-nspawn` exists or `rocknix.safe=1` is on the kernel cmdline) | Opt-in fallback only |

The `rocknix-recovery-toggle` oneshot
(`projects/ROCKNIX/packages/tools/rocknix-guest-substrate/scripts/rocknix-recovery-toggle`)
runs `Before=sysinit.target` on every boot and writes `default.target` via
`systemctl set-default` based on two OR'd escape hatches: a `/flash` flag file
(sticky, readable from an SD-card reader without booting the device) and a
kernel cmdline token (per-boot only).

### 1.2 Storage & guest Nix substrate

`rocknix-guest-substrate` ships the minimum plumbing to run the persistent
NixOS guest rootfs on a LibreELEC-derived read-only host image:

- `/storage/machines/rocknix-guest/` holds the persistent NixOS rootfs; the
  host never re-writes it from an image update.
- Guest Nix state lives inside that rootfs at
  `/storage/machines/rocknix-guest/nix`. The host root `/nix` bind mount from
  earlier Nix-integration layers is retired; the host resolves guest profiles
  through `${GUEST_ROOT}/nix/...` instead of maintaining its own Nix store.
- `/usr/lib/rocknix-guest-substrate/guest/` ships the pinned
  `rocknix-nix-guest` source tree (SHA256-verified tarball fetched at package
  build time) plus its revision marker.
- `rocknix-guest-promote.service` runs after the guest is up, compares the
  packaged revision against the applied one
  (`/storage/machines/rocknix-guest/etc/rocknix-guest-revision`), runs
  `nix build` *inside the running guest namespace* via `nsenter`, updates the
  selected guest profile via
  `nix-env -p /nix/var/nix/profiles/per-user/root/rocknix-guest-system --set`,
  then restarts the guest one time. `/nix/var/nix/profiles/system` is retired
  as a host-recognized boot authority. This is the on-device update mechanism
  for the main-space.

### 1.3 What's already excised vs. what still ships

`projects/ROCKNIX/packages/tools/rocknix-guest-substrate/tests/guest-substrate-static-checks.sh`
enforces that the host no longer carries:

- Old host CLIs `nixctl`, `nix-doctor`, `nix-layer-activate`
- Host `nix-daemon.service` / `nix-daemon.socket`
- The `modules/` and `profile.d/` Nix integration trees
- Any `NIX_INTEGRATION_SUPPORT`, `NIX_NSPAWN_SUPPORT`, `NIX_DAEMON_SUPPORT`,
  `THIN_HOST` build flags

`systemd-nspawn` itself is stripped from every non-SM8550 image
(`safe_remove ${INSTALL}/usr/bin/systemd-nspawn` in
`projects/ROCKNIX/packages/sysutils/systemd/package.mk`).

What still ships on the host SM8550 image and is **not yet reduced**:

- Full LibreELEC userland declared by
  `projects/ROCKNIX/packages/virtual/image/package.mk`: `PKG_UI` (EmulationStation,
  es-themes, textviewer), `PKG_MULTIMEDIA` (ffmpeg, vlc, mpv, gmu, m8c),
  `PKG_FONTS` (corefonts), `PKG_SOUND` (espeak, libao), `PKG_GRAPHICS`
  (imagemagick), `PKG_SYNC` (synctools).
- The whole emulator metapackage when `EMULATION_DEVICE=yes` (default in
  `distributions/ROCKNIX/options`): `emulators gamesupport` -- pulls in
  hundreds of `*-lr` cores, RetroArch, the duckstation/flycast/etc.
  standalones, BIOS scaffolding.
- The legacy graphical stack: `swaywm-env`, `compositor/sway`, `essway`,
  `pipewire`, `wireplumber`, `bluez`, `inputplumber`, `kodi`*ish*
  mediacenter inheritance (still present in `packages/mediacenter`).
- Network metapackage (`packages/virtual/network/package.mk`): connman, iwd,
  netbase, ethtool, openssh, iw, wireless-regdb, rsync, tailscale, avahi,
  miniupnpc, nss-mdns, speedtest-cli, plus optional samba/openvpn/wireguard/zerotier.

The guest (`rocknix-nix-guest`) is now the canonical owner of the UI, but the
host image still carries a *second* full copy of the runtime that the guest
shadows.

---

## 2. Architectural Minimum Responsibilities of the Host

These are the responsibilities the host **must** retain because (a) they
cannot be delegated into the guest without losing the ability to recover from
a broken guest, and (b) they are prerequisites for the SSH-indefinite
guarantee.

### 2.1 Boot & kernel (immutable)

- Bootloader (`projects/ROCKNIX/devices/SM8550/bootloader`, `qcom-abl`).
- Kernel + SM8550 DTBs + SM8550 patches
  (`projects/ROCKNIX/devices/SM8550/linux`, `…/patches/linux`,
  `…/dts/qcom/*.dts*`).
- Kernel firmware (`kernel-firmware`, the device's
  `filesystem/usr/lib/kernel-overlays/base/lib/firmware/...` tree --
  ath12k WCN7850 Wi-Fi, qcom/sm8550 ADSP, etc.).
- initramfs (`packages/virtual/initramfs`) wired to find `/flash` and
  `/storage`.
- Linux drivers metapackage minus emulation-only entries.

These are not negotiable. The guest runs in the host's kernel and can never
own them.

### 2.2 Init + early plane selection

- `systemd-255` (host-side, with `default-hierarchy=unified` for SM8550 via
  `SYSTEMD_DEFAULT_HIERARCHY` in `projects/ROCKNIX/devices/SM8550/options`).
- `systemd-nspawn` binary + `systemd-nspawn@.service` template (only built
  on SM8550 per `packages/sysutils/systemd/package.mk`).
- `rocknix-recovery-toggle.service` -- the per-boot `default.target` decision
  is host-only by design; the guest cannot select between itself and the
  recovery plane.
- `rocknix-main-space.target` (aliased to `default.target` on normal boot,
  `Requires=multi-user.target`, `Wants=rocknix-guest.service`).
- `rocknix.target` (legacy recovery plane entry, kept indefinitely as
  fallback).

### 2.3 Storage substrate

- `/storage` automount (existing `rocknix-automount.service` in
  `projects/ROCKNIX/packages/rocknix/system.d/`).
- `/flash` mount (read-only image partition; carries `HOW-TO-FALL-BACK.md`
  and the `rocknix.no-nspawn` flag file).
- Guest rootfs Nix state under `/storage/machines/rocknix-guest/nix`; the host
  no longer maintains a root `/nix` bind mount for itself.
- Filesystem tools needed to repair the guest from the host: `e2fsprogs`,
  `dosfstools`, `parted`/`gptfdisk`, `util-linux`, `coreutils`, `bash`,
  `busybox` (already declared by the `image` virtual package).

### 2.4 Network (host-owned, shared with guest)

The guest unit explicitly does **not** use `--private-network`. The host
owns the kernel netns and the guest reuses it. This means:

- The host *must* be the unique owner of physical NIC setup at boot:
  `wireless-regdb`, `iw`, the `linux-firmware` Wi-Fi blobs.
- But Wi-Fi state ownership has migrated: today the guest runs its own
  NetworkManager and binds to wlan0 directly (Tier C finding, called out in
  `rocknix-guest-v2.service` header).
- This is the trickiest boundary in the current design and is why the soak
  harness explicitly probes for `/etc/resolv.conf` clobbers
  (`rocknix-guest-soak`, `check_resolv_owned`). The host must not clobber
  guest-owned net state, but it must be able to bring the link up cold
  before the guest is alive (e.g., to provide SSH on first boot or in a
  guest-failure recovery).
- **Minimum host network responsibility:** carrier-grade link bring-up
  (NIC driver + firmware load + initial wpa\_supplicant/iwd profile from
  `/storage/.config/iwd/*.psk`) sufficient to get SSH reachable when the
  guest is off. Everything beyond that is the guest's job.

### 2.5 SSH (indefinite contract)

Per the user constraint, `packages/network/openssh` must remain in the host
image. The package config already supports this cleanly:

- `--with-keydir=/storage/.cache/ssh` (host keys persist across image updates).
- `PermitRootLogin yes`, `StrictModes no` (the recovery-grade contract).
- `enable_service sshd.service` unconditionally.

The host SSH is **not** a redundancy of guest SSH; it is the lifeline of
last resort that lets a human reach the device when:

- The guest fails to boot (no `rocknix-main-space.target` activation).
- `rocknix-guest-promote.service` failed mid-build, leaving the system
  profile pointed at a missing store path (the script's
  `applied system path is missing; rebuilding` branch is the auto-repair,
  but a hard failure needs human SSH access).
- The user has flipped the recovery flag and the recovery plane itself has
  regressed.

`rocknix-guest-soak`'s `check_host_ssh_responsive` probe is the canonical
"host SSH still works after N hours of guest activity" assertion. That probe
should stay green forever.

### 2.6 Update plumbing

- The ROCKNIX update mechanism (LibreELEC-style "drop a `.tar` in `/storage/.update`,
  reboot to apply") -- handled by `packages/virtual/image` +
  `projects/ROCKNIX/devices/SM8550/bootloader/update.sh` +
  `packages/rocknix/sources/post-update`.
- The `rocknix-guest-substrate` package itself ships pinned guest revisions:
  `PKG_NIX_GUEST_REV` + `PKG_NIX_GUEST_SHA256` in `package.mk`. Image updates
  therefore deliver a new guest pin; `rocknix-guest-promote.service` does the
  on-device application.
- Recovery doc shipped to `/flash/HOW-TO-FALL-BACK.md` -- the contract is that
  this file is readable from any teardown without booting the device.

### 2.7 Recovery plane (kept indefinitely)

The legacy ROCKNIX userland (essway/sway/EmulationStation/inputplumber/pipewire
/bluez/...) is what `rocknix.target` boots when recovery is requested.
**This is the part of the host that the SSH-indefinite constraint does *not*
require but the soak/recovery contract does.** Decisions about how thick to
keep it are the whole subject of §4 below.

---

## 3. Boundaries to Enforce

These are the contracts the static checks already encode plus the ones the
design implies but doesn't yet enforce. They should be promoted to invariants
checked by `guest-substrate-static-checks.sh` (and the runtime smoke) before
each reduction step lands.

### 3.1 Host → Guest leakage (negative space; already enforced)

The guest unit must **not** bind any of:

- `--bind-ro=/usr` — host Mesa/Vulkan ICDs vs. guest /nix store mismatch
  (Vulkan/EGL ICD pollution).
- `--bind-ro=/lib` — same class.
- `--bind-ro=/etc/profile{,.d}` — host PATH (incl. `098-busybox`) clobbers
  guest PATH.
- `--bind-ro=/etc/resolv.conf` — host resolvconf clobbers guest DNS (Tier E1).
- `--bind=/storage` (blanket) — only narrow subdirs may be bound (RO `/storage/roms`,
  RW `/storage/.guest`, configured subdirs of `/storage/.config/<app>`).
- `--bind=/run/0-runtime-dir`, `--bind=/tmp/.X11-unix` — guest runs its own
  compositor/server stack.
- `--bind=/etc/ssh/authorized_keys.d` — guest SSH (if it ever runs) owns
  its own keys.

The static checker iterates a `forbidden` list and the runtime smoke
duplicates it. **Keep this list authoritative.** Every new bind must justify
itself by name in the unit's leading comment and not match the forbidden set.

### 3.2 Guest → Host leakage (positive space; partly enforced)

- Guest must not `ExecStopPost=` into a host reclaim helper. The static check
  explicitly fails on `ExecStopPost=` to prevent regressing this. The reason:
  a half-broken guest must not automatically resurrect the legacy host UI; it
  must fall through to a clean recovery decision the user can see. (The
  `refactor(rocknix-guest-substrate): remove automatic legacy host reclaim` commit
  `8e6b67f076` enforces this.)
- `rocknix-guest-v2.service` must `--register=no` so the guest doesn't
  couple to `machined` on the host. Static-check enforced.
- The guest is bounded by `CPUWeight=100`, `IOWeight=100`, `MemoryMax=6G`.
  This is so a runaway guest still leaves the host CPU and memory budget
  to run SSH. **This is the SSH-indefinite contract's runtime expression
  and must not regress.**

### 3.3 Device gating (architectural firewall)

The reduction is SM8550-only. Three independent gates already exist; all
three should stay:

1. `packages/virtual/image/package.mk`:
   `[ "${DEVICE}" = "SM8550" ] && PKG_DEPENDS_TARGET+=" rocknix-guest-substrate"`
2. `packages/sysutils/systemd/package.mk`:
   `if [ "${DEVICE}" != "SM8550" ]; then safe_remove …systemd-nspawn… fi`
3. `packages/tools/rocknix-guest-substrate/package.mk`'s `post_install` aborts
   with a clear error if `DEVICE != SM8550`.

Defense-in-depth on a single decision. Keep the redundancy.

### 3.4 Ownership of the source of truth

- The host repo owns: SM8550 device tree, kernel patches, bootloader,
  `rocknix-guest-substrate` bootstrap, recovery plane.
- The guest repo (`simonwjackson/rocknix-nix-guest`) owns: NixOS config,
  contract docs (`docs/contracts/layer14-main-space-contract.md`,
  `…/layer14-soak-checklist.md`, `…/HOW-TO-FALL-BACK.md`). The host **copies
  these from the fetched guest tarball at build time** rather than
  duplicating them. Static-check enforced. This is correct: contract docs
  belong with the runtime they describe.

### 3.5 Lifecycle boundary (the promote contract)

`rocknix-guest-promote` is the *only* host-side process allowed to touch
the guest's system profile. Its contract is in
`scripts/rocknix-guest-promote`:

1. Compare `/usr/lib/rocknix-guest-substrate/guest-revision` (host-shipped) to
   `${GUEST_ROOT}/etc/rocknix-guest-revision` (applied marker).
2. If equal AND `${GUEST_ROOT}/etc/rocknix-guest-system-path` still exists
   inside the guest's `/nix/store` → no-op.
3. If marker matches but profile drifted → repair via `nsenter` + `nix-env --set`,
   restart guest.
4. If marker matches but the path is gone → rebuild.
5. Otherwise → stage source under `/storage/.guest/rocknix-nix-guest-packaged`,
   `nix build` via `nsenter` (after waiting up to 60×2s for guest's
   `NetworkManager.service`), `nix-env --set`, write markers, restart guest.

**Invariants to enforce going forward:**

- Promote must never run before the guest is reachable (today: depends on
  guest `NetworkManager` being active inside the guest namespace; the wait
  loop is essential and is static-check enforced).
- Promote must not use `sh -lc` (no login shell — PATH pollution risk;
  static-check enforced).
- Promote must communicate results via a file in shared guest storage
  (`/storage/.guest/rocknix-guest-promote-system-path`), not via stdout
  parsing — static-check enforced.

---

## 4. Reduction Sequence (validate-able)

The goal: get the host image to "kernel + storage + network bring-up + SSH +
nspawn + recovery plane + update plumbing." Anything else moves into the
guest or out of the image entirely. The constraint is each step must remain
demonstrably bootable with both a working main-space and a working recovery
plane.

The order below is staged so each step adds at most one new failure mode and
each step's "done" condition is a smoke/soak the repo can already run.

### Step 0 — Lock the current contracts (no code change)

**Why first:** before any subtractive change, freeze the contract so
regressions are detectable.

- Add `guest-substrate-static-checks.sh` to a CI gate (it's already
  the canonical static check; just make it required).
- Run `guest-substrate-runtime-smoke.sh` with `ROCKNIX_GUEST_LIVE_SMOKE=1`
  on a Thor and capture baseline: `default.target`, guest rootfs `/nix`,
  guest unit active, recovery toggle service installed.
- Run `rocknix-guest-soak --hours 24` and bank a green run as the
  "everything's still wired correctly" baseline.

**Validate-able exit criterion:** all three pass on a stock build of the
current `custom` branch.

### Step 1 — Strip emulation from the host image

**Target:** the host image no longer carries any emulator binaries or BIOS
scaffolding; the guest carries them.

- Flip `EMULATION_DEVICE=no` for SM8550 (set in
  `projects/ROCKNIX/devices/SM8550/options`, currently relying on the
  distribution default `yes`).
- Confirm `packages/virtual/image/package.mk`'s
  `[ "${EMULATION_DEVICE}" = "yes" ] && PKG_DEPENDS_TARGET+=" emulators gamesupport"`
  no longer fires.
- Cross-check that the existing
  `[ "${BASE_ONLY}" = "true" ]` path is *not* what we want — `BASE_ONLY`
  also strips fonts, multimedia, UI tools. We want a middle position:
  emulators gone, host UI/recovery still present.

**Why it's safe:** the guest already owns the emulator stack. Today the
host image carries the same binaries again, shadowed by the guest's
versions. Removing the host-side copy saves ~hundreds of MB of image
without changing any runtime path that's currently active.

**Validate-able exit:**
- Image build succeeds with the same `DEVICE=SM8550` invocation.
- `guest-substrate-static-checks.sh` passes (no surface touched).
- A Thor boot: recovery plane reachable via flag-file, but EmulationStation
  inside the recovery plane will be missing — this is acceptable **if and
  only if** the recovery plane's job is redefined to "shell + SSH + ability
  to fix the guest," not "play games." That redefinition is Step 2.

### Step 2 — Redefine the recovery plane: shell + SSH only

**Target:** `rocknix.target` boots a minimal recovery environment, not the
full essway/sway/EmulationStation UI.

- Replace the `rocknix.target` chain so it no longer `Wants=` essway, sway,
  pipewire, wireplumber, inputplumber, bluez, etc.
- Keep `rocknix-automount.service`, `sshd.service`, the storage mounts,
  `network-base.service`, NetworkManager-or-equivalent for the host.
- Drop the UI metapackage (`PKG_UI=emulationstation es-themes textviewer`)
  from `packages/virtual/image/package.mk` for SM8550.
- Drop `WINDOWMANAGER=swaywm-env` for SM8550 (override in
  `projects/ROCKNIX/devices/SM8550/options`) — the guest brings its own
  compositor; the host has no use for one.
- Drop `PIPEWIRE_SUPPORT` for SM8550 — same reasoning.
- Keep `BLUETOOTH_SUPPORT=yes` only if recovery needs Bluetooth (probably
  not — controllers and audio are guest concerns).

**Why this is the SSH-anchored step:** once Step 2 lands, the host has
nothing UI-shaped left. SSH becomes literally the only way to reach the
host out-of-band. This is consistent with the brief.

**Validate-able exit:**
- `guest-substrate-runtime-smoke.sh` live mode: `systemctl get-default`
  is `rocknix-main-space.target` (or `multi-user.target` if flagged), both
  unit files exist.
- `rocknix-guest-soak --hours 24`: zero alarms, including
  `check_host_ssh_responsive` and `check_resolv_owned`.
- Manual recovery test: drop `/flash/rocknix.no-nspawn`, reboot, confirm
  the host comes up with sshd listening and `/storage` mounted, but no
  graphical session. (This will require a new test asserting "boot to
  recovery plane → SSH works → can edit/remove the flag file."
  Add it as `guest-substrate-recovery-smoke.sh`.)

### Step 3 — Excise duplicate userland packages

**Target:** the host image no longer carries multi-hundred-MB userland that
exists only because the recovery plane used to be the main plane.

Concrete candidates from `packages/virtual/image/package.mk`:

- `PKG_UI="emulationstation es-themes textviewer"` — drop for SM8550.
- `PKG_UI_TOOLS="fbgrab grim"` — drop for SM8550 (the guest has these).
- `PKG_MULTIMEDIA="ffmpeg vlc mpv gmu m8c"` — drop for SM8550.
- `PKG_SYNC="synctools"` — drop for SM8550 (sync is a guest concern).
- `PKG_GRAPHICS="imagemagick"` — drop for SM8550.
- `PKG_SOUND="espeak libao"` — drop for SM8550.

Each of these should become a per-device gate, not a global flip, so the
other devices remain unaffected (the brief is SM8550-only).

**Validate-able exit:**
- Image size delta: measure before/after; expect substantial reduction.
- All Step-2 smokes still green.
- Add a new static check: a denylist of packages that must not appear in
  the `SM8550` final image manifest. (The build already emits package
  manifests under `target/`.)

### Step 4 — Tighten the host network surface

**Target:** the host owns only what's required for cold link-up + SSH; the
guest owns everything else.

- Today `packages/virtual/network/package.mk` pulls
  `connman iwd netbase ethtool openssh iw wireless-regdb rsync tailscale
  avahi miniupnpc nss-mdns speedtest-cli`. For SM8550 the guest owns
  NetworkManager+wpa_supplicant and the user-facing networking — so the
  host should keep `iwd` (or `wpa_supplicant`) only for early bring-up,
  `iw`, `wireless-regdb`, `openssh`, `netbase`.
- `tailscale`, `avahi`, `nss-mdns`, `miniupnpc`, `speedtest-cli`, `rsync`,
  `connman` are user-experience concerns — they belong in the guest.

This step is the most subtle because of the shared netns boundary
(see §2.4). Concretely:

  - The guest's NetworkManager binds wlan0 directly today; the host can run
    its own minimal supplicant *before* the guest is up but must hand off
    cleanly. The simplest contract: host runs iwd against
    `/storage/.config/iwd/*.psk` until the guest's NetworkManager activates;
    once guest NM is active, host iwd should be `Conflicts=`-gated off, or
    configured to manage zero interfaces.
  - The soak harness's `check_resolv_owned` already detects bleed; extend
    it with a `check_link_owner` that asserts only one of (host iwd, guest
    NM) is managing wlan0 at any time.

**Validate-able exit:**
- Soak harness extended and passing.
- Cold-boot test: power on with guest absent (force the flag file),
  observe host comes online on Wi-Fi within N seconds, SSH reachable.
- Warm-boot test: normal boot, observe guest takes over wlan0, host
  supplicant is idle, host SSH still works.

### Step 5 — Excise the legacy host UI packages entirely

**Target:** the source tree no longer compiles the legacy host UI for
SM8550. The packages remain in the repo (other devices still need them),
but SM8550's build manifest doesn't include them.

- `essway`, `compositor/sway`, `weston`, `swaywm-env`, EmulationStation
  for SM8550 only.
- The mediacenter (`packages/mediacenter/kodi*`) for SM8550 only.
- The legacy `rocknix.target` recovery plane should still exist but its
  `[Install]` and `Wants=` graph point at a minimal set
  (debug-shell, sshd, automount, machine-id, userconfig).

This is the step where the host image becomes "a kernel, a systemd, a
container engine, SSH, and an updater." Nothing more.

**Validate-able exit:**
- Image size delta vs. Step 3 baseline.
- Manifest denylist now includes the UI packages.
- A new test: `guest-substrate-recovery-smoke.sh` boots into recovery,
  confirms `systemctl list-units --type=service --state=running`
  contains *only* the minimal recovery set (sshd, automount, journald,
  systemd-resolved, systemd-timesyncd, the recovery toggle, the guest
  promote if guest is up, nothing else).

### Step 6 — Promote the host to a true "container substrate"

**Target:** make explicit that the host is a container substrate, not a
gaming OS that happens to host a container. This is mostly documentation,
naming, and CI gates — but it's the step that lets the architecture
stabilize.

- Rename `rocknix-guest-substrate` to something neutral if `rocknix-guest-substrate` is
  still misleading (it's the host-side bootstrap for *any* nspawn-rooted
  guest, not just Nix). Keep the package surface byte-stable as the
  static check enforces.
- Add a documented "container guest contract" alongside the existing
  `layer14-main-space-contract.md`: any nspawn guest the host hosts
  must declare its bind set, its resource budget, and its recovery
  story. Today there's exactly one guest; the contract is implicit.
- Codify the inverse contract: the host promises (a) the guest rootfs at
  `/storage/machines/rocknix-guest` contains its own `/nix` store/profile tree,
  (b) kernel cmdline carries `systemd.unified_cgroup_hierarchy=1` on SM8550,
  (c) `systemd-nspawn` binary + service template are available, and (d)
  `nsenter` is available for promote. The host no longer promises a root
  `/nix` mount for itself.
- Add a runtime invariant: a single "host services to keep alive" unit
  list, validated by a smoke. Today the soak checks essway, but that's
  a Step-2 casualty. The replacement is "sshd, journald, recovery
  toggle, guest promote, guest v2, automount, the system mounts."

**Validate-able exit:**
- `guest-substrate-static-checks.sh` extended with a positive allowlist
  of host services for SM8550.
- The 24h soak is updated to drop `check_host_essway_alive` (now
  obsolete) and gain `check_host_minimal_set_alive`.

---

## 5. Compliance Check Against Architectural Principles

| Principle | Status today | Notes |
|-----------|--------------|-------|
| Single Responsibility (per package) | Strong | `rocknix-guest-substrate` is purely the bootstrap; the guest tree is fetched, not duplicated. |
| Open/Closed (extension via guest, not host churn) | Strong | New main-space behavior lands as guest revision bumps (commits like `5af42b75e4 feat(rocknix-guest-substrate): auto-promote packaged guest revisions`), not host code edits. |
| Liskov-style substitutability of planes | Adequate | `multi-user.target` recovery and `rocknix-main-space.target` are interchangeable defaults; the toggle is purely declarative. |
| Interface Segregation (host ↔ guest) | Improving | The static checker enforces the negative interface (no leaks). The positive interface (what *is* exposed) is implicit in the bind list and the netns sharing; should be promoted to a typed contract doc. |
| Dependency Inversion (high-level OS depends on abstractions) | Weak today, strong after Step 6 | Today the host ships the same UI twice. After Step 5 the host depends only on systemd-nspawn + a guest revision pin, never on the guest's contents. |
| No circular dependencies | OK | Host fetches guest tarball at build time; guest never imports from host except at runtime via narrow binds. |
| Defense in depth on device gating | Strong | Three independent SM8550 gates (§3.3). |
| Recovery decoupling | Strong | `/flash/rocknix.no-nspawn` is readable from a card reader; `HOW-TO-FALL-BACK.md` is shipped to `/flash`; kernel cmdline override exists. |
| Lifecycle boundary on guest profile | Strong | `rocknix-guest-promote` writes only the canonical `rocknix-guest-system` profile; drift repair branches are tested for via the static checker. |

---

## 6. Risk Analysis

### 6.1 Carried by the current design

- **Shared netns is a leaky abstraction.** The host and guest share wlan0
  by design (faster path, no NAT, no double-encryption). The price is
  that any host service that touches networking can poison the guest
  (and vice versa). The static checker forbids `/etc/resolv.conf` binds;
  the soak harness samples for clobbers. This works today but it's a
  surface that needs explicit ownership — see Step 4.
- **`/storage/machines/rocknix-guest` is never reset by an image update.**
  A divergent guest profile can persist across updates. The `rocknix-guest-promote`
  drift-repair branch is the safety valve, but a corrupted `/nix/store`
  needs a manual `rocknix.no-nspawn` boot + repair. Document this in
  `HOW-TO-FALL-BACK.md` if it isn't already.
- **`MemoryMax=6G` is hardcoded.** Fine for the Thor profile, but if
  SM8550 ever expands to a device with less RAM the host SSH guarantee
  silently breaks. This should be parameterized by device.
- **The guest builds at runtime via `nsenter` from the host.** If the
  host's `nsenter` is incompatible with the guest's `systemd-nspawn`
  namespace ABI in a future systemd version, promote will silently fail.
  Worth a long-term watch.

### 6.2 Introduced by the reduction sequence

- **Step 2 (kill host UI):** if a user is mid-recovery with no console,
  no display, SSH is the only fallback. If SSH key provisioning has any
  rough edge (e.g., the `/storage/.cache/ssh` directory hasn't been
  populated on a fresh image), the device is bricked. **Mitigation:**
  ship a known authorized_keys via `LOCAL_SSH_KEYS_FILE` build-time
  option (already supported by `packages/rocknix/package.mk`) and
  document the recovery procedure for first-boot SSH explicitly.
- **Step 4 (network surface shrink):** the hand-off contract between
  host iwd and guest NetworkManager on wlan0 is the highest-risk
  technical move. **Mitigation:** introduce the link-owner soak check
  before flipping the package set.
- **Step 5 (excise UI packages):** the legacy recovery plane disappears.
  If the guest is broken AND the recovery flag was never set, the user
  has to either edit `/flash` over USB or use SSH. **Mitigation:** the
  recovery toggle's flag-file design already addresses this; keep
  `HOW-TO-FALL-BACK.md` on `/flash` as the canonical doc.

---

## 7. Recommendations (in order)

1. **Now:** lock the contract. Make `guest-substrate-static-checks.sh` a
   required CI gate (it's a single self-contained script with no
   external deps). Bank a 24h soak baseline. Tag the commit.
2. **Step-1 first because it's cheapest and safest:** flip
   `EMULATION_DEVICE=no` for SM8550 only. Image size drops dramatically;
   no runtime path changes for users (the guest already had them).
3. **Before Step 2, write `guest-substrate-recovery-smoke.sh`.** It must
   assert (a) booting with `/flash/rocknix.no-nspawn` reaches a state
   where sshd is listening, (b) `/storage` is mounted, (c) the flag
   file can be removed, (d) a subsequent reboot returns to the
   guest. This is the test that gives the SSH-indefinite contract teeth.
4. **Step 4 (network surface) requires a design doc, not just a code
   change.** Write the host↔guest network ownership contract
   explicitly before changing packages: who owns the link before the
   guest is up, what does host-side `iwd`/`wpa_supplicant` do once the
   guest's NM is active, who writes `/etc/resolv.conf`, what's the
   handoff order.
5. **Promote `rocknix-guest-substrate` from "package" to "subsystem" in the
   documentation hierarchy.** It is the SM8550 host's identity. A
   `documentation/ARCHITECTURE.md` at repo root, calling out the
   two-plane model and the SSH-indefinite contract, would prevent
   confusion for future contributors.
6. **Make device-specific overrides authoritative.** Today the SM8550
   reduction relies on `if [ "${DEVICE}" = "SM8550" ]` scattered across
   three packages. Consider centralizing the SM8550 "thin host"
   reduction in `projects/ROCKNIX/devices/SM8550/options` with a single
   flag like `THIN_HOST=yes`, then derive package gates from it. The
   static checker currently forbids `THIN_HOST` (commit `0b0ef32485`
   "remove THIN_HOST compatibility gate") — but it forbids it because
   it's *no longer a build-time gate*. If reintroduced as a forward
   gate for Steps 1–5, the static check should be updated accordingly.
7. **Never drop SSH from the SM8550 image.** Add an explicit static
   check: `grep -q 'openssh' projects/ROCKNIX/packages/virtual/network/package.mk`
   and assert that the SM8550 build manifest contains `openssh`.

---

## 8. Architectural Smells Flagged

- **Inappropriate intimacy** (medium): the host's `rocknix-guest-promote`
  reaches *inside* the running guest via `nsenter` to invoke `nix build`.
  This is pragmatic — there's no realistic way to build a Nix closure
  for the guest from outside it without duplicating the toolchain — but
  it does couple the host to the guest's PATH and Nix-tooling layout
  (`/run/current-system/sw/bin/nix-env`, etc.). The static checker
  enforces "no login shell, no sh -lc" to keep this surface narrow.
  Tolerable.
- **Leaky abstraction** (medium): shared netns. Documented above.
- **Inconsistent pattern** (low): the legacy ROCKNIX userland's
  service graph is recovery-only while the guest unit
  is `WantedBy=rocknix-main-space.target`. Two parallel target trees
  with overlapping membership. Fine for now but auditing the wants
  graph as Step 5 lands will be necessary.
- **Missing boundary documentation** (medium): the host↔guest network
  contract is implicit. Recommendation 4 addresses this.

---

## Appendix A — Files of Interest

- `projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk` — pinned
  guest fetch, install plan, service enablement, SM8550 gate.
- `projects/ROCKNIX/packages/tools/rocknix-guest-substrate/system.d/` — every
  host-owned unit involved in the two-plane runtime.
- `projects/ROCKNIX/packages/tools/rocknix-guest-substrate/scripts/` —
  `rocknix-guest-prep` (per-boot guest rootfs sanity + system-profile
  relink), `rocknix-guest-promote` (revision-driven on-device update),
  `rocknix-guest-udev-stage` (InputPlumber/seatd scrub),
  `rocknix-recovery-toggle` (per-boot default.target picker),
  `rocknix-guest-soak` (24h invariant sampler).
- `projects/ROCKNIX/packages/tools/rocknix-guest-substrate/tests/` — static
  checks + runtime smoke; both are the architectural contract in
  executable form.
- `projects/ROCKNIX/packages/virtual/image/package.mk` — the
  global package manifest; the `[ "${DEVICE}" = "SM8550" ]` line is
  where the substrate identity is currently expressed.
- `projects/ROCKNIX/packages/sysutils/systemd/package.mk` —
  `systemd-nspawn` stripping for non-SM8550 (the other half of the
  device gate).
- `projects/ROCKNIX/devices/SM8550/options` — kernel cmdline (incl.
  `systemd.unified_cgroup_hierarchy=1`), bootloader, kernel target.
- `packages/network/openssh/package.mk` — the SSH-indefinite anchor.
- `distributions/ROCKNIX/options` — the distribution-wide defaults
  (`EMULATION_DEVICE`, `CONTAINER_SUPPORT`, etc.) that SM8550 will
  need to override.
- `projects/ROCKNIX/packages/rocknix/system.d/rocknix.target` — the
  recovery-plane entry point that needs to shrink in Steps 2 and 5.
