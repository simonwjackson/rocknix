# SM8550 ROCKNIX Base Scout

Goal: bare-minimum ROCKNIX host needed when the **NixOS guest is the primary
UX** and **host SSH stays indefinitely**. Below: per-category evidence
(`MUST-KEEP` vs `CANDIDATE-REMOVE`) with file/package references.

All paths are relative to `/home/simonwjackson/code/sandbox/rocknix`.

---

## 0. Entry Points / Wiring Overview

- Device options: `projects/ROCKNIX/devices/SM8550/options`
  - `BOOTLOADER="qcom-abl"`, `KERNEL_TARGET="Image"`, kernel cmdline,
    `ADDITIONAL_PACKAGES="gamepadcalibration screen-switch rocknix-abl inputplumber"`,
    `WINDOWMANAGER="swaywm-env"`, `DISPLAYSERVER="wl"`,
    `SYSTEMD_DEFAULT_HIERARCHY="unified"`.
- Distro defaults: `distributions/ROCKNIX/options` (PIPEWIRE, BLUETOOTH,
  AVAHI, NFS, SAMBA_SERVER, SFTP, SIMPLE_HTTP, ZEROTIER, WIREGUARD,
  UDEVIL, NTFS3G, EXFAT, REMOTE_SUPPORT, EMULATION_DEVICE, JOYSTICK,
  HTOP/BTOP, etc).
- Project options: `projects/ROCKNIX/options`
  (`CLEAN_OS_BASE="emulators system-utils modules quirks autostart rocknix kernel-firmware"`).
- Image meta: `packages/virtual/image/package.mk` (pulls `linux`,
  `linux-drivers`, `linux-firmware`, `${BOOTLOADER}`, `busybox`,
  `util-linux`, `corefonts`, `network`, `misc-packages`, `debug`,
  `exfatprogs`, plus optional `displayserver`, `pipewire`, `udevil`,
  `remote`, `mediacenter`).
- Network meta: `packages/virtual/network/package.mk`
  (`connman netbase ethtool openssh iw wireless-regdb nss ipset`
  + bluez/wireguard/wsdd/etc. via flags).
- Boot target wiring: `projects/ROCKNIX/packages/rocknix/package.mk`
  `post_install()` sets `default.target -> rocknix.target` BUT
  `nix-integration` overrides it to `rocknix-graphical.target`
  (`projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-graphical.target`)
  via `Alias=default.target` and the per-boot
  `rocknix-recovery-toggle.service` selects normal vs recovery target.

---

## 1. Boot / Bootloader

| Path / Package | Role | Status |
|---|---|---|
| `projects/ROCKNIX/packages/tools/qcom-abl/package.mk` | virtual meta for Qcom Android boot loader image | **MUST-KEEP** — boot path |
| `projects/ROCKNIX/packages/tools/rocknix-abl/package.mk` (PKG `rocknix-abl-1.0.3`) | ships `abl_signed-SM8550.elf`, `flash_abl.sh`; explicitly listed in `ADDITIONAL_PACKAGES` | **MUST-KEEP** |
| `projects/ROCKNIX/devices/SM8550/bootloader/update.sh` | flash-time bootloader updater; calls `updateabl` | **MUST-KEEP** |
| `projects/ROCKNIX/packages/rocknix/sources/scripts/updateabl` | runtime ABL updater | **MUST-KEEP** |
| `packages/tools/mkbootimg/{mkimage,rkhelper,release}` | Qcom boot image build glue | **MUST-KEEP** (Image+DTB packaging) |
| `packages/tools/u-boot*`, `packages/tools/grub`, `packages/tools/syslinux`, `packages/tools/rpi-eeprom`, `packages/tools/atf`, `packages/tools/rkbin`, `packages/tools/exynos-boot-fip`, `packages/tools/amlogic-boot-fip`, `packages/tools/bcm2835-bootloader`, `packages/tools/crust` | other-platform bootloaders | **CANDIDATE-REMOVE** (not pulled for SM8550 since `BOOTLOADER=qcom-abl`, but unused source folders can be dropped) |
| Recovery readme drop: `nix-integration` `post_install` copies `HOW-TO-FALL-BACK.md` to `/flash/` | recovery docs | **MUST-KEEP** |

