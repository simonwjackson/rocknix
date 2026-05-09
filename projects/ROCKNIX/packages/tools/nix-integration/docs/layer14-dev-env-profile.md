# Layer 14 — Interactive dev-env profile

## Goal

Live in Nix space as the primary interactive system on AYN Thor. Same
Layer 14 nspawn substrate and cold-boot autostart pipeline as
`profiles/main-space.nix`, but lands in an interactive sway session
with a launcher, sane keybinds, a battery indicator, and a developer-
flavored package set — so you can launch, close, and switch between
apps without an SSH tether.

The dev-env profile is the prerequisite environment for iterating on
Korri (and any other Nix-built UI) directly on the device.

## Sibling of `profiles/main-space.nix`

Both profiles import the same six guest modules
(`base / tools / ssh / display / audio / network`). The only material
differences are:

| Aspect | `main-space.nix` | `dev-env.nix` |
|---|---|---|
| Hostname | `rocknix-nix` | `rocknix-nix-dev` |
| Sway config | Kiosk: only `seat hide_cursor`, output config, touch routing | Adds `$mod` keybinds (Mod+Return = foot, Mod+D = fuzzel, Mod+Shift+Q = kill, workspaces, focus/move, layout toggles), swaybar with clock + battery, `exec foot` to pre-spawn one terminal |
| Extra packages | None beyond `display.nix` defaults | `fuzzel`, `git`, `htop`, `btop` |
| Kiosk service `path` | `dbus foot swaybg swaylock bashInteractive` | adds `fuzzel git coreutils sway` (sway is required so sway can `execlp("swaybar", ...)` — same PATH-lookup mechanism that the U1 fix solved for `sh`) |

Touch routing (DSI-2 default + per-device post-patch rules), output
config (DSI-2 transform 90, DSI-1 disable), and the `WLR_*` env are
copied verbatim. Both profiles produce the same kiosk *service unit
name* (`rocknix-sway-kiosk.service`) so the host-side
`rocknix-guest-v2.service` graph is identical regardless of which
profile is booted.

## Selection mechanism

`guest/flake.nix` exposes three configurations:

- `nixosConfigurations.rocknix-guest` — Layer 10b minimal (default
  closure used by the rootfs builder).
- `nixosConfigurations.rocknix-guest-main-space` — Layer 14 kiosk for
  THIN_HOST=yes flashed images.
- `nixosConfigurations.rocknix-guest-dev-env` — interactive dev-env.

The shipped image flashes with `main-space` active. The dev-env
profile is reachable at runtime via an in-guest `nixos-rebuild
switch`. There is no flag file, no cmdline knob, no host-side prep
change for this milestone — keeping the boot pipeline identical to the
main-space contract.

Persistent profile selection is **deferred** to the four-image plan
(see `docs/brainstorms/2026-05-07-002-rocknix-thin-host-nix-main-space.md`).

## Live swap procedure

Prerequisites:

- Thor is running Layer 14 (`rocknix-guest-v2.service` is `active`,
  `rocknix-sway-kiosk.service` is `active`).
- Network is up (`ssh root@thor` reachable via tailscale or LAN).
- The guest has flake source staged at `/storage/machines/rocknix-guest/etc/nixos/`. On a freshly flashed image this directory is the rootfs's `/etc/nixos/` from the closure builder, which is read-only via squashfs. To make it writable, **once per device**, copy the repo's `guest/` tree into that path so it can be edited and rebuilt:
  ```bash
  # one-time setup, from a workstation with the repo cloned
  rsync -a projects/ROCKNIX/packages/tools/nix-integration/guest/ \
        root@thor:/storage/machines/rocknix-guest/etc/nixos/
  ```

Switch to dev-env (run from a workstation):

```bash
ssh root@thor 'bash -s' <<'OUTER'
GUEST_PID=$(pgrep -P $(pgrep -f 'systemd-nspawn.*rocknix-guest' | head -1) | head -1)
nsenter -t $GUEST_PID -m -u -i -n -p -r -w /bin/sh <<'INNER'
PATH=/run/current-system/sw/bin
cd /etc/nixos
nixos-rebuild switch \
    --flake .#rocknix-guest-dev-env \
    --option sandbox false \
    --no-update-lock-file
systemctl restart rocknix-sway-kiosk.service
INNER
OUTER
```

