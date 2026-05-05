---
title: ROCKNIX profile.d ordering can clobber late PATH integrations
last_updated: 2026-05-05
date: 2026-05-05
category: runtime-errors
module: ROCKNIX nix-integration
problem_type: runtime_error
component: tooling
symptoms:
  - Real Nix installed successfully, but `command -v nix` returned nothing in shells that sourced `/etc/profile`.
  - `nixctl status` reported Layer 4 installed while shell PATH resolution still showed no `nix` on PATH.
  - `nix-doctor` warned that profile.d might not be sourced, even though `/etc/profile.d/085-nix-integration.conf` existed in the image.
root_cause: config_error
resolution_type: config_change
severity: medium
related_components:
  - profile.d
  - busybox shell environment
  - nixctl
  - nix-doctor
tags: [rocknix, nix, profile-d, path, busybox, sm8550, layer-4]
---

# ROCKNIX profile.d ordering can clobber late PATH integrations

## Problem

After installing the Layer 4 real-Nix build on `thor`, real Nix itself worked by absolute path, but the expected shell integration did not: `nix` was not automatically available on `$PATH` after sourcing `/etc/profile`. This made the image-side PATH work look broken even though `/nix/var/nix/profiles/default/bin/nix` and `/storage/.nix-profile/bin/nix` were both valid.

## Symptoms

- The update to `OS_VERSION="20260505"` succeeded and shipped `/usr/bin/nixctl`, `/usr/bin/nix-doctor`, and `/etc/profile.d/085-nix-integration.conf`.
- Layer 3 was healthy:

  ```sh
  systemctl is-active nix-storage-setup.service nix.mount
  # active
  # active

  cat /proc/mounts | grep ' /nix '
  # /dev/sda19 /nix ext4 rw,noatime 0 0
  ```

- Layer 4 installed successfully:

  ```sh
  /nix/var/nix/profiles/default/bin/nix --version
  # nix (Nix) 2.34.7
  ```

- But a profile-sourced shell still could not find `nix`:

  ```sh
  . /etc/profile
  command -v nix
  # no output

  nix --version
  # sh: nix: command not found
  ```

- `nixctl status` showed the install was real but PATH resolution was not:

  ```text
  Layer 4 (real Nix) status
  ------------------------
    installed: yes
    binary:    /nix/var/nix/profiles/default/bin/nix
    version:   nix (Nix) 2.34.7
    sandbox:   true

  Shell PATH resolution
  ---------------------
    which nix -> no 'nix' on $PATH
  ```

## What Didn't Work

- **Validating only the snippet directly.** Sourcing `/etc/profile.d/085-nix-integration.conf` by itself produced the desired PATH, which made the snippet look correct in isolation:

  ```sh
  . /etc/profile.d/085-nix-integration.conf
  echo "$PATH"
  # /storage/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/storage/bin:...
  ```

  That missed the later profile scripts that run during a real `/etc/profile` load.

- **Assuming profile.d files only append to the environment.** ROCKNIX's profile stack includes files that reset core variables. In particular, `098-busybox` exports a new `PATH`, so earlier PATH edits are not durable.

- **Treating `/storage/.nix-profile/bin/nix` as unexpected.** After a successful single-user install, `${HOME}/.nix-profile` points at the default profile. That means `/storage/.nix-profile/bin/nix` is a valid real-Nix path, not an anomaly.

## Solution

Rename the Nix integration profile snippet so it sorts after ROCKNIX's busybox profile reset:

```text
projects/ROCKNIX/packages/tools/nix-integration/profile.d/
  085-nix-integration.conf  ->  998-nix-integration.conf
```

The snippet contents did not need to change. The fix is ordering: `998-nix-integration.conf` runs after `/etc/profile.d/098-busybox`, restoring the intended precedence:

```sh
${HOME}/.nix-profile/bin
/nix/var/nix/profiles/default/bin
/storage/bin
/usr/bin:/usr/sbin
```

Add a static check that encodes the ordering requirement:

```sh
PROFILE_SNIPPET="998-nix-integration.conf"
[ -f "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" ] || fail "missing profile integration"
sh -n "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile integration syntax failed"
grep -q '/nix/var/nix/profiles/default/bin' "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile.d missing Layer 4 PATH prefix (/nix/var/nix/profiles/default/bin)"
grep -q '\.nix-profile/bin' "${PKG_DIR}/profile.d/${PROFILE_SNIPPET}" || fail "profile.d missing Layer 5 PATH prefix (~/.nix-profile/bin)"

# ROCKNIX's /etc/profile.d/098-busybox resets PATH. The Nix profile snippet
# must sort after it, or the Layer 4/5 PATH prefixes are clobbered in login
# shells.
case "${PROFILE_SNIPPET}" in
  99*|[1-9][0-9][0-9]*) ;;
  *) fail "profile snippet must sort after 098-busybox so PATH is not reset later: ${PROFILE_SNIPPET}" ;;
esac
```

