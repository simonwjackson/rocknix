# ROCKNIX / Thor / Layer 14: routing two touchscreens with identical libinput identifiers

Date: 2026-05-08
Hardware: AYN Thor (SM8550) — DSI-2 (top, primary) + DSI-1 (bottom, secondary)
Branch: `feat/rocknix-layer-14-thin-host`
Outcome of the session that triggered this note: top-panel touch fully
working through Wayland; bottom-panel touch unreachable from sway.

## What we observed

Both touch controllers are kernel-visible as separate input devices:

```
/dev/input/event4  generic ft5x06 (8d)   sysfs: 1-0038 (i2c-1, 98c000.i2c)
/dev/input/event5  generic ft5x06 (8d)   sysfs: 4-0038 (i2c-4, a90000.i2c)
```

`libinput debug-events` from the host enumerates them as separate
devices and emits multitouch streams from each. End-to-end Wayland
testing confirms top-panel taps reach `wl_touch` events on clients.

But sway (via wlroots/libinput) builds device identifiers as
`vendor:product:name`:

```
$ swaymsg -t get_inputs | grep ft5
"identifier": "0:0:generic_ft5x06_(8d)",
"identifier": "0:0:generic_ft5x06_(8d)",
```

Both panels collide on identifier `0:0:generic_ft5x06_(8d)`. Sway
treats this as one logical device. There is no per-instance disambiguation
in sway 1.11 and no syntax to address an input by sysfs path or device
node. Without distinct identifiers, `swaymsg input <id> map_to_output
<output>` cannot be used to route event4 → DSI-1 separately from
event5 → DSI-2.

Coarse workaround that *does* work and is what we ship today:

```
input type:touch map_to_output DSI-2
```

This locks all touch sources to the top panel. Top-screen taps land
on Wayland clients perfectly. Bottom-screen taps fire libinput events
but are silently dropped at the wlroots routing stage.

## Why this is a real limitation, not a bug

* `EVIOCGNAME` returns the kernel-side input device name. Both ft5x06
  controllers report `"generic ft5x06 (8d)"` because the driver derives
  the name from a chip-revision detection step, not from devicetree.
* `vendor`/`product` are zero because i2c devices don't have USB-style
  IDs and the driver doesn't synthesize them from DT.
* libinput exposes `udev_device` properties, but wlroots' libinput
  backend does **not** propagate them into sway's identifier string.
* sway's identifier grammar is `vendor:product:name` with no escape
  for path or sysname. There's no `[N]` index suffix in sway 1.11.

So even if everything *upstream* of sway is fine (kernel + udev + libinput
all see two distinct devices), sway's IPC surface only exposes one.

## Three viable fixes, ranked

### 1. Kernel patch: honour DT `input-name` property in edt-ft5x06

The cleanest fix and the one we'd ship for production. Add a small
hook to `drivers/input/touchscreen/edt-ft5x06.c`:

```c
if (of_property_read_string(client->dev.of_node, "input-name", &name) == 0)
    input_dev->name = name;
else
    input_dev->name = ...; /* current behaviour */
```

Then in `qcs8550-ayn-thor.dts`:

```dts
&i2c1 {
    touch@38 {
        compatible = "edt,edt-ft5x06";
        ...
        input-name = "ft5x06-bottom";
    };
};
&i2c4 {
    touch@38 {
        compatible = "edt,edt-ft5x06";
        ...
        input-name = "ft5x06-top";
    };
};
```

After rebuild, `swaymsg -t get_inputs` shows
`0:0:ft5x06-top` and `0:0:ft5x06-bottom` and we map per-device:

```
input "0:0:ft5x06-top"    map_to_output DSI-2
input "0:0:ft5x06-bottom" map_to_output DSI-1
```

Cost: requires a kernel rebuild + DT edit. Aligns with how upstream
linux input drivers already handle multi-instance naming in other
contexts.

### 2. Patch sway/wlroots to expose path-based identifiers

Either:
* sway PR adding `path:` identifier syntax to sway-input(5), or
* a wlroots PR appending sysname / by-path suffix to the libinput
  identifier when (vendor, product, name) collides.

Cost: out-of-tree compositor patches. Maintenance burden. Only useful
if upstream accepts.

### 3. Use a different compositor with multi-touchscreen support

KDE Plasma Mobile and gnome-shell route touch by output via
`org.freedesktop.UPower.PowerProfiles`-adjacent extensions on
`KDE_OUTPUT` udev tags. cage might also work. Out of scope for the
ROCKNIX Layer 14 thin-host design which is sway-pinned.

## Decision (current)

Ship the kernel patch (Fix 1) when ready. Until then, configure sway
with `input type:touch map_to_output DSI-2` so the top panel works
end-to-end and bottom-panel taps are silently ignored rather than
landing on the wrong surface.

The legacy ROCKNIX UI does not use the bottom panel for input either,
so we are not regressing user-visible behaviour.

## Implementation tracking

* `projects/ROCKNIX/packages/tools/nix-integration/guest/profiles/main-space.nix`
  → bake `input type:touch map_to_output DSI-2` into `/etc/sway/config`.
* Future kernel-patch task: search ROCKNIX kernel tree for
  `edt-ft5x06.c` (or whichever ft5x06 driver applies) and add the
  `input-name` DT hook.
* Future DT task: edit `qcs8550-ayn-thor.dts` to set distinct
  `input-name` per touch controller node.

## Test matrix to reach 'done'

| Test | Pass criteria |
|---|---|
| `swaymsg -t get_inputs` shows two distinct identifiers | `ft5x06-top` and `ft5x06-bottom` |
| Top-screen tap reaches `wl_touch` on a DSI-2 client | down + motion + up events |
| Bottom-screen tap reaches `wl_touch` on a DSI-1 client | down + motion + up events |
| Tapping top while DSI-1 client focused does NOT swallow events | DSI-2 client still focused after |
| Multi-finger across both panels works simultaneously | trackslot IDs unique per device |