Within ~5 s the screen swaps from the kiosk session to the dev-env
session (one foot terminal pre-spawned, status bar at the bottom, all
keybinds live). The `systemctl restart` is required because
`nixos-rebuild` only auto-restarts units whose drv changed; a config
swap that only touches `/etc/sway/config` won't trigger it on its own.

Switch back to main-space — same shape:

```bash
nixos-rebuild switch --flake .#rocknix-guest-main-space \
    --option sandbox false --no-update-lock-file
systemctl restart rocknix-sway-kiosk.service
```

The switch is **not persistent across reflash**: the next image pull
restores main-space as the default. Live swap survives reboots only if
no reflash happens (the closure is in the on-device nix store, the
generation symlink stays intact).

## Default keybinds (sway)

| Key | Action |
|---|---|
| `$mod+Return` | Launch `foot` |
| `$mod+d` | Launch `fuzzel` (search/run any binary on PATH) |
| `$mod+Shift+q` | Kill focused window |
| `$mod+Shift+e` | Exit sway (kiosk service then auto-restarts) |
| `$mod+Shift+c` | Reload sway config in place |
| `$mod+1..9` | Switch to workspace N |
| `$mod+Shift+1..9` | Move window to workspace N |
| `$mod+Left/Right/Up/Down` | Focus left/right/up/down |
| `$mod+Shift+Left/...` | Move window left/right/up/down |
| `$mod+f` | Toggle fullscreen |
| `$mod+space` | Toggle floating |
| `$mod+s` / `$mod+w` / `$mod+e` | Layout: stacking / tabbed / split-toggle |

`$mod` is `Mod4` (Super / Windows key on a standard USB keyboard).

## Status bar

`swaybar` runs at the bottom of DSI-2 with a fixed-path
`status_command` (`/nix/store/<hash>-sway-bar-status`, built by Nix as
a `writeShellScript`). The script writes one line every 5 s:

    HH:MM | bat NN%

Battery is read from `/sys/class/power_supply/battery/capacity` (Thor's
Qualcomm `pmic-glink` path); `BAT*/capacity` is the wildcard fallback.
If neither path is readable the bar displays `bat ?%` and stays alive.

The status_command is a separate Nix-built script, not an inline
multi-line shell loop, because sway's config parser strips quoting
from `status_command` values — verified live on Thor 2026-05-08 by
inspecting `swaymsg -t get_bar_config` output. As an absolute path the
script's quoting survives untouched.

## Running Korri

Korri is **not** baked into the dev-env image. From a `foot` terminal,
launch via `nix run`:

```bash
# from the published flake (network required)
nix run github:simonwjackson/korri#korri-desktop

# from a local checkout (avoids re-fetching, fast iteration)
git clone https://github.com/simonwjackson/korri /storage/code/korri
nix run /storage/code/korri#korri-desktop
```

The dev-env's `network.nix` brings up NetworkManager; the `nix daemon`
from `base.nix` lets `nix run` substitute from cache.nixos.org.

## Known limitations

- USB keyboard required. On-screen keyboard is a separate plan.
- No InputPlumber → keyboard mapping; gamepad input is not surfaced as
  keystrokes inside sway.
- `swaymsg exec` and bound keybinds spawn child processes via
  `execlp("sh", ...)`. The unit's `path` must include
  `bashInteractive` (and `sway` for the bar block). New programs added
  to the user's typical workflow may need to land in `path` if invoked
  by keybind. `nix run` from foot works because foot inherits sway's
  PATH and gives bash to the child.
- Bottom-panel touch routing (`0:0:ft5x06-bottom`) is dependent on the
  kernel patch + DT input-name properties shipping in flashed images.
  On unpatched kernels both ft5x06 controllers report identical
  identifiers and the per-device sway rules become no-ops; the
  `input type:touch map_to_output DSI-2` fallback still pins all touch
  to DSI-2.
- Live profile swap requires the flake source staged in
  `/storage/machines/rocknix-guest/etc/nixos/` (one-time setup; see
  Prerequisites above).

## Related artefacts

- Profile: `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/dev-env.nix`
- Flake: `projects/ROCKNIX/packages/tools/nix-integration/guest/flake.nix`
- Sibling profile: `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/main-space.nix`
- Layer 14 substrate: `projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-main-space-contract.md`
- Plan: `docs/plans/2026-05-08-001-feat-rocknix-interactive-dev-env-profile-plan.md`
- Prerequisite cold-boot autostart: `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md`