Patch `nix-doctor` to accept both canonical real-Nix paths:

```sh
case "${path_nix}" in
  "${NIX_DEFAULT_PROFILE_BIN}/nix"|"${NIX_USER_PROFILE_LINK}/bin/nix")
    ok "\$PATH 'nix' resolves to real nix: ${path_nix}"
    ;;
  "${NIX_WRAPPER_DIR}/nix")
    warn "\$PATH 'nix' resolves to portable wrapper (${path_nix}); open a fresh shell or run 'hash -r'"
    ;;
  *)
    warn "\$PATH 'nix' resolves to unexpected path: ${path_nix}"
    ;;
esac
```

For the already-flashed device, use a storage-side runtime hotfix because `/etc` is read-only:

```sh
cat >/storage/.config/profile.d/998-nix-integration <<'EOF'
if [ -z "${NIX_PORTABLE_DIR:-}" ]; then
  export NIX_PORTABLE_DIR="/storage/apps/nix-portable"
fi
if [ -z "${NP_LOCATION:-}" ]; then
  export NP_LOCATION="/storage"
fi
if [ -z "${NP_RUNTIME:-}" ]; then
  export NP_RUNTIME="proot"
fi

case ":${PATH:-}:" in
  *:/storage/bin:*) ;;
  *) export PATH="/storage/bin:${PATH:-}" ;;
esac
case ":${PATH:-}:" in
  *:/nix/var/nix/profiles/default/bin:*) ;;
  *) export PATH="/nix/var/nix/profiles/default/bin:${PATH:-}" ;;
esac
if [ -n "${HOME:-}" ]; then
  case ":${PATH:-}:" in
    *:"${HOME}/.nix-profile/bin":*) ;;
    *) export PATH="${HOME}/.nix-profile/bin:${PATH:-}" ;;
  esac
fi
EOF
chmod 0644 /storage/.config/profile.d/998-nix-integration
```

Validation after the runtime hotfix:

```sh
. /etc/profile
command -v nix
# /storage/.nix-profile/bin/nix

nix --version
# nix (Nix) 2.34.7

nix-doctor --offline
# ...
# OK: $PATH 'nix' resolves to real nix: /storage/.nix-profile/bin/nix
# nix-doctor: passed with 1 warning(s)
```

## Why This Works

`/etc/profile` sources `/etc/profile.d/*` in lexical order, then `/storage/.config/profile.d/*`. During tracing, `085-nix-integration.conf` correctly prepended the Nix paths, but later `098-busybox` ran this reset:

```sh
export PATH=/usr/bin:/usr/sbin
```

That removed every earlier PATH addition, including `/storage/bin`, `/nix/var/nix/profiles/default/bin`, and `${HOME}/.nix-profile/bin`.

Moving the image-provided snippet to `998-nix-integration.conf` makes it run after `098-busybox`, so its PATH additions are final unless a later file intentionally changes them. The storage-side hotfix works for the same reason: `/storage/.config/profile.d/*` is sourced after `/etc/profile.d/*`, so it can repair PATH without rebuilding the read-only image.

`nix-doctor` also needed to reflect the intended model. Once Layer 4 installs, `${HOME}/.nix-profile` points at `/nix/var/nix/profiles/per-user/root/profile`, so `${HOME}/.nix-profile/bin/nix` is simply the user-profile symlink path to real Nix. It should be reported as OK.

## Prevention

- When adding ROCKNIX profile snippets that modify PATH, inspect the full profile order, not just the new file:

  ```sh
  ls /etc/profile.d /storage/.config/profile.d
  ```

- Validate with the complete profile load:

  ```sh
  cat >/tmp/path-test.sh <<'EOF'
  set -x
  echo "before:$PATH HOME=$HOME SHELL=$SHELL"
  . /etc/profile
  echo "after:$PATH HOME=$HOME SHELL=$SHELL"
  command -v nix || true
  nix --version || true
  EOF
  /bin/sh /tmp/path-test.sh
  ```

- Keep the static guard that requires the Nix snippet to sort after `098-busybox`. A presence check for PATH entries is not enough; ordering is part of the contract.

- In post-image validation, test both absolute-path functionality and shell integration:

  ```sh
  /nix/var/nix/profiles/default/bin/nix --version
  . /etc/profile
  command -v nix
  nix --version
  nix-doctor --offline
  ```

- `nix-doctor` should treat both `/nix/var/nix/profiles/default/bin/nix` and `${HOME}/.nix-profile/bin/nix` as real-Nix success paths.

## Related Issues

- `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` — deployment procedure and Nix-integration validation checklist for custom SM8550 builds.
- `documentation/PER_DEVICE_DOCUMENTATION/SM8550/NIX_EXPERIMENT.md` — operator-facing Nix layer documentation; references the final `998-nix-integration.conf` filename after this fix.
- Commits: `a2ab2e7781 fix(nix): source PATH integration after ROCKNIX busybox profile reset`, `fb27a9f38e fix(nix): accept user profile nix path in nix-doctor`.
