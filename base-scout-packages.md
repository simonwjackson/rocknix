# SM8550 Base Image Scout — Removable Packages

Scope: SM8550 (`projects/ROCKNIX/devices/SM8550`) image with NixOS guest
owning UI / audio / input / emulators. Host must keep SSH, OTA update,
recovery, and `systemd-nspawn` boot path working.

## Files Retrieved

1. `projects/ROCKNIX/packages/virtual/image/package.mk` (lines 1–110) — top-level meta package; defines what gets pulled in based on flags.
2. `distributions/ROCKNIX/options` (lines 1–end) — global build switches (BLUETOOTH, SAMBA_SERVER, WIREGUARD, ZEROTIER, JOYSTICK, REMOTE, NANO, HTOP, BTOP, NFS, etc.).
3. `projects/ROCKNIX/devices/SM8550/options` (lines 1–end) — device defaults: `DISPLAYSERVER=wl`, `WINDOWMANAGER=swaywm-env`, `VULKAN=vulkan-loader`, `EXTRA_CMDLINE` includes `systemd.unified_cgroup_hierarchy=1` (needed for nspawn), `ADDITIONAL_PACKAGES="gamepadcalibration screen-switch rocknix-abl inputplumber"`.
4. `projects/ROCKNIX/packages/virtual/emulators/package.mk` (entire file) — every libretro core + every standalone emulator pulled in; the largest single source of bloat.
5. `projects/ROCKNIX/packages/virtual/gamesupport/package.mk` — sixaxis, rocknix-hotkey, jstest-sdl, gamecontrollerdb, sdljoytest, sdltouchtest, control-gen, sdl2text, mangohud, rocknix-touchscreen-keyboard.
6. `projects/ROCKNIX/packages/virtual/swaywm-env/package.mk` — sway, wlr-randr, swayimg, rocknix-screenshot.
7. `projects/ROCKNIX/packages/virtual/es-themes/package.mk` — es-theme-art-book-next.
8. `projects/ROCKNIX/packages/virtual/synctools/package.mk` — rsync, rclone, syncthing.
9. `projects/ROCKNIX/packages/virtual/debug/package.mk` — gdb, memtester, kmsxx, nvtop, apitrace, kmsxx (strace stripped).
10. `projects/ROCKNIX/packages/virtual/initramfs/package.mk` — `libc busybox util-linux e2fsprogs dosfstools spleen-font avfs rocknix-splash` (all needed for boot/initrd).
11. `projects/ROCKNIX/packages/virtual/linux-firmware/package.mk` — `kernel-firmware ${FIRMWARE}`.
12. `projects/ROCKNIX/packages/virtual/linux-drivers/package.mk` — adds `rocknix-joypad` if `ROCKNIX_JOYPAD=yes`; SM8550 sets it to `no`.
13. `projects/ROCKNIX/packages/rocknix/package.mk` — host update plumbing (`update.sh`, `post-update`, `rocknix.target` as `default.target`, save-sysconfig, memory-manager, autostart). **Must stay.**
14. `projects/ROCKNIX/packages/tools/nix-integration/package.mk` (entire file) — fetches pinned guest tarball, installs `/usr/lib/nix-integration/{guest,tests,docs}`, host scripts (`rocknix-guest-prep`, `rocknix-guest-promote`, `rocknix-recovery-toggle`, `rocknix-guest-soak`, `rocknix-guest-udev-stage`), enables `nix-storage-setup.service`, `nix.mount`, `rocknix-graphical.target`, `rocknix-guest-v2.service`, `rocknix-guest-promote.service`, `rocknix-recovery-toggle.service`. **Must stay.**
15. `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service` (ExecStart block) — only kernel devices and a narrow `/storage` bind list; nothing from host `/usr` is bound into the guest.
16. `projects/ROCKNIX/packages/sysutils/autostart/package.mk` + `system.d/rocknix-autostart.service` — generic boot dispatcher. **Must stay** (rocknix package wires it as default.target).
17. `projects/ROCKNIX/packages/sysutils/system-utils/package.mk` — fancontrol, headphone_sense, hdmi_sense, input_sense, ledcontrol, turbomode + per-device autostart. SM8550-specific scripts present.
18. `projects/ROCKNIX/packages/hardware/quirks/package.mk` + `platforms/SM8550/` — thermal, governors, fan, suspend, affinity, audio_path, mangohud-supported, ui_service. Some entries are host-UI-only (`090-ui_service`, `091-ui_shader`, `075-mangohud-supported`) but the rest (thermal/cpu/affinity/audio_path/led/touch events) are host-owned hardware policy.
19. `projects/ROCKNIX/packages/tools/rocknix-abl/package.mk` — installs signed ABL into `/usr/share/bootloader/rocknix_abl/`. **Must stay** (recovery / flashing).
20. `build.ROCKNIX-SM8550.aarch64/install_pkg/` (directory listing) — concrete set of 448 staged packages in the current image, used to validate the candidate-removal list.