---

## 2. Kernel / Device Tree / Firmware

| Path | Role | Status |
|---|---|---|
| `packages/linux/package.mk` (+ `patches/`, `sysctl.d/`, `udev.d/`) | mainline kernel build | **MUST-KEEP** |
| `projects/ROCKNIX/devices/SM8550/linux/linux.aarch64.conf` | SM8550 kernel config (8500+ lines) | **MUST-KEEP** |
| `projects/ROCKNIX/devices/SM8550/linux/dts/qcom/*.dts*` (Ayaneo Pocket variants, Ayn Odin2 / Thor / RP6) | device trees | **MUST-KEEP** (must keep at least the actively shipped targets; can prune unused board DTS once UX is finalized) |
| `projects/ROCKNIX/devices/SM8550/patches/linux/*` (~45 patches) | required kernel patches (display panels, audio codec aw88166, rsinput, qcom-abl boot quirks, IFPC, etc.) | **MUST-KEEP** |
| `packages/linux-firmware/kernel-firmware/package.mk` + `projects/ROCKNIX/devices/SM8550/config/kernel-firmware.dat` | firmware harvest list (ath12k WCN7850, qcom sm8550) | **MUST-KEEP** |
| `projects/ROCKNIX/devices/SM8550/filesystem/usr/lib/kernel-overlays/base/lib/firmware/{qcom/sm8550/*, ath12k/WCN7850/*}` | device-tuned firmware blobs (ADSP/CDSP/VPU/topology) | **MUST-KEEP** (per-OEM subdirs ayaneo/ayn/...; can prune to actually-supported SKUs later) |
| `projects/ROCKNIX/devices/SM8550/filesystem/usr/lib/udev/hwdb.d/10-ayaneo.hwdb` | device hwdb | **MUST-KEEP** |
| `packages/linux-firmware/firmware-imx`, `firmware-dragonboard`, `firmware-rpi`, `iwlwifi-firmware`, `brcmfmac*` | non-SM8550 firmware bundles | **CANDIDATE-REMOVE** (not selected; sources hygiene only) |
| `packages/linux-drivers/tm16xx`, etc. | unused on SM8550 (`ADDITIONAL_DRIVERS=""`) | **CANDIDATE-REMOVE** |

---

## 3. Init / systemd / Autostart

Must-keep (PID 1, basic plumbing):

| Path | Why |
|---|---|
| `packages/sysutils/systemd/package.mk` + `system.d/{cpufreq,debugconfig,envconfig,flash.mount.d,getty@tty0,machine-id,network-base,storage.mount.d,systemd-timesyncd-setup,systemd-timesyncd,usercache,userconfig}.service` | PID 1, mounts, time sync, login tty (host SSH/serial console), persistent ids |
| `packages/sysutils/busybox`, `util-linux`, `kmod`, `dbus`, `libcap`, `libidn2`, `entropy`, `wait-time-sync` | core userland that systemd depends on |
| `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-graphical.target` | new default.target (`Alias=default.target`); `Wants=rocknix-guest-v2.service` |
| `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service` | guest nspawn launcher |
| `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-recovery-toggle.service` + `scripts/rocknix-recovery-toggle` | per-boot default.target chooser; honours `/flash/rocknix.no-nspawn` + `rocknix.safe=1` cmdline |
| `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-promote.service` + `scripts/rocknix-guest-promote` | atomic guest revision promotion |
| `projects/ROCKNIX/packages/tools/nix-integration/system.d/nix.mount` + `nix-storage-setup.service` | `/storage/.nix-root` bind to `/nix` |
| `projects/ROCKNIX/packages/rocknix/system.d/rocknix.target` | **recovery** target alias (Wants `multi-user.target graphical.target`); used by `rocknix-recovery-toggle` fallback |
| `projects/ROCKNIX/packages/rocknix/system.d/rocknix-automount.service` | mounts /storage, /flash; `Wants=rocknix-graphical.target`-adjacent |

