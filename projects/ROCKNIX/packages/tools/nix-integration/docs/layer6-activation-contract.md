# Layer 6 activation contract

Layer 6 manages a narrow ROCKNIX user environment by activating files from a Nix-built bundle onto explicitly allowed storage surfaces. It does not install Nix packages, replace ROCKNIX services, or manage broad dotfile trees.

## Bundle shape

A bundle is a directory with a `manifest` file and payload files. The manifest is line-oriented and busybox-shell friendly:

```text
# surface|name|source|mode
bin|rocknix-layer6-smoke|files/bin/rocknix-layer6-smoke|0755
profile.d|999-rocknix-layer6-smoke|files/profile.d/999-rocknix-layer6-smoke|0644
```

Fields:

- `surface` — one of the supported activation surfaces.
- `name` — basename to create on that surface. It must not contain `/`, `..`, or shell metacharacters.
- `source` — relative path inside the bundle.
- `mode` — four-digit octal mode applied to the activated file.

The activation engine computes the runtime target from `surface` and `name`; manifests do not provide arbitrary absolute target paths.

## Initial allowed surfaces

| Surface | Runtime target | Initial support | Notes |
|---|---|---:|---|
| `bin` | `/storage/bin/<name>` | yes | Storage-local wrappers already on `$PATH`. |
| `profile.d` | `/storage/.config/profile.d/<name>` | yes | Sourced after `/etc/profile.d`; snippets must account for lexical order. |

## Deferred surfaces

| Surface | Status | Reason |
|---|---|---|
| `/storage/.config/autostart` / `autostart.sh` | deferred | Can affect UI startup and recovery. |
| `/storage/.config/system.d` | deferred | Service ordering and boot failure risk require a separate opt-in unit. |

## Forbidden surfaces

Layer 6 must never activate files under:

- `/usr`
- `/flash`
- `/boot`
- kernel module directories
- firmware directories
- ROCKNIX package-managed system services
- EmulationStation/Sway default startup paths
- ROM, save, Steam/FEX, or browser profile data

## State and ownership

Default state lives under:

```text
/storage/.config/nix-integration/layer6/
```

State includes:

- `state` — current state: `active`, `inactive`, or `partial`.
- `active-generation` — active generation identifier when present.
- `owned-files` — target, checksum, source, mode, and generation for each owned file.
- `rollback-files` — temporary rollback metadata during activation.
- `backups/` — backups for files replaced during activation.
- `logs/` — optional activation logs.

Ownership metadata is the source of truth. Filename conventions alone do not prove ownership.

## Conflict policy

Activation refuses to overwrite an existing target unless that target is already owned by Layer 6. The first implementation has no automatic adopt or force mode.

If activation fails after changing targets, the activator must roll back changed targets when possible. If rollback cannot fully complete, it must leave state as `partial` so `nix-doctor` fails and points the operator at rollback/deactivation.

## Layer 4 uninstall interaction

Layer 6 bundles may activate wrappers or snippets that reference `/nix/store` paths. `nixctl uninstall` removes the real Nix store, so it must detect active Layer 6 state and refuse or safely deactivate before removing Layer 4 state.