## Key Code

### What the SM8550 image pulls in (entry point)

`projects/ROCKNIX/packages/virtual/image/package.mk`:

```
PKG_DEPENDS_TARGET="toolchain squashfs-tools:host ... busybox lsof umtprd util-linux usb-modeswitch poppler jq socat \
                    p7zip file initramfs grep util-linux btrfs-progs zstd lz4 empty lzo libzip \
                    bash coreutils system-utils autostart quirks powerstate \
                    gzip six xmlstarlet pyudev dialog network mako-osd rocknix"

PKG_UI="emulationstation es-themes textviewer"
PKG_UI_TOOLS="fbgrab grim"
PKG_GRAPHICS="imagemagick"
PKG_FONTS="corefonts"
PKG_MULTIMEDIA="ffmpeg vlc mpv gmu m8c"
PKG_SOUND="espeak libao"
PKG_SYNC="synctools"
PKG_TOOLS="patchelf i2c-tools evtest"
PKG_DEBUG="debug"

# (BASE_ONLY=true skips PKG_UI/PKG_SOUND/PKG_SYNC/PKG_GRAPHICS/PKG_MULTIMEDIA/misc-packages)
[ "${EMULATION_DEVICE}" = "yes" ] && PKG_DEPENDS_TARGET+=" emulators gamesupport"
[ "${PIPEWIRE_SUPPORT}" = "yes" ] && PKG_DEPENDS_TARGET+=" alsa pulseaudio pipewire wireplumber"
[ "${DEVICE}" = "SM8550" ]       && PKG_DEPENDS_TARGET+=" nix-integration"
```

### Guest contract (host-side)

`rocknix-guest-v2.service` ExecStart only binds kernel device nodes
(`/dev/snd`, `/dev/dri/card0`, `/dev/dri/renderD128`, `/dev/input`,
`/dev/tty0`, `/dev/tty1`, `/dev/rfkill`), `/sys/class/{backlight,leds,devfreq}`,
`/sys/devices/system/cpu/cpufreq`, and narrow `/storage` paths.
Comments explicitly forbid binding host `/usr`, `/lib`, `/etc/profile*`,
`/etc/resolv.conf`, `/run/0-runtime-dir`, `/tmp/.X11-unix`. The host
userspace stacks (Mesa/EGL/Vulkan ICDs, sway, pipewire, RetroArch) are
deliberately *not* used by the guest.

### Update / recovery plumbing on the host

* `rocknix` package -> `/usr/share/bootloader/update.sh`, `/usr/share/post-update`, enables `rocknix-autostart`, `rocknix-memory-manager`, `save-sysconfig`.
* `rocknix-abl` -> signed bootloader payload for SM8550 in `/usr/share/bootloader/rocknix_abl/`.
* `nix-integration` -> `rocknix-recovery-toggle.service` flips between guest UI and legacy host (the legacy host plane is still the fallback when `/flash/rocknix.no-nspawn` is set).

## Architecture

The SM8550 image today is built from three independent stacks layered on top of the boot/host plumbing:

