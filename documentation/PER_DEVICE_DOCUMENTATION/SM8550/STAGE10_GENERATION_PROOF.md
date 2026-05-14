# Stage 10 SM8550 generation switch proof

This runbook validates the Stage 10 proof on an explicit SM8550 target: an
off-device NixOS guest generation can be imported into the persistent guest
store, selected as the canonical guest system, booted, audited, and rolled back
to the original generation without using host product UX.

## Scope

This proof is intentionally narrow:

- Target device: an explicit supported SM8550 profile (`thor` or `odin2portal`).
- Off-device build output: an explicit per-device proof output, e.g.
  `nixosConfigurations.rocknix-guest-stage10-proof-thor.config.system.build.toplevel`
  or `nixosConfigurations.rocknix-guest-stage10-proof-odin2portal.config.system.build.toplevel`.
- Import mode: requires a healthy running guest generation A.
- Profile switch: updates only `/nix/var/nix/profiles/per-user/root/rocknix-guest-system`; `/nix/var/nix/profiles/system` is retired as a host-recognized boot authority.
- Recovery: manual host SSH/recovery only. There is no automatic rollback.

Device-generic proof, offline host-side import, arbitrary in-guest
`nixos-rebuild switch`, and legacy profile retirement are follow-up work.

## Required proof marker

Generation B must include a harmless marker owned by the NixOS guest generation:

```text
/etc/rocknix-stage10-proof-marker
```

The exact contents are not important, but they should identify the build/source
well enough to distinguish B from A in audit output. The marker must live in the
B generation closure, not as a hand-copied mutable `/storage` file.

## Expected states

Capture the generation state at each boundary with
`rocknix-guest-activation-audit`.

| State | Expected evidence |
|-------|-------------------|
| Clean A | selected = running = A; no B proof marker required |
| Imported B | B toplevel exists in the guest store and import provenance names the explicit target (`thor` or `odin2portal`) |
| Selected B, not restarted | selected = B; running may still be A |
| Booted B | selected = running = B; B proof marker visible |
| Selected A, not restarted | selected = A; running may still be B |
| Restored A | selected = running = A; host and guest failed units remain clean |

Applied marker files such as `/etc/rocknix-guest-revision` and
`/etc/rocknix-guest-system-path` are corroborating evidence only during this
manual proof. The selected profile plus live `/run/current-system` are
authoritative.

## Promotion hold lifecycle

Before switching generations, create the manual-generation hold file:

```text
/storage/.guest/rocknix-guest-manual-generation-hold
```

While this file exists, `rocknix-guest-promote` exits without repairing drift,
building, writing profile state, writing marker state, or restarting the guest.
The switch helper also stops or waits for an already-running
`rocknix-guest-promote.service` before changing profiles.

Remove the hold only after A has been restored and audited. A stale hold prevents
normal image-driven guest promotion, so live smoke and soak report it visibly.

## Recovery if B does not boot

If B fails before guest userspace is usable:

1. Keep or regain host SSH using the existing recovery paths:
   `/flash/rocknix.no-nspawn`, `rocknix.safe=1`, or the still-running host SSH
   path if available.
2. Use the recorded generation A from
   `/storage/.guest/rocknix-guest-generation-switch-a`.
3. Restore profiles with `rocknix-guest-generation-switch --restore`.
4. Ensure `rocknix-guest.service` failed/start-limit state is reset before
   restarting A. The switch helper performs this reset as part of restore.
5. Reboot or restart the guest and run `rocknix-guest-activation-audit` again.

Do not create an automatic recovery flag, do not reboot automatically, and do not
fall back to host product UX as part of this proof.

## Safety invariants

The proof must preserve the Stage 9 substrate envelope:

- host root `/nix` remains retired;
- host SSH/recovery remains available;
- no full `/dev` bind is introduced;
- no broad `DeviceAllow=block-*` class is introduced;
- `/storage/.guest` remains the only host/guest control seam;
- host app/product storage such as `/storage/roms`, Cemu config, MangoHud config,
  and `.local` remains unbound from the host.
