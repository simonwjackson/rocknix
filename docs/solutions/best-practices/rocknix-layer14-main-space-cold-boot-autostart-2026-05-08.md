# ROCKNIX Layer 14 main-space: cold-boot autostart on AYN Thor

Date: 2026-05-08
Hardware: AYN Thor (SM8550), DSI-2 1080x1920@120Hz primary panel, DSI-1
1080x1240@60Hz secondary panel, msm DRM driver, FD740 GPU.
Branch: `feat/rocknix-layer-14-thin-host`
Final HEAD: `99f5fc6bb2`

## Outcome

A cold reboot of Thor with `THIN_HOST=yes` inputs and the validated source
patches now produces this state without any manual intervention:

```
$ systemctl is-active rocknix-recovery-toggle.service \
                     rocknix-graphical.target \
                     rocknix-guest-v2.service
active
active
active

$ journalctl -u rocknix-guest-v2.service -b | tail -3
... [  OK  ] Reached target Graphical Interface.
...        Starting ROCKNIX Layer 14 sway kiosk session...
... [  OK  ] Started ROCKNIX Layer 14 sway kiosk session.
```

Sway is up, rendering to DSI-2 with the correct 90° transform; DSI-1 is
disabled. A wayland socket is exposed at `/run/user/0/wayland-1` inside
the guest; external clients (foot, etc.) connect and render.

## End-to-end pipeline

```
cold boot
    └─> rocknix-recovery-toggle.service (host)
         · reads /flash/rocknix.no-nspawn (absent → main-space)
         · writes /storage/.config/system.d/default.target → rocknix-graphical.target
    └─> rocknix-graphical.target (host)
         └─> rocknix-guest-v2.service (host)
              · ExecStartPre=/usr/bin/rocknix-layer14-prep
              ·   relinks guest /init to current system profile (Bug 6 fix)
              · ExecStartPre=/usr/bin/rocknix-guest-udev-stage
              ·   strips InputPlumber-hidden devices into /run/.guest-udev
              · ExecStart=/usr/bin/systemd-nspawn ... \
              ·   --bind=/dev/tty0 --bind=/dev/tty1 \
              ·   --bind-ro=/run/.guest-udev:/run/udev \
              ·   ...
              └─> guest PID 1 (NixOS systemd)
                   └─> multi-user.target
                        └─> rocknix-sway-kiosk.service (guest)
                             · path = [ dbus foot swaybg swaylock ]
                             · Type=simple, no TTYPath (PAM in nspawn fails)
                             └─> dbus-run-session sway -c /etc/sway/config
                                  · DRM master via libseat seatd backend
                                  · Mesa freedreno/turnip on FD740
                                  · DSI-2 transform 90, DSI-1 disable
                                  └─> swaybg (paints background)
```

## What had to be fixed

Eleven distinct bugs blocked this pipeline at first flash. Each was
live-validated on Thor and fixed in source.

### Host-side (5 + 1)

1. `${reasons }` POSIX shell typo in `rocknix-recovery-toggle`. Fixed.
2. `RECOVERY_TARGET="graphical.target"` would have left thin-host falling
   back to a non-existent target on flag toggle. Changed to
   `rocknix.target`.
3. `rocknix-layer14-prep` skipped `/init` relink on every clean install
   because `[ -x "${current_system}/init" ]` tested the host filesystem,
   not the guest's `/nix/store`. Now tests `${GUEST_ROOT}${path}`.
   (Bug 6.)
4. `--bind=/dev/console` clashed with the nspawn pty. Removed.
5. `cgroup v1 vs v2`: systemd-258 inside guest refused legacy v1 view.
   Added `Environment=SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1`.
6. `--bind=/run/udev` (raw): InputPlumber tags devices it claims with
   `S:inputplumber/by-hidden/...` in udev DB. libseat does not honour
   the tag and tried to canonicalize the hidden device's by-path
   symlink, hit ENOENT, cascaded into a wlroots GPU reset that turned
   both panels black. Fix: a host-side
   `rocknix-guest-udev-stage` script copies `/run/udev` to
   `/run/.guest-udev`, deletes every record marked
   `inputplumber/by-hidden`, and the unit binds the staged tree.
7. Missing `--bind=/dev/tty0 --bind=/dev/tty1`. Without these libseat
   could not acquire a VT and DRM session bring-up failed. Added.

### Guest-side (5)

8. `nix.settings.sandbox = true` (default): nspawn lacks the kernel
   namespace combo nix's sandboxed-builds path needs, so every
   `nixos-rebuild switch` from inside the guest aborted before
   activation. Set `false` declaratively.