1. **Host plumbing (must keep)**: kernel, initramfs, systemd, busybox, coreutils/util-linux, glibc, openssh, connman+iw+iwd+wireless-regdb+kernel-firmware, btrfs/e2fs/dosfs/squashfs, libzip/zstd/lz4, dbus, polkit, parted, qcom-abl + rocknix-abl, the `rocknix` meta (update.sh, post-update, rocknix.target), `autostart`, `system-utils` (hw button helpers — partially relevant), `quirks` (SM8550 thermal/governor/affinity), `powerstate`, `nix-integration` (guest bootstrap + nspawn glue), `mako-osd` (the host's recovery overlay), `dialog`.

2. **Legacy host UI/AV/emulation stack (now redundant under the guest)**: emulationstation, es-themes, textviewer, sway + swaywm-env + xwayland + foot + wlroots + wlr-randr + swayimg + rocknix-screenshot + libxkbcommon + mtdev + libinput + seatd + xkeyboard-config + xkbcomp + xorg-launch-helper + entire `/packages/x11`/`/packages/wayland`/`xcb-*` lib tree, mesa + glmark2 + vkmark + glslang + spirv-tools + libepoxy + libglvnd + vulkan-loader/headers/tools + waffle, ffmpeg + vlc + mpv + gmu + m8c + gstreamer + libdvbpsi + libplacebo + libvpx + gst-libav + gst-plugins-base/good + dav1d + aom + opus + opusfile + libass + freetype + harfbuzz + fontconfig + dejavu + liberation-fonts-ttf + cairo + pango + pixman + libdrm + libdisplay-info + libpciaccess + libwebp + libjpeg-turbo + libpng + tiff + jasper + freeimage + libraw + gdk-pixbuf + at-spi2-core + atk + libxslt + xmlstarlet (kept by host scripts), poppler, faad2, sbc, ldacBT, libfreeaptx, libldac, openal-soft, fluidsynth, wavpack, libmodplug, libxmp, libxmp-lite, libvorbis, libvorbisidec, libogg, libsamplerate, portaudio, libsndfile, libao, espeak, soxr, speex, speexdsp, wildmidi, zmusic, alsa-utils + alsa-lib + alsa-topology-conf + alsa-ucm-conf, pulseaudio, pipewire, wireplumber, SDL2 (host build is used by host emus only), inputplumber (host input router), gamepadcalibration, sixaxis, joyutils, the entire gamesupport metapkg, mangohud, every `*-lr` libretro core, all `*-sa` standalones (`duckstation-sa`, `flycast2021-sa→sa`, `gzdoom-sa`, `hatari-sa`, `hypseus-singe`, `moonlight`, `mupen64plus-sa`, `portmaster`, `openbor`, `pico-8`, `ppsspp-sa`, `scummvmsa`, `touchhle-sa`, `vice-sa`, `wine`, `yabasanshiro-sa`, plus the SM8550-specific list: `aethersx2-sa`, `ares-sa`, `azahar-sa`, `bigpemu-sa`, `cemu-sa`, `dolphin-sa`, `drastic-sa`, `gopher64-sa`, `daedalusx64-sa`, `mednafen`, `melonds-sa`, `nanoboyadvance-sa`, `rpcs3-sa`, `supermodel-sa`, `xemu-sa`, `skyemu-sa`, `steam`, `vita3k-sa`, `box86`, `pcsx_rearmed-lr` 32-bit), retroarch + retroarch-assets + retroarch-joypads + retroarch-overlays + retropie-shaders + slang-shaders + core-info + libretro-database.

3. **Optional services (review per-policy)**: samba (`SAMBA_SERVER=yes`), wsdd2, nfs-utils + libtirpc + rpcbind, syncthing, rclone, rsync, tailscale, zerotier-one, wireguard-tools, simple-http-server, avahi + nss-mdns, bluez + sbc (BT), ntfs-3g_ntfsprogs (`NTFS3G=yes`), exfatprogs (`EXFAT=yes`), udevil (automount), entware (storage `/opt`).

## Removable (host-side, by category)

All paths below are package directories; pruning them means dropping them from the corresponding `PKG_DEPENDS_TARGET` in `projects/ROCKNIX/packages/virtual/image/package.mk` (or the relevant virtual meta) and is not a delete of the package directory itself.

### A. EmulationStation / themes / launcher UI (free win)

Source: `PKG_UI`, `PKG_UI_TOOLS`, `es-themes`.

* `projects/ROCKNIX/packages/ui/emulationstation/`
* `projects/ROCKNIX/packages/ui/themes/` (whole tree, art-book-next)
* `projects/ROCKNIX/packages/virtual/es-themes/`
* `sources/es-theme-art-book-next/`
* `packages/...textviewer` (whole UI text viewer)
* `packages/sysutils/fbgrab/` and `packages/apps/...grim/` (`PKG_UI_TOOLS`) — used by host screenshot keybinds, redundant under guest.
* `packages/graphics/imagemagick` (`PKG_GRAPHICS` — only used for ES box-art rebuilding) — redundant.

Risk: none for SSH/update/recovery. The guest renders the UI.

### B. Sway / Wayland compositor stack (free win)

Source: `WINDOWMANAGER=swaywm-env` → `projects/ROCKNIX/packages/virtual/swaywm-env/package.mk`.

* `packages/wayland/compositor/sway/`
* `packages/wayland/util/wlr-randr/`
* `packages/apps/swayimg/`
* `packages/apps/rocknix-screenshot/`
* `packages/apps/screen-switch/` (depends on sway; in `ADDITIONAL_PACKAGES`)
* `packages/wayland/compositor/swaybg/` (built but unused; brought in by sway dep tree)
* `packages/wayland/compositor/weston/` and `weston-kiosk-shell-dpms/` (not active on SM8550 but still in repo)
* `packages/wayland/util/mtdev/`, `wayland-protocols`, `xwayland`, `wlroots`, `libinput`, `libxkbcommon`, `seatd`, `xorg-launch-helper`, `foot`, `fcft`, `tllist`, `libfontenc`, `libICE`, `libSM`, `libXft`, `libXt`, `libXmu`, `libXaw`, `libxcb*` (kept transitively only for sway/xwayland)

How to disable: set `WINDOWMANAGER=none` and `DISPLAYSERVER=no` in `projects/ROCKNIX/devices/SM8550/options`. This drops the whole `wl` virtual chain via `packages/virtual/wl/package.mk`.

Risk: any host helper script that calls `swaymsg`/`wlr-randr` breaks. Searches show `quirks/platforms/SM8550/090-ui_service`, `091-ui_shader`, `gamesupport` and `screen-switch` are the only callers — all UI plane.

### C. Emulators + retroarch + libretro cores (largest free win)

Source: `EMULATION_DEVICE=yes` → pulls `emulators` and `gamesupport`. The emulators meta lists ~120 packages.

To disable wholesale: set `EMULATION_DEVICE=no` in `projects/ROCKNIX/devices/SM8550/options`.

Removable virtual entries:

* `projects/ROCKNIX/packages/virtual/emulators/`
* `projects/ROCKNIX/packages/virtual/gamesupport/`

Concrete packages pruned (current image staged in `build.ROCKNIX-SM8550.aarch64/install_pkg/`):

* RetroArch stack: `packages/emulation/...retroarch`, `retroarch-assets`, `retroarch-joypads`, `retroarch-overlays`, `retropie-shaders`, `slang-shaders`, `core-info`, `libretro-database`, `libretro-common`.
* All `*-lr` directories under `packages/emulation/`.
* Standalones: every `packages/emulation/*` non-`-lr` dir referenced by `PKG_EMUS` (`amiberry`, `box64`, `duckstation-sa`, `flycast-sa`, `gzdoom-sa`, `hatarisa`, `hypseus-singe`, `moonlight`, `mupen64plus-sa`, `portmaster`, `openbor`, `pico-8`, `ppsspp-sa`, `scummvmsa`, `touchhle-sa`, `vice-sa`, `wine`, `yabasanshiro-sa`, plus SM8550 list above).
* `packages/sysutils/box86/` (32-bit; pulled via `EMUS_32BIT`).
* `packages/emulation/libretro-database/`, `core-info/`, `slang-shaders/`, etc.
* `packages/sysutils/cabextract`, `p7zip` are kept by `image` meta directly — `p7zip` only useful for ROM unpacking in host emus; safe to drop along with emulators.
* `packages/multimedia/{ffmpeg,vlc,mpv,gstreamer,gst-libav,gst-plugins-*,libdvbpsi,libplacebo,libvpx,aom,dav1d,libass}`, `packages/audio/{fluidsynth,wavpack,libmodplug,libxmp,libxmp-lite,libvorbis,libvorbisidec,libogg,libsamplerate,libsndfile,libao,openal-soft,sbc,fdk-aac,flac,opusfile,libfreeaptx,libldac,ldacBT,speex,speexdsp,soxr,wildmidi,zmusic}` — only consumed by `mpv/vlc/ffmpeg/retroarch/libretro cores/standalones`. Drops with the emulator stack.
* `packages/apps/m8c/`, `packages/audio/espeak/`, `packages/multimedia/opusfile/` etc.
* `packages/apps/gmu/`, `packages/apps/portmaster/`, `packages/apps/moonlight/`, `packages/apps/mangohud/`, `packages/apps/qterminal/`, `packages/apps/gamescope/`, `packages/apps/sdljoytest/`, `packages/apps/sdltouchtest/`, `packages/apps/sdl2text/`, `packages/apps/control-gen/`, `packages/apps/jstest-sdl/`, `packages/apps/gamecontrollerdb/`, `packages/apps/rocknix-hotkey/`, `packages/apps/rocknix-touchscreen-keyboard/`, `packages/apps/oga_controls/`, `packages/apps/gamepadtester/`, `packages/apps/commander/`, `packages/apps/fileman/`, `packages/apps/device-switch/`, `packages/apps/list-guid/`, `packages/apps/mako-osd/` (kept by image meta — see Risk).
* `packages/network/sixaxis/`, `packages/python/...` (only pulled by gamesupport/python emulators), `packages/lang/lua52`, `packages/lang/lua54`, `packages/devel/luajit/`.
* `packages/audio/{alsa-utils, alsa-topology-conf, alsa-ucm-conf, alsa-lib}` — *keep* `alsa-lib`+`alsa-ucm-conf` only if needed for kernel-side `/dev/snd` ACL setup; otherwise the guest brings its own. Removing `alsa-utils` is safe; `aplay`/`amixer` aren't used by host plumbing.
* `packages/audio/pulseaudio/`, `packages/audio/pipewire/`, `packages/audio/wireplumber/` — set `PIPEWIRE_SUPPORT=no` in `distributions/ROCKNIX/options`. Guest owns audio over `/dev/snd`.
* `packages/graphics/SDL2*` family, `packages/audio/SDL2_mixer` — referenced only by ES + standalone emus.
* `packages/sysutils/box86`, `packages/lang/...` only used by emus.

Risk: `mako-osd` is in the `image` meta `PKG_DEPENDS_TARGET` (`network mako-osd rocknix`). It is used by the host for on-screen notifications. If the guest provides recovery messaging via its own compositor, mako-osd can also be dropped. Otherwise keep.

### D. Input router for the host (review per device)

* `projects/ROCKNIX/packages/tools/inputplumber/` (in `ADDITIONAL_PACKAGES`) — host-side gamepad remapper. The guest binds `/dev/input` directly and runs its own input handling. Drop from `ADDITIONAL_PACKAGES` in `projects/ROCKNIX/devices/SM8550/options`.
* `projects/ROCKNIX/packages/tools/gamepadcalibration/` — same logic.
* `packages/network/sixaxis/` (host BT controller pairing) — drop unless host needs to pair PS3/PS4 pads before guest boots.

Risk: if a user is on a stock host UI fallback, controllers may not work in recovery. Mitigated by `rocknix-recovery-toggle` re-enabling the legacy host UI on demand only when the legacy stack is *kept*. If C is also dropped, recovery is SSH-only.

### E. Debug / dev shell tooling (low-risk free win)

Source: `DEBUG_PACKAGES=yes` → `projects/ROCKNIX/packages/virtual/debug/package.mk` (gdb, memtester, kmsxx, nvtop, apitrace), plus image-meta `PKG_TOOLS="patchelf i2c-tools evtest"`.

Set `DEBUG_PACKAGES=no`, `HTOP_TOOL=no`, `BTOP_TOOL=no`, `NANO_EDITOR=no`. Concrete removals:

* `packages/debug/{gdb,memtester,strace,valgrind,libva-utils,vdpauinfo}`
* `packages/graphics/kmsxx/`
* `packages/sysutils/nvtop/`, `packages/debug/apitrace/`
* `packages/sysutils/htop/`, `packages/sysutils/btop/`
* `packages/tools/nano/`
* `packages/devel/patchelf/` (host build/QA only — verify no runtime caller; `chk_ld_path` etc. run at build time)
* `packages/devel/i2c-tools/` (kept for `i2cdetect` in fancontrol scripts — keep if `system-utils/fancontrol` is active on SM8550)
* `packages/devel/evtest/` (only manual debugging)
* `packages/multimedia/glmark2`, `packages/multimedia/vkmark/`, `packages/graphics/mesa-demos` — already guarded behind `OPENGL_SUPPORT`/`OPENGLES_SUPPORT`/`VULKAN_SUPPORT`; SM8550 has VULKAN_SUPPORT=yes so `vkmark` is currently built. Drop `vkmark` once `EMULATION_DEVICE=no`.

Risk: losing `gdb` and `strace` makes on-device debugging painful. Recommended: ship `strace` and `gdbserver` minimally if remote dev is expected.

### F. Network services beyond SSH (per-policy)

Default options in `distributions/ROCKNIX/options`:

* `SAMBA_SERVER=yes` → `packages/network/samba/` + `packages/network/wsdd2/` are built. Guest can re-export `/storage/roms` itself; safe to drop on host.
* `NFS_SUPPORT=yes` → `packages/network/nfs-utils/` + `libtirpc` + `rpcbind`. Same logic.
* `SIMPLE_HTTP_SERVER=yes` → `packages/network/simple-http-server/`. Drop.
* `ZEROTIER_SUPPORT=yes` → `packages/network/zerotier-one/`. Drop (guest can run it).
* `WIREGUARD_SUPPORT=yes` → `packages/network/wireguard-tools/`. Host kernel still has the wg module; user-space tools can move to guest.
* `tailscale` (`packages/network/tailscale/`) — present in build but not gated by an option flag; check `projects/ROCKNIX/...` for the implicit dep. Drop on host; move to guest.
* `packages/network/syncthing/`, `packages/network/rclone/`, `packages/network/rsync/` — via `synctools` virtual. `rsync` is *also* a transitive build-host dep but the target build can drop the on-image binary; verify update.sh path. `update.sh` uses `cp/tar`, not rsync, so on-image rsync is optional.
* `packages/network/avahi/` + `packages/network/nss-mdns/` — host advertises `rocknix.local`. Useful for `ssh rocknix.local`; recommend *keep* on host even though guest could do it (guest may not be up).
* `packages/network/bluez/` + `packages/audio/sbc/`, `ldacBT`, `libfreeaptx` — pull-in chain from `BLUETOOTH_SUPPORT=yes`. Guest can own BT via `/dev/rfkill` bind. Drop on host.
* `packages/network/iptables/`, `libnftnl`, `libmnl`, `libnl` — kept by networkmanager/connman/wireguard; iptables itself is mostly safe to drop if neither user-space wg nor docker is on host.

Risk:
- Dropping samba/wsdd2 breaks "rocknix.local SMB share" mounted from Windows during recovery. Mitigation: re-implement in guest, or keep host samba only when legacy UI active.
- Dropping avahi breaks `ssh rocknix.local`; keep on host.

### G. Storage & filesystem helpers (mostly keep)

Keep:

* `packages/sysutils/btrfs-progs`, `e2fsprogs`, `dosfstools`, `exfatprogs`, `parted`, `squashfs-tools`, `squashfuse`, `fuse`, `fuse2`, `util-linux`, `gptfdisk`, `kmod`, `mtools`, `populatefs` (host) — all part of boot/install/update path.
* `packages/sysutils/udevil/` — automount of `/storage`/USB; guest depends on host `/storage` already mounted. Keep.

Removable:

* `packages/sysutils/ntfs-3g_ntfsprogs/` if NTFS isn't required for SD cards (set `NTFS3G=no`).
* `packages/sysutils/umtprd/` — MTP serving (USB-to-PC file transfer of `/storage`). Drop unless that workflow matters; cheap.
* `packages/sysutils/usb-modeswitch/`, `packages/sysutils/usbutils/` — small but only useful for cellular dongles / debug.
* `packages/compress/p7zip`, `packages/textproc/poppler` — only used by ROM/comic tooling. Drop with emulators.
* `packages/sysutils/file/`, `packages/textproc/jq`, `packages/textproc/xmlstarlet`, `packages/tools/dialog/` — referenced by host scripts (autostart quirks, update.sh, system-utils). `jq` and `xmlstarlet` are used by `quirks/platforms/SM8550/*`. **Keep.**
* `packages/sysutils/lsof/`, `packages/sysutils/socat/`, `packages/network/fping/` — minor; keep `socat` and `lsof` for SSH-side debugging.

### H. Misc

* `packages/python/Python3/` and all `packages/python/*` — pulled by `gamepadcalibration` and various standalones. Drop with C/D.
* `packages/lang/{lua52,lua54}`, `packages/devel/luajit` — pulled by retroarch/cores. Drop with C.
* `packages/security/{nss,nspr}` — pulled by samba/avahi/curl-tls/qt6. If samba/qt6 drop, evaluate.
* `packages/devel/qt6/` — for Dolphin Qt frontend (RK3399/SM8250/SM8550/SM8650 — see `add_emu_core gamecube dolphin dolphin-qt-gc`). Drops with C.
* `packages/sysutils/entware/` — `/storage/.opt` package manager bootstrap; light-weight (just a service+script). Keep or drop based on whether users still expect Entware on the host.
* `packages/sysutils/system-utils/` — SM8550 has device-specific scripts (`AYN Thor` etc.). Hardware behavior (LED, headphone jack, HDMI hotplug) — **keep** (these run from host autostart, before guest).
* `packages/hardware/quirks/` — **keep**; provides SM8550 thermal/governor/affinity tweaks. Note `090-ui_service` and `091-ui_shader` are host-UI specific and become dead code once C is dropped — harmless, but can be pruned in `platforms/SM8550/` as cleanup.

## Must Keep (host minimum for SSH / update / recovery / nspawn)

| Area | Packages |
| --- | --- |
| Bootloader | `projects/Qualcomm/devices/Dragonboard/packages/mkbootimg`, `packages/tools/qcom-abl`, `projects/ROCKNIX/packages/tools/rocknix-abl/`, `packages/tools/u-boot-tools` (transitive) |
| Kernel & init | `packages/linux/`, `projects/ROCKNIX/packages/virtual/initramfs/` (incl. `avfs`, `spleen-font`, `rocknix-splash:init`), `packages/tools/plymouth-lite:init`, `kernel-firmware` |
| Userland core | `packages/sysutils/busybox`, `packages/sysutils/systemd`, `packages/lang/gcc` runtime (glibc, libgcc, libstdc++), `packages/security/libxcrypt`, `packages/sysutils/util-linux`, `packages/sysutils/e2fsprogs`, `packages/sysutils/dosfstools`, `packages/sysutils/btrfs-progs`, `packages/sysutils/squashfs-tools`, `packages/sysutils/squashfuse`, `packages/sysutils/fuse`, `packages/sysutils/kmod`, `packages/sysutils/parted`, `packages/sysutils/dbus`, `packages/security/polkit` (used by `inputplumber`; keep only if D kept), `packages/sysutils/udevil` |
| Update path | `projects/ROCKNIX/packages/rocknix/` (`update.sh`, `post-update`, `rocknix.target`, `rocknix-autostart.service`, `rocknix-memory-manager.service`, `save-sysconfig.service`), `projects/ROCKNIX/packages/sysutils/autostart/`, `projects/ROCKNIX/packages/sysutils/system-utils/`, `projects/ROCKNIX/packages/hardware/quirks/` |
| nspawn / nix | `projects/ROCKNIX/packages/tools/nix-integration/` (with its enabled units: `nix-storage-setup.service`, `nix.mount`, `rocknix-graphical.target`, `rocknix-guest-v2.service`, `rocknix-guest-promote.service`, `rocknix-recovery-toggle.service`) |
| Networking for SSH | `packages/network/openssh`, `packages/network/connman`, `packages/network/iwd`, `packages/network/iw`, `packages/network/wireless-regdb`, `packages/network/netbase`, `packages/security/openssl`, `packages/security/nettle`, `packages/security/gnutls`, `packages/network/avahi`, `packages/network/nss-mdns` (for `rocknix.local`) |
| Storage of nix store | `/nix` mount: provided by `nix-integration` `nix.mount` unit; only requires kernel `overlay`/`fuse` (depends on staging) and the busybox tools above. |
| Host shell tooling used by scripts | `packages/shells/bash`, `packages/sysutils/coreutils`, `packages/sysutils/sed`, `packages/sysutils/grep`, `packages/sysutils/gzip`, `packages/compress/xz`, `packages/compress/zstd`, `packages/compress/lz4`, `packages/textproc/jq`, `packages/textproc/xmlstarlet`, `packages/tools/dialog`, `packages/sysutils/pyudev`, `packages/sysutils/six`, `packages/textproc/libxml2`, `packages/textproc/libxslt` |

## Concrete Code Paths to Change

1. `projects/ROCKNIX/devices/SM8550/options` — flip:
   - `WINDOWMANAGER="none"` (kills swaywm-env meta → drops sway/swayimg/wlr-randr/rocknix-screenshot/screen-switch)
   - `DISPLAYSERVER="no"` (kills `packages/virtual/wl` chain → drops xwayland/wlroots/foot)
   - `EMULATION_DEVICE="no"` (kills `emulators` + `gamesupport`)
   - `ADDITIONAL_PACKAGES="rocknix-abl"` (drops `gamepadcalibration screen-switch inputplumber`)
   - `VULKAN_SUPPORT="no"` if no host GPU consumers (the guest brings its own Vulkan ICDs). Drops `vulkan-loader`, `vulkan-headers`, `vulkan-tools`, `vkmark`, `volk`, `spirv-tools`, `spirv-llvm-translator`, `glslang`.
   - `PREFER_GLES="no"` (no change; only matters for emus)

2. `distributions/ROCKNIX/options` — flip globally or via SM8550 override:
   - `PIPEWIRE_SUPPORT="no"` (drops alsa+pulseaudio+pipewire+wireplumber from `image` meta)
   - `BLUETOOTH_SUPPORT="no"` (drops bluez+sbc; guest owns BT)
   - `SAMBA_SERVER="no"` (drops samba+wsdd2)
   - `NFS_SUPPORT="no"` (drops nfs-utils+libtirpc+rpcbind)
   - `SIMPLE_HTTP_SERVER="no"` (drops simple-http-server)
   - `ZEROTIER_SUPPORT="no"` / `WIREGUARD_SUPPORT="no"` (drops user-space tools; kernel modules stay)
   - `JOYSTICK_SUPPORT="no"` (drops `joyutils`; double-check kernel paths)
   - `REMOTE_SUPPORT="no"` (drops `virtual/remote` → eventlircd, libirman, v4l-utils, evrepeat)
   - `MODULES_PKG="no"` (drops out-of-tree drivers metapackage)
   - `DEBUG_PACKAGES="no"`, `HTOP_TOOL="no"`, `BTOP_TOOL="no"`, `NANO_EDITOR="no"`
   - `EXFAT="no"` / `NTFS3G="no"` if SD cards are FAT/ext4 only.
   - `UDEVIL="yes"` — keep (automount of `/storage` is required by nix-integration prep)
   - Keep `ENABLE_UPDATES="yes"`.

3. `projects/ROCKNIX/packages/virtual/image/package.mk` — once flags above are flipped, the `BASE_ONLY=true` branch already excludes `PKG_UI`, `PKG_SOUND`, `PKG_SYNC`, `PKG_GRAPHICS`, `PKG_MULTIMEDIA`, `misc-packages`. Either (a) set `BASE_ONLY=true` for SM8550 (lightest hammer, but currently scoped to BASE builds only) or (b) make the metas conditional on `WINDOWMANAGER!=none`.

4. `projects/ROCKNIX/packages/virtual/emulators/package.mk` — guard `case "${TARGET_TYPE}"` so that `EMULATION_DEVICE=no` is honoured early; the file already short-circuits via the outer `[ "${EMULATION_DEVICE}" = "yes" ] && PKG_DEPENDS_TARGET+=" emulators gamesupport"` in `image/package.mk`, so flipping the device flag is sufficient.

## Risks of Removal

| Removal | Risk | Mitigation |
| --- | --- | --- |
| sway / swaywm-env stack | `rocknix-recovery-toggle` may rely on legacy host UI to display "boot recovery" splash | Recovery path is text/SSH; `mako-osd` (kept) shows OSD events; `rocknix-splash:init` still renders boot logo |
| EmulationStation + retroarch + cores | No on-device fallback if guest fails to boot | `rocknix.no-nspawn`/`rocknix.safe=1` already document recovery via SSH; document that "recovery = SSH only" |
| pipewire / pulseaudio / wireplumber / alsa-utils | Host loses sound; some quirk scripts (`002-audio_path`) call `amixer` | Either keep `alsa-utils` only (no daemons) or rewrite `002-audio_path` to use `tinyalsa`/sysfs. Verify: `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/002-audio_path` |
| inputplumber + gamepadcalibration + sixaxis | No host-side gamepad in legacy recovery; SSH/keyboard still works | Acceptable |
| samba + wsdd2 + nfs-utils | Lose host SMB/NFS share of `/storage/roms`; SD-card eject for ROM management still works | Re-implement in guest |
| zerotier / tailscale / wireguard tools | Lose pre-guest VPN connectivity; only matters if host needs out-of-band remote SSH before guest boots | Move to guest only when on-LAN SSH is reachable; otherwise keep tailscale on host |
| Python3, lua, luajit, qt6 | Lose `gamepadcalibration` and Dolphin-Qt; not used by host plumbing | None; drop with C |
| `mako-osd` | OSD notifications during recovery disappear | Optional; kept by default in `image` meta — only drop if guest owns the OSD even during pre-guest boot |
| `udevil` | `/storage` not auto-mounted → `nix-integration` `nix-storage-setup.service` fails | KEEP |
| `entware` | Users lose `/storage/.opt` package set | Document; cheap to keep |
| `quirks/platforms/SM8550/090-ui_service`/`091-ui_shader` | dead post-removal; not a removal blocker | Optional cleanup later |
| `kernel-firmware` | Wi-Fi / GPU break | KEEP (in `linux-firmware` meta) |
| `vulkan-loader` | If host has any post-boot GL/Vulkan smoke test, breaks | Verify `vkmark`/`glmark2` references — they all come from the emulator stack |
| `polkit` | Required by `inputplumber.service`; without inputplumber it's only needed for udisks-style flows | Drops with D |
| `python3 / pyudev / six / dialog / jq / xmlstarlet` | Host autostart scripts and quirks scripts | KEEP (used by host) |
| `rsync` | Update bundle install uses `cp -av`; rsync is convenience only | Safe to drop on-image; verify `post-update` script |

## Open Questions

1. Does any host quirk script under `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/` invoke `amixer`, `swaymsg`, or RetroArch-specific tooling? `002-audio_path`, `090-ui_service`, `091-ui_shader`, `075-mangohud-supported` are candidates; need to read each before pruning the audio/UI/mangohud stacks.
2. Does `rocknix-recovery-toggle` enable the *legacy host* graphical target on toggle? If yes, dropping sway/ES kills recovery UI; check `projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-recovery-toggle`.
3. Is `mako-osd` only used during early boot for "guest starting" notifications, or also during normal host operation? It is pulled by `image` meta directly (not by `gamesupport`).
4. `nix.mount` — does it require `fuse`/`overlay` userland or just kernel module? Affects whether `fuse`/`fuse2` can be slimmed.
5. Is `udevil`'s automount of FAT32 `/storage/.update` directory required before SSH comes up (for OTA bundle drop-in)? If yes, must keep.

## Start Here

Open `projects/ROCKNIX/packages/virtual/image/package.mk` first. It is the
authoritative list of what enters the SM8550 image and shows precisely
how `PKG_UI`/`PKG_SOUND`/`PKG_GRAPHICS`/`PKG_MULTIMEDIA`/`PKG_SYNC` are
gated. Pair it with `projects/ROCKNIX/devices/SM8550/options` (the
device-level switches) and `distributions/ROCKNIX/options` (the global
switches). Together those three files control >90% of what can be
dropped without touching individual package definitions.

The next file to read is
`projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service`
to confirm what host-side resources the guest actually consumes — the
bind list there is the ground truth for "must keep on the host".