Candidate-remove (legacy host UX path; not Wanted by `rocknix-graphical.target` per nix-integration design):

| Path | Notes |
|---|---|
| `projects/ROCKNIX/packages/rocknix/system.d/bluetooth-agent.service`, `hdmi-hotplug.{path,service}`, `rocknix-memory-manager.service`, `rocknix-report-stats.{service,timer}`, `save-sysconfig.service` | currently enabled by `rocknix/package.mk`; only needed if recovery plane wants them. Recovery target still pulls them. **Keep `rocknix.target` + memory-manager** as recovery hygiene; the report-stats and bluetooth-agent are CANDIDATE-REMOVE if not used during recovery. |
| `projects/ROCKNIX/packages/rocknix/autostart/{006-display,008-perfmode,009-sleepmode,010-uimode,050-audio,055-hdmi-check,081-usbgadget,099-networkservices}` | runs only when `rocknix-autostart.service` -> `rocknix.target` is current default. With guest as default these never fire. **CANDIDATE-REMOVE** for steady-state SM8550 builds (keep `001-setup`, `003-upgrade`, `007-rootpw` for recovery) |
| `projects/ROCKNIX/packages/sysutils/autostart/{package.mk,sources/autostart,system.d/rocknix-autostart.service}` | the legacy "boot the games UI" controller. Still WantedBy `rocknix.target` for recovery, so cannot be deleted, just bypassed when default.target is `rocknix-graphical.target`. **MUST-KEEP for recovery only** |
| `projects/ROCKNIX/packages/sysutils/system-utils/system.d/{batteryledstatus,fancontrol,headphones,input,video}.service` (`WantedBy=multi-user.target`) | hardware hooks; the guest may handle these. **MUST-KEEP** for now; profile later for redundancy with guest. |

---

## 4. Storage / Update

| Path / Package | Role | Status |
|---|---|---|
| `packages/sysutils/util-linux`, `e2fsprogs`, `exfatprogs`, `dosfstools`, `parted`, `gptfdisk`, `fuse`, `fuse3`, `squashfs-tools`, `squashfuse` | mount/format/loopback; squashfs is /usr root | **MUST-KEEP** |
| `packages/sysutils/btrfs-progs`, `ntfs-3g_ntfsprogs` (NTFS3G=yes) | extended FS support (used by /storage/roms etc.) | **MUST-KEEP** while keeping rom storage as today |
| `packages/sysutils/systemd/system.d/{flash.mount.d,storage.mount.d}` | mounts `/flash` (ro) and `/storage` | **MUST-KEEP** |
| `projects/ROCKNIX/packages/rocknix/sources/post-update`, `sources/scripts/rocknix-update`, `installtointernal`, `factoryreset` | update flow + recovery installers | **MUST-KEEP** |
| `projects/ROCKNIX/packages/tools/nix-integration/system.d/nix.mount` + `nix-storage-setup.service` | persistent Nix store at `/storage/.nix-root -> /nix` | **MUST-KEEP** |
| `packages/sysutils/udevil` (UDEVIL=yes) | external drive automount | **CANDIDATE-REMOVE** (guest can run its own; redundant on host if guest owns the UX). But cheap to keep for SD-swapping recovery. |
| `packages/sysutils/{nvtop,htop,btop,lsof,file,grep,sleep,i2c-tools,libiio,powerstate,drm_tool}` | debug ergonomics | **CANDIDATE-REMOVE** for size, **MUST-KEEP** at least one of htop/btop + drm_tool for host triage with SSH |

