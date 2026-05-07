# ROCKNIX declarative modules

This directory contains the image-owned Layer 13 module authoring kit.

ROCKNIX host modules are Nix modules evaluated with `lib.evalModules`, but
they do not mutate the ROCKNIX base OS directly. Evaluation emits a small
activation manifest consumed by `nixctl module apply`, which delegates to
existing storage-scoped layers:

- Layer 6 for `/storage/bin` and `/storage/.config/profile.d` files
- Layer 11 for one-shot guest-backed bridges
- Layer 12 for key-only guest SSH metadata on port `2222`

Editable module workspaces should live under:

```text
/storage/.config/nix-integration/modules/host
```

Start with:

```sh
nixctl module init
nixctl module preflight
nixctl module apply
nixctl module status
nixctl module deactivate
```

Example module:

```nix
{ pkgs, ... }:

let
  hello = pkgs.writeShellScript "rocknix-module-hello" ''
    echo rocknix-module-hello
  '';
in {
  rocknix.files.bin.rocknix-module-hello.source = hello;
  rocknix.files.bin.rocknix-module-hello.mode = "0755";

  rocknix.guest.ssh.enable = true;
  rocknix.guest.ssh.port = 2222;
  rocknix.guest.ssh.authorizedKeys = "/storage/.ssh/authorized_keys";
}
```

## Boundaries

Host modules must stay storage-scoped. They must not manage `/usr`, `/flash`,
`/boot`, host `/etc`, host SSH configuration, ROMs, saves, Steam/FEX state, or
package-managed ROCKNIX services.

Guest modules are separate: they are real NixOS modules under the guest flake
and are applied by rebuilding/importing the Layer 10b rootfs explicitly.