9. `services.greetd`: greetd's PAM stack pulls `pam_systemd.so` which
   fails to dlopen inside nspawn ("failed to map segment from shared
   object"). Replaced with a bare `rocknix-sway-kiosk.service` that
   runs sway directly.
10. `WLR_LIBINPUT_NO_DEVICES=0`: under nspawn with `--bind=/dev/input`
    but without udev/sysfs symlink support, libinput sees zero devices
    and aborts wlroots backend init. Set to `1`.
11. `networking.nftables.enable = true`: nftables.service inside nspawn
    fails permanently with "cache initialization failed: Operation not
    permitted" because nspawn's profile blocks the netfilter caps.
    Set both firewall and nftables `false`; trust boundary lives at
    the host under shared-netns Layer 14.
12. `rocknix-sway-kiosk.service` exited 127 immediately under
    systemd-managed TTY claim (`TTYPath=/dev/tty1` + `PAMName=""`).
    Inside nspawn there is no logind / pam_systemd, so systemd's PAM
    pre-exec stage failed silently before sway was reached. Dropped
    `TTYPath`, `StandardInput=tty`, `PAMName`. Sway / wlroots acquires
    its own VT directly via libseat as part of DRM session bring-up.
13. Same unit's `dbus-run-session: failed to execute message bus daemon
    'dbus-daemon': No such file or directory`. systemd's default
    service PATH does not include dbus. Set `path = [ dbus foot
    swaybg swaylock ]`.

(Bugs 1–5 and 7 were committed as `35cb3ed7a4`; 6 + 8–11 as `edcf7299dc`;
udev-stage as `ea492ba733`; 12–13 as `99f5fc6bb2`.)

## Live-validated capabilities

| Capability | How tested |
|---|---|
| Recovery toggle decides target | flag absent → graphical, flag present → rocknix.target |
| Guest /init relink | prep script relinked on rebuild between system-N profiles |
| Cgroup v2 unified | guest reached multi-user with the env var |
| nspawn pty alloc | no `/dev/console` clash |
| TTY binding (libseat seat0) | sway opened DRM master on FD740 |
| DRM passthrough | `[wlr] DRM device /dev/dri/card0 (msm)` |
| Mesa freedreno/turnip | EGL/GLES2 init reported FD740 device |
| Sway compositor | systemd unit active, swaybg painting DSI-2 |
| Display rotation correct | foot terminal text reads landscape |
| Audio (raw ALSA) | `speaker-test` 440 Hz tone audible |
| Input enumeration | `swaymsg -t get_inputs` lists all devices |
| Touchscreens visible | both ft5x06 controllers exposed as `type: touch` |
| Keyboard input lands | external USB-C keyboard typed into foot |
| udev-scrubbed bind | `staged ... (removed 1 hidden entries)` |
| Network shared-netns | wlan0 + tailscale0 reachable from guest |
| Cold-boot autostart | rebooted Thor, full pipeline came up unattended |

## Known open issues (deferred)

* `swaymsg exec` silently fails on `execlp("/bin/sh", ...)` inside
  nspawn even though `/bin/sh` resolves and works from every other
  context. Workaround: launch desired clients as separate systemd
  units that inherit `WAYLAND_DISPLAY`. Tracked separately.
* InputPlumber's `Default` profile passes the AYN gamepad through as
  `event8` only (XInput-style joystick). wlroots ignores joystick
  devices, so gamepad button presses do not reach Wayland clients.
  Switch to a profile that maps gamepad → keyboard if desired.
* `nftables.service` and `sshd.socket` inside the guest are still
  reported as failed units (cosmetic). nftables is intentionally
  disabled now; sshd port conflict needs Layer-12 rework.

## Iteration tips

* `/etc` inside the guest rootfs is squashfs read-only on ROCKNIX, but
  `/storage/machines/rocknix-guest/etc/nixos/` is the writable nix
  config. Edit there, then run `nixos-rebuild switch --flake
  .#rocknix-guest --option sandbox false` from inside the guest.
* Drop-ins go under `/storage/.config/system.d/<unit>.d/` (host) or
  `/run/systemd/system/<unit>.d/` (guest tmpfs). The shipped `/usr/lib`
  units are squashfs RO.
* Patched scripts during a live spike can be staged at
  `/storage/.cache/<name>` and pointed at via an `ExecStartPre=` drop-in
  override, so you don't need a re-flash to test fixes to the
  on-image `/usr/bin/<name>`.
* `nsenter -t $GUEST_PID -m -u -i -n -p -r -w /usr/bin/env -i
  PATH=/run/current-system/sw/bin:/run/current-system/systemd/bin <cmd>`
  enters the guest from the host. ROCKNIX `nsenter` is busybox, so
  no `--all`.

## Build / fast-iter notes

* Build #25585704921 was triggered against `edcf7299dc` (the first six
  fixes only). The udev-stage and sway-kiosk fixes (`ea492ba733`,
  `99f5fc6bb2`) are NOT in that artifact.
* Future fast-iter against #25585704921 can pick up the later commits:
  the changed files are all in `IMAGE`-step territory
  (`/usr/bin/rocknix-guest-udev-stage`, the new unit drop-in shape,
  the guest profile under `/usr/lib/nix-integration/guest/`), so the
  surgical patch path documented in
  `docs/solutions/developer-experience/fast-iter-and-local-rocknix-build-2026-05-08.md`
  applies.