---

## 5. SSH / Network (HOST SSH KEPT INDEFINITELY)

Must-keep:

| Path | Why |
|---|---|
| `packages/network/openssh/package.mk` (+ overlay `projects/ROCKNIX/packages/network/openssh/system.d/sshd.service`, `daemons/001-ssh`) | host-side SSH listener; keys pinned at `/storage/.cache/ssh` via `--with-keydir` |
| `packages/network/openssh/system.d/sshd.service` | systemd unit |
| `projects/ROCKNIX/packages/rocknix/package.mk` `LOCAL_SSH_KEYS_FILE` injection -> `/usr/config/ssh/authorized_keys` | initial key seeding |
| `projects/ROCKNIX/packages/network/connman/{package.mk,system.d,scripts}` | network manager (DEFAULT path; guest currently shares netns, host owns wlan0 per Layer 14 contract comment) |
| `packages/network/netbase`, `nss`, `nss-mdns`, `iw`, `wireless-regdb`, `ipset`, `ethtool`, `iptables`, `libnl`, `libndp`, `libmnl`, `libnftnl` | base networking userland |
| `projects/ROCKNIX/packages/network/iwd` | wpa supplicant alt, used by connman | keep if installed in image |
| `packages/network/avahi` (AVAHI_DAEMON=yes) | mDNS so host is reachable as `rocknix.local` over ssh | **MUST-KEEP** |

Candidate-remove / keep-optional:

| Path | Notes |
|---|---|
| `packages/network/networkmanager` (`projects/ROCKNIX/packages/network/networkmanager`) | the **guest** uses NetworkManager (Layer 14 contract). On the host this can be `CANDIDATE-REMOVE` if connman is the host's network plane (current setup). Confirm before removal. |
| `packages/network/samba`, `wsdd2` (`SAMBA_SERVER=yes`) | SMB share of /storage/roms; UX choice; **CANDIDATE-REMOVE** for slim base (guest can run its own samba), **MUST-KEEP** if existing user behaviour matters |
| `packages/network/nfs-utils`, `rpcbind`, `libtirpc` (NFS_SUPPORT=yes) | NFS client; **CANDIDATE-REMOVE** for slim base |
| `packages/network/bluez`, `projects/ROCKNIX/packages/network/bluez`, `packages/audio/ldacBT`, `libfreeaptx` | host-side bluetooth; the guest can run its own bluez via `--bind=/dev/rfkill`. **CANDIDATE-REMOVE** from host if you accept guest-only BT, otherwise keep. |
| `packages/network/wireguard-tools`, `zerotier-one`, `openvpn`, `tailscale`, `syncthing`, `rclone`, `simple-http-server`, `speedtest-cli`, `rsync`, `cifs-utils`, `fping` | extra net tools — **CANDIDATE-REMOVE** for host slimming; reintroduce inside guest. (`ZEROTIER_SUPPORT=yes` and `WIREGUARD_SUPPORT=yes` in distro options.) |
| `packages/network/openvpn`, `samba` server, `wsdd2` | gated by options; flip off for slim base |

---

## 6. nspawn / nix-integration (THE PRODUCT)

All under `projects/ROCKNIX/packages/tools/nix-integration/`:

- `package.mk` — SM8550-only guard; pins
  `PKG_NIX_GUEST_REV=5f1a19c3...` from `github.com/simonwjackson/rocknix-nix-guest`,
  installs to `/usr/lib/nix-integration/guest/`, enables 5 services.
- `system.d/nix-storage-setup.service` — prepares `/storage/.nix-root`.
- `system.d/nix.mount` — bind `/storage/.nix-root` -> `/nix`.
- `system.d/rocknix-graphical.target` — `Alias=default.target`,
  `Wants=rocknix-guest-v2.service`, `Requires=multi-user.target
  rocknix-automount.service nix.mount`.
