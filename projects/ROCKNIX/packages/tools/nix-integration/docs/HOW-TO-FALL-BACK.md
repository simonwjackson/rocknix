# HOW TO FALL BACK

This file ships to `/flash/HOW-TO-FALL-BACK.md` on every ROCKNIX
THIN_HOST=yes image. It is readable from a card reader on another
machine without booting the device.

## What this image is

This is a `THIN_HOST=yes` image. Default boot reaches `rocknix-graphical.target`,
which is the Layer 14 Nix main-space (a systemd-nspawn guest that owns the
display, audio, Bluetooth, input, and Wi-Fi from inside its own NixOS
config).

A `THIN_HOST=no` image is the regular ROCKNIX image — sway + Emulationstation
running directly on the host. You can identify which one you have:

```text
ssh root@thor 'systemctl get-default; ls /flash/HOW-TO-FALL-BACK.md 2>/dev/null'
```

`rocknix-graphical.target` + the file present → THIN_HOST=yes.
`graphical.target` + the file absent → THIN_HOST=no.

## Symptoms of a guest failure

- Black screen for more than 30 seconds after boot
- No SSH on `root@thor:22`
- Lid open / power button does nothing visible
- Display shows the boot splash and never advances

If host SSH still works but the display is blank, the guest may be
crashing while the host's recovery toggle is fine — try the toggle
first.

## Recovery (no SSH, no card reader)

Hold the **POWER + VOLUME-UP** buttons for 8 seconds while booting (TODO:
verify the exact device key combo per device). This sets
`rocknix.safe=1` on the kernel cmdline for one boot only. The boot
will land in the legacy ROCKNIX UI (essway). The override clears on
next reboot — do whatever fix you need, then power-cycle normally.

## Recovery (card reader, no booted device)

1. Power off the device.
2. Eject the storage card (or open the case to reach the on-board
   eMMC if soldered).
3. Mount the FAT/EXFAT `/flash` partition on another machine.
4. Create the flag file:

   ```text
   touch /path/to/flash/rocknix.no-nspawn
   ```

5. Eject and reinstall.
6. Power on. Boot lands in legacy ROCKNIX UI.

The flag file is **sticky** — it persists across reboots until you
explicitly remove it. This is intentional: a stuck "I'm in recovery
mode" state should require a conscious action to exit.

## Recovery (booted but guest crashing repeatedly)

1. SSH to the device: `ssh root@thor`
2. Confirm host SSH works: `whoami` should return `root`.
3. `touch /flash/rocknix.no-nspawn`
4. `reboot`
5. Boot lands in legacy ROCKNIX UI.

## Confirming you are in recovery mode

```text
systemctl get-default                       # graphical.target (not rocknix-graphical.target)
systemctl is-active rocknix-guest-v2        # inactive
systemctl is-active sway                    # active
systemctl is-active essway                  # active
systemctl status rocknix-recovery-toggle    # shows the reasons it triggered
```

## Exiting recovery mode

```text
rm /flash/rocknix.no-nspawn
reboot
```

If you used the `rocknix.safe=1` cmdline path, exiting is automatic:
just `reboot` without the button-hold.

## Where to find logs after a failure

- `journalctl -b -1`   — previous boot's journal
- `/var/log/rocknix-host-reclaim.log` — reclaim contract decisions
- `/var/log/layer14-soak*.log` — soak harness output (if running)
- `/var/log/boot.log`  — ROCKNIX autostart trace (legacy host UI)
- `/storage/.cache/iwd/*.log` — Wi-Fi association history

## Re-flashing

If recovery does not get you back to a working device, the image is
flashable from the standard ROCKNIX recovery flow (fastboot / SD-card
reflash) without losing `/storage`. Your ROMs, saves, and configs
live on `/storage` and are not touched by an image flash.
