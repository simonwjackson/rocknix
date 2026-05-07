# Layer 12 opt-in guest SSH contract

Layer 12 exposes the first persistent Nix-managed guest service: OpenSSH inside the Layer 10b bootable guest. ROCKNIX remains the host OS and owns boot, kernel, firmware, host SSH recovery, Sway/EmulationStation, Steam/FEX, image updates, and package-managed services.

Layer 12 is valid only after Layer 10b bootable start/stop has been hardware-validated on the target device. Building a Layer 12 image before Layer 10b validation is allowed for pipeline efficiency, but Go/No-Go evidence must still be collected in order.

## Responsibilities

Layer 12 may:

- configure one explicit service: guest SSH
- expose guest SSH on an alternate host port, defaulting to `2222`
- require an operator-provided authorized-keys file
- record service metadata under `/storage/.config/nix-integration/layer12`
- extend the Layer 10 disabled guest unit with the minimum nspawn flags needed for configured SSH exposure
- report Layer 12 status through `nixctl guest service status`, `nixctl status`, and `nix-doctor`
- remove only Layer 12-owned service metadata

Layer 12 must not:

- replace or modify host SSH
- bind guest SSH to host port `22`
- enable password authentication, keyboard-interactive authentication, or default credentials
- ship reusable authorized keys in the image
- enable guest autostart
- make the guest a recovery dependency for SSH, Sway, EmulationStation, Steam/FEX, update, or rollback
- expose generic persistent service management beyond SSH
- pass through graphics, audio, `/dev/input`, Wayland/Sway sockets, ROMs, saves, Steam state, FEX state, or browser profiles
- mutate `/usr`, `/flash`, `/boot`, host `/etc`, host SSH config, firmware, kernel modules, or package-managed services at runtime

## Default paths

Default Layer 12 metadata root:

```text
/storage/.config/nix-integration/layer12
```

Default guest root dependency:

```text
/storage/machines/rocknix-guest
```

Default host port for guest SSH:

```text
2222
```

Default guest authorized-keys mount target:

```text
/etc/ssh/authorized_keys.d/root
```

## Service definition model

A configured SSH service must have inspectable metadata that records at least:

```text
service=ssh
state=configured
port=2222
authorized_keys=/storage/.ssh/authorized_keys
authorized_keys_sha256=<sha256>
guest_root=/storage/machines/rocknix-guest
layer10_provenance=/storage/.config/nix-integration/layer10/rootfs-provenance
```

The authorized-keys file is an operator-provided input. The image must not contain a shared key or a default credential. Password login remains unavailable because the guest root password is locked and OpenSSH password authentication is disabled.

## Host SSH boundary

Host SSH on port `22` is the recovery plane. Layer 12 must refuse port `22` at command validation time and `nix-doctor` must report it as a failure if unsafe metadata is found.

The expected operator flow is:

```text
nixctl guest service enable ssh --port 2222 --authorized-keys /storage/.ssh/authorized_keys
nixctl guest start
ssh -p 2222 root@thor /usr/bin/nix --version
nixctl guest stop
```

If guest SSH fails, the rollback path remains host SSH:

```text
ssh root@thor
nixctl guest stop
nixctl guest service disable ssh
```

## Layer 10 dependency

Layer 12 depends on Layer 10b bootable mode. Service preflight must refuse unsupported, proof-only, invalid, failed, or missing-provenance guest roots. Layer 12 must not make proof roots look service-capable.

The generated Layer 10 unit must use private networking while Layer 12 is unconfigured, so a generic bootable guest cannot collide with host networking. When Layer 12 SSH metadata is configured, the guest uses the shared host network namespace and guest sshd listens directly on the fixed alternate port `2222`; this avoids depending on `systemd-nspawn --port` NAT, which is unavailable on SM8550 images without the legacy iptables NAT table. Layer 12 may modify the generated disabled Layer 10 unit only to remove private networking for this direct alternate-port SSH mode and add the authorized-keys bind mount. The generated unit remains manually started and must not call `systemctl enable`.

## Go / No-Go rule

Layer 12 guest SSH is Go only if hardware validation proves:

- Layer 10b bootable start/stop was validated first
- image install does not enable guest SSH by default
- `nixctl guest service enable ssh --port 2222 --authorized-keys ...` records explicit metadata
- host port `22` is never bound or modified by Layer 12
- password authentication is unavailable
- `ssh -p 2222 root@thor /usr/bin/nix --version` reaches the guest and returns the guest Nix version
- `nixctl guest stop` removes the live guest SSH exposure
- reboot does not autostart the guest or guest SSH
- host `ssh root@thor` remains healthy throughout
- `nix-doctor --offline` reports Layer 12 state and guardrails clearly

Any host SSH takeover, port `22` binding, password login, default credential, guest autostart, forbidden passthrough dependency, unsafe cleanup boundary, or residual guest process after stop is a No-Go for Layer 12 until documented and fixed.