- `system.d/rocknix-guest-v2.service` — the `systemd-nspawn` invocation.
  Critical contract notes (excerpted in file header): drops broad
  `/usr`, `/lib`, `/etc/profile`, `/etc/resolv.conf`, `/run/0-runtime-dir`,
  `/tmp/.X11-unix`, `/etc/ssh/authorized_keys.d`, blanket `/storage` binds.
  Uses `--register=no`, shared host netns,
  `SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1`, CPU/IO/Memory caps 100/100/6G,
  binds `/dev/snd`, `/dev/rfkill`, `/dev/dri/card0`, `renderD128`,
  `/dev/input`, `/dev/tty0`, `/dev/tty1`, sysfs nodes for backlight/leds/devfreq/cpufreq,
  scrubbed `/run/udev`, narrow `/storage/.{config/Cemu,config/MangoHud,local,guest}`, RO `/storage/roms`.
- `system.d/rocknix-guest-promote.service` — atomic guest revision
  promotion runner.
- `system.d/rocknix-recovery-toggle.service` — pre-`sysinit.target`
  per-boot default-target selector.
- `scripts/{rocknix-guest-prep, rocknix-guest-promote, rocknix-guest-soak, rocknix-guest-udev-stage, rocknix-recovery-toggle}` — install to `/usr/bin`.
- `tests/{nix-integration-runtime-smoke.sh, nix-integration-static-checks.sh}`.

Status: **ENTIRE PACKAGE = MUST-KEEP, expand**.

External host requirements consumed by the unit:
- `/usr/bin/systemd-nspawn` from systemd package (must keep with `-Dmachined=false` — confirm currently absent flag still allows nspawn; in package.mk machined is disabled but nspawn binary is still produced).
- `/usr/bin/nsenter` (util-linux) **MUST-KEEP**.
- `/dev/dri/card0`, `/dev/dri/renderD128` — from `mesa` (`freedreno`) and kernel; **MUST-KEEP** mesa+freedreno on host.
- `inputplumber` (in `ADDITIONAL_PACKAGES`) and its config (`projects/ROCKNIX/devices/SM8550/filesystem/usr/share/inputplumber/{capability_maps,devices}/*.yaml`) — referenced explicitly in `rocknix-guest-v2.service` comments (it removes hidden devices before guest udev stage). **MUST-KEEP**.
- Quirks platform dir `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/*` — runs early via autostart for hardware init (LED/fan/governors/touch/audio path). **MUST-KEEP** at minimum for cold-boot hardware bringup before nspawn. Some entries (e.g. `090-ui_service`) are recovery-only and could be split later.

---

## 7. Recovery

Path: when `/flash/rocknix.no-nspawn` exists OR kernel cmdline has
`rocknix.safe=1`, `rocknix-recovery-toggle` sets default.target to
`rocknix.target` (legacy ROCKNIX userland).

**Recovery surface that must remain installed:**

- `rocknix.target` + dependency chain: `rocknix-autostart.service` ->
  `/usr/bin/autostart` (`projects/ROCKNIX/packages/sysutils/autostart/sources/autostart`)
  -> per-platform quirks
  (`projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/*`).
- Legacy UI services: `essway.service`, `sway.service` from
  `projects/ROCKNIX/packages/ui/emulationstation/system.d/essway.service`,
  `projects/ROCKNIX/packages/wayland/compositor/sway/` —
  WantedBy `rocknix.target` only, so they are inert when guest is
  default. They are required to satisfy the recovery toggle. **MUST-KEEP**
  per the explicit comment in `rocknix-recovery-toggle`:
  > "essway/sway/rocknix-autostart/etc are WantedBy=rocknix.target ...
  > default=graphical.target leaves the device on a blank/login-only
  > screen".
- `rocknix-config`, `rocknix-update`, `factoryreset`, `installtointernal`,
  `wifictl`, `setrootpass` — `projects/ROCKNIX/packages/rocknix/sources/scripts/`.
