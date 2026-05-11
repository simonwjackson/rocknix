# Layer 13 declarative modules contract

Layer 13 adds a NixOS-like declarative authoring layer on top of the existing ROCKNIX Nix integration layers. It does not turn ROCKNIX into NixOS. ROCKNIX remains the host OS and owns boot, kernel, firmware, host SSH recovery, Sway/EmulationStation, Steam/FEX, image updates, and package-managed services.

Layer 13 has two module domains:

1. **Guest modules** are real NixOS modules imported into the Layer 10b guest flake. They shape the bootable guest rootfs that is later imported through Layer 10 provenance tracking.
2. **ROCKNIX host modules** are storage-scoped modules evaluated with the Nix module system. They compile to existing safe activation artifacts and are applied through Layer 6, Layer 11, and Layer 12 commands.

## Responsibilities

Layer 13 may:

- evaluate storage-local module configs with typed Nix options
- create an editable module workspace under `/storage/.config/nix-integration/modules`
- activate module-owned wrappers and profile snippets under `/storage/bin` and `/storage/.config/profile.d`
- install module-owned one-shot bridges under `/storage/bin` through Layer 11
- configure Layer 12 guest SSH metadata for the fixed validated port `2222`
- create a guest module workspace and build/import bootable guest rootfs artifacts through Layer 10
- record module metadata under `/storage/.config/nix-integration/layer13`
- report module state through `nixctl module status`, `nixctl status`, and `nix-doctor`

Layer 13 must not:

- mutate `/usr`, `/flash`, `/boot`, host `/etc`, host SSH config, firmware, kernel modules, or package-managed services at runtime
- replace or modify ROCKNIX host SSH on port `22`
- enable guest autostart or make the guest a boot dependency
- expose guest SSH by default
- permit password auth, keyboard-interactive auth, default credentials, or shipped reusable authorized keys
- pass through graphics, audio, `/dev/input`, Wayland/Sway sockets, ROMs, saves, Steam state, FEX state, or browser profiles by default
- bypass Layer 6/10/11/12 guardrails when applying module output

## Host module application model

Host modules are authoring input, not direct mutation scripts. Evaluation produces a shell-friendly activation manifest. `nixctl module apply` then delegates to existing layer commands:

- file outputs become a Layer 6 activation bundle using a Layer 13-owned Layer 6 state directory
- bridge outputs become Layer 11 bridges using a Layer 13-owned Layer 11 state directory
- guest SSH output becomes Layer 12 metadata through `nixctl guest service enable ssh`

This keeps path validation, ownership tracking, conflict refusal, and rollback behavior centralized in the layers that already own those surfaces.

## Guest module application model

Guest modules are NixOS modules. A storage-local guest module workspace may import the image-provided guest modules and profiles, build a rootfs tarball with Nix, and import it through:

```text
nixctl guest import --bootable <artifact>
```

Building a guest module rootfs must not replace the active guest root automatically. Import is explicit so failed builds cannot destroy a known-good guest.

## Default paths

Default host module workspace:

```text
/storage/.config/nix-integration/modules/host
```

Default guest module workspace:

```text
/storage/.config/nix-integration/modules/guest
```

Default Layer 13 state:

```text
/storage/.config/nix-integration/layer13
```

Image-owned module kit:

```text
/usr/lib/nix-integration/modules
/usr/lib/nix-integration/guest
```

## Go / No-Go rule

Layer 13 is Go on SM8550 only if hardware validation proves, in order:

1. Layer 10b bootable start/stop is Go.
2. Layer 12 guest SSH is Go.
3. Host module preflight/apply/deactivate works without touching host system paths.
4. Guest module workspace/build/import preserves Layer 10 provenance and manual lifecycle.
5. `nix-doctor --offline` reports module state and drift clearly.
6. Reboot does not autostart the guest or guest SSH.
7. Host `ssh root@thor` on port `22` remains healthy throughout.

Any host SSH takeover, port `22` binding, password login, default credential, guest autostart, forbidden passthrough dependency, unsafe cleanup boundary, non-owned file overwrite, or residual guest process after stop is a No-Go for Layer 13 until documented and fixed.