- `/flash/HOW-TO-FALL-BACK.md` (installed by `nix-integration`).
- Audio (`pipewire-pulse.service` WantedBy=default.target,
  `projects/ROCKNIX/packages/audio/pipewire/system.d/`) — used by recovery UI.
- `inputplumber.service` (`projects/ROCKNIX/packages/tools/inputplumber/sources/usr/lib/systemd/system/inputplumber.service`) — used by both.

**Recovery candidate-remove**:
- `emulationstation` per-emulator config/cores
  (`projects/ROCKNIX/packages/emulators/...`) — recovery does not need
  emulator runtime, only a UI shell. These are large and could be moved
  guest-side entirely. **CANDIDATE-REMOVE** with caveat: this dramatically
  alters recovery UX.
- Themes `projects/ROCKNIX/packages/ui/themes/` — visual only; trim.

---

## 8. Headline "Slim Base" Candidates to Remove

Ranked by impact / safety:

1. **Whole `packages/emulation/*` libretro cores + `projects/ROCKNIX/packages/emulators/*` (libretro + standalone)** — heaviest by far; the guest owns emulation. Removal requires keeping enough recovery UX (or accepting recovery = SSH only). **CANDIDATE-REMOVE (large win, breaks legacy recovery UX)**.
2. **Mediacenter + addons** (`packages/mediacenter/kodi*`, `packages/addons/*`) — `MEDIACENTER` isn't set for SM8550 image (not in deps chain explicitly) but distribution adds Kodi-binary-addons via emulationstation; verify. **CANDIDATE-REMOVE**.
3. **`packages/audio/{pulseaudio}`** — `PIPEWIRE_SUPPORT=yes` only; pulseaudio is `disabled` in image meta but built as a runtime tool by some packages. **CANDIDATE-REMOVE**.
4. **Bluez host stack** if guest BT is acceptable (see §5).
5. **NFS / Samba / WireGuard / ZeroTier / OpenVPN / Syncthing / Tailscale / Rclone / Simple-HTTP** — move to guest. Set distribution options off:
   - `distributions/ROCKNIX/options`: `SAMBA_SERVER`, `SFTP_SERVER`,
     `SIMPLE_HTTP_SERVER`, `ZEROTIER_SUPPORT`, `WIREGUARD_SUPPORT`,
     `NFS_SUPPORT`, `OPENVPN_SUPPORT`, `AVAHI_DAEMON` (keep mDNS).
6. **`packages/print/{cups,freetype}` chain** — present via gst-plugins / dependency closure. Investigate.
7. **`packages/wayland/weston`, `projects/ROCKNIX/packages/wayland/weston*`** — `WINDOWMANAGER="swaywm-env"`, weston only used on RK3588 path. **CANDIDATE-REMOVE** for SM8550.
8. **`packages/lang/lua52`, `packages/python/*`, `packages/rust/*`** — pulled for build only or for retroarch; trim runtime-installed portion.
9. **OEM, INSTALLER, TESTING, DEBUG_PACKAGES** — gated off; ensure they stay off in SM8550 release builds. Also `MODULES_PKG`, `INITRAMFS_PARTED_SUPPORT`.
10. **Unused-platform sources**: `projects/{Allwinner,Amlogic,RPi,Rockchip,Samsung,NXP,ARM,Generic}` and corresponding `packages/linux-firmware/firmware-imx` etc. — not selected in build, but consume tree size. **CANDIDATE-REMOVE** for repo hygiene only; orthogonal to image size.

---

## 9. Minimum Host Service Set (proposed)

The lean steady-state SM8550 host can be expressed as:

```
sysinit.target
└─ rocknix-recovery-toggle.service        (decide default.target)
multi-user.target
├─ systemd-{timesyncd,journald,udevd,logind,tmpfiles*}
├─ sshd.service                            (host SSH — KEPT INDEFINITELY)
├─ connman.service                         (host network plane)
├─ avahi-daemon.service                    (mDNS)
├─ dbus.service
├─ nix-storage-setup.service -> nix.mount
├─ rocknix-automount.service               (mount /storage, /flash)
├─ inputplumber.service                    (pre-guest device shaping)
├─ system-utils: fancontrol, batteryledstatus, headphones, input, video
└─ getty@tty0.service                      (serial/console fallback)

rocknix-graphical.target  (= default.target via nix-integration)
├─ rocknix-guest-v2.service                (systemd-nspawn)
└─ rocknix-guest-promote.service           (post-boot promotion oneshot)

rocknix.target            (recovery fallback only)
├─ rocknix-autostart.service -> autostart -> quirks/SM8550/* -> ${UI_SERVICE}
├─ sway.service / essway.service
├─ pipewire-pulse.service
├─ rocknix-memory-manager.service
└─ save-sysconfig.service
```

---

## 10. Risks / Open Questions

1. **machined disabled in systemd build** (`-Dmachined=false` in
   `packages/sysutils/systemd/package.mk`) — `rocknix-guest-v2.service`
   uses `--register=no` which is consistent, but confirm `systemd-nspawn`
   binary is still produced under this flag (it should be; nspawn is
   independent of machined). Quick check: `build.ROCKNIX-SM8550.aarch64/install_pkg/systemd-255.8/usr/bin/systemd-nspawn` existence.
2. **Bluetooth ownership** — host has `BLUETOOTH_SUPPORT=yes` + bluez +
   ldacBT/libfreeaptx; the guest also binds `/dev/rfkill`. If the guest
   runs its own bluez, the host stack is redundant (and `/dev/rfkill`
   exclusivity may cause conflicts).
3. **NetworkManager vs ConnMan boundary** — Layer 14 comment says
   "guest's NetworkManager owns wlan0 directly (Tier C finding)". If
   wlan0 is guest-owned, host connman should not also try to manage
   wlan0. Investigate whether host connman is restricted (e.g. ethernet
   only) or whether it can be removed and the host relies on the guest's
   network entirely. Removing host connman would impact host SSH-over-WLAN
   if the host has no other connection plane — this is the biggest risk
   for "keep host SSH indefinitely".
4. **Recovery UX**: removing emulators from host kills useful recovery
   self-service; document the tradeoff (recovery = SSH-only?).
5. **/flash partition size** — current `update.sh` cleans `/EFI`, `/boot`;
   ensure recovery README + ABL fits.
6. **`MEDIACENTER`** unset for SM8550, but `kodi`/`kodi-binary-addons`
   are listed under `packages/mediacenter`. Verify image actually
   excludes them (image meta gates on `${MEDIACENTER}` != "no").
7. **Quirks autostart vs nix-integration default.target** — the
   per-platform quirks under `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/`
   are invoked from `/usr/bin/autostart` which is run by
   `rocknix-autostart.service` (`WantedBy=rocknix.target`). When the
   guest is default, **these quirks DO NOT RUN** at boot. Hardware
   init (LED, fan, governors, touchscreen events, audio path) may be
   absent unless the guest replicates them. **This is the single most
   important gap to validate** for the slim-host design.

---

## 11. Start Here

Open `projects/ROCKNIX/packages/tools/nix-integration/package.mk` and
`projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service`
first. They define the entire contract between host and guest and
implicitly enumerate every host capability the guest depends on
(device nodes, sysfs paths, /storage subtrees, systemd state files,
udev DB). Anything outside that bind list is a candidate-remove or a
quirks/recovery-only artifact.

Second: `projects/ROCKNIX/devices/SM8550/options` for the device-level
package/firmware/driver knobs, and
`projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/` to decide
which quirks must move into guest-side equivalents before host slimming
is safe.
