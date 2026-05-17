#!/usr/bin/env bash
# shellcheck disable=SC2016
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Generate a small Nix-on-ROCK build-evidence artifact. This deliberately sits
# beside inherited ROCKNIX payload filenames rather than renaming the payloads.

set -euo pipefail

out=${1:-nix-on-rock-build-manifest.md}
artifact_root=${ARTIFACT_ROOT:-artifacts}
device=${NIX_ON_ROCK_DEVICE:-${DEVICE:-SM8550}}
status=${NIX_ON_ROCK_ARTIFACT_STATUS:-BuildProof}
intake_note=${NIX_ON_ROCK_INTAKE_NOTE:-not-reviewed}
branch=${GITHUB_REF_NAME:-$(git branch --show-current 2>/dev/null || echo unknown)}
sha=${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}
run_id=${GITHUB_RUN_ID:-unknown}
run_attempt=${GITHUB_RUN_ATTEMPT:-unknown}
repo=${GITHUB_REPOSITORY:-unknown}
package_mk=${NIX_ON_ROCK_SUBSTRATE_PACKAGE:-projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk}
sm8550_doc=documentation/PER_DEVICE_DOCUMENTATION/SM8550/README.md

extract_pkg_var() {
  var=$1
  [ -r "${package_mk}" ] || return 0
  sed -n "s/^${var}=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "${package_mk}" | sed -n '1p'
}

list_artifact_files() {
  [ -d "${artifact_root}" ] || return 0
  find "${artifact_root}" -type f | sort
}

image_files=$(list_artifact_files | grep -E '/ROCKNIX-.*\.img\.gz$|^ROCKNIX-.*\.img\.gz$' || true)
update_files=$(list_artifact_files | grep -E '/ROCKNIX-.*\.tar$|^ROCKNIX-.*\.tar$' || true)
image_sha_files=$(list_artifact_files | grep -E '/ROCKNIX-.*\.img\.gz\.sha256$|^ROCKNIX-.*\.img\.gz\.sha256$' || true)
update_sha_files=$(list_artifact_files | grep -E '/ROCKNIX-.*\.tar\.sha256$|^ROCKNIX-.*\.tar\.sha256$' || true)
count_lines() {
  [ -n "$1" ] || { echo 0; return; }
  printf '%s\n' "$1" | wc -l | tr -d ' '
}

update_tar=$(printf '%s\n' "${update_files}" | sed -n '1p')

payload_for_checksum() {
  checksum_file=$1
  checksum_payload=$(awk 'NR == 1 { print $2 }' "${checksum_file}")
  checksum_payload_base=$(basename "${checksum_payload}")
  list_artifact_files | awk -v base="${checksum_payload_base}" 'base == "" { exit } { n=split($0, parts, "/"); if (parts[n] == base) { print; exit } }'
}

validate_checksum_file() {
  checksum_file=$1
  expected_hash=$(awk 'NR == 1 { print $1 }' "${checksum_file}")
  payload_file=$(payload_for_checksum "${checksum_file}")
  [ -n "${expected_hash}" ] || { echo "checksum file ${checksum_file} has no hash" >&2; exit 1; }
  [ -n "${payload_file}" ] || { echo "checksum file ${checksum_file} has no matching payload" >&2; exit 1; }
  actual_hash=$(sha256sum "${payload_file}" | awk '{print $1}')
  if [ "${actual_hash}" != "${expected_hash}" ]; then
    echo "checksum file ${checksum_file} mismatch for ${payload_file}: ${actual_hash} != ${expected_hash}" >&2
    exit 1
  fi
}

seed_archive=$(extract_pkg_var PKG_NIX_GUEST_ROOTFS_SEED_ARCHIVE)
seed_sha256=$(extract_pkg_var PKG_NIX_GUEST_ROOTFS_SEED_SHA256)
seed_compatible=$(extract_pkg_var PKG_NIX_GUEST_ROOTFS_SEED_COMPATIBLE)
guest_rev=$(extract_pkg_var PKG_NIX_GUEST_REV)
system_bytes="unknown"
seed_payload="unknown"
seed_tar_entry=""
actual_seed_sha256="unknown"

if [ -n "${update_tar}" ] && [ -r "${update_tar}" ]; then
  system_bytes=$(tar -tvf "${update_tar}" 2>/dev/null | awk '$NF ~ /(^|\/)target\/SYSTEM$/ { print $3; exit }')
  system_bytes=${system_bytes:-unknown}
  seed_tar_entry=$(tar -tf "${update_tar}" 2>/dev/null | grep -E '(^|/)target/seed/.*\.tar\.zst$' | sed -n '1p' || true)
  if [ -n "${seed_tar_entry}" ]; then
    seed_payload=$(basename "${seed_tar_entry}")
  fi
fi

case "${status}" in
  BuildProof|DeviceAccepted|ReleaseCandidate) : ;;
  *)
    echo "unsupported Nix-on-ROCK artifact status: ${status}" >&2
    exit 1
    ;;
esac

if [ "${status}" = "BuildProof" ] || [ "${status}" = "DeviceAccepted" ] || [ "${status}" = "ReleaseCandidate" ]; then
  [ "$(count_lines "${image_files}")" -eq 1 ] || { echo "manifest cannot claim ${status}: expected exactly one image payload" >&2; exit 1; }
  [ "$(count_lines "${image_sha_files}")" -eq 1 ] || { echo "manifest cannot claim ${status}: expected exactly one image checksum" >&2; exit 1; }
  [ "$(count_lines "${update_files}")" -eq 1 ] || { echo "manifest cannot claim ${status}: expected exactly one update payload" >&2; exit 1; }
  [ "$(count_lines "${update_sha_files}")" -eq 1 ] || { echo "manifest cannot claim ${status}: expected exactly one update checksum" >&2; exit 1; }
  while IFS= read -r checksum_file; do
    [ -n "${checksum_file}" ] || continue
    validate_checksum_file "${checksum_file}"
  done <<EOF
${image_sha_files}
${update_sha_files}
EOF
  [ "${system_bytes}" != "unknown" ] || { echo "manifest cannot claim ${status}: update tar lacks target/SYSTEM" >&2; exit 1; }
  [ "${seed_payload}" != "unknown" ] || { echo "manifest cannot claim ${status}: update tar lacks target/seed/*.tar.zst" >&2; exit 1; }
  if [ -n "${seed_archive}" ] && [ "${seed_payload}" != "${seed_archive}" ]; then
    echo "manifest cannot claim ${status}: update seed ${seed_payload} does not match expected ${seed_archive}" >&2
    exit 1
  fi
  if [ -n "${seed_sha256}" ] && [ -n "${seed_tar_entry}" ]; then
    actual_seed_sha256=$(tar -xOf "${update_tar}" "${seed_tar_entry}" | sha256sum | awk '{print $1}')
    if [ "${actual_seed_sha256}" != "${seed_sha256}" ]; then
      echo "manifest cannot claim ${status}: update seed sha256 mismatch ${actual_seed_sha256} != ${seed_sha256}" >&2
      exit 1
    fi
  fi
fi

{
  printf '# Nix-on-ROCK SM8550 Build Manifest\n\n'
  printf '## Status\n\n'
  printf -- '- **Artifact status:** `%s`\n' "${status}"
  printf -- '- **Meaning:** CI-produced artifact evidence. `DeviceAccepted` requires separate on-device smoke evidence; `ReleaseCandidate` is reserved for a future public release channel.\n\n'

  printf '## Build Identity\n\n'
  printf -- '- **Product:** Nix-on-ROCK\n'
  printf -- '- **Repository:** `%s`\n' "${repo}"
  printf -- '- **Branch:** `%s`\n' "${branch}"
  printf -- '- **Commit:** `%s`\n' "${sha}"
  printf -- '- **Run:** `%s` attempt `%s`\n' "${run_id}" "${run_attempt}"
  printf -- '- **Device lane:** `%s`\n' "${device}"
  printf -- '- **Inherited build project:** `ROCKNIX`\n\n'

  printf '## Payloads\n\n'
  printf 'Payload filenames intentionally retain inherited `ROCKNIX-*` names during this transition. The workflow/artifact wrapper and this manifest identify the build as Nix-on-ROCK.\n\n'
  printf -- '- **Image files:**\n'
  if [ -n "${image_files}" ]; then printf '%s\n' "${image_files}" | sed 's#^#  - `#; s#$#`#'; else printf '  - none found\n'; fi
  printf -- '- **Image checksum files:**\n'
  if [ -n "${image_sha_files}" ]; then printf '%s\n' "${image_sha_files}" | sed 's#^#  - `#; s#$#`#'; else printf '  - none found\n'; fi
  printf -- '- **Update files:**\n'
  if [ -n "${update_files}" ]; then printf '%s\n' "${update_files}" | sed 's#^#  - `#; s#$#`#'; else printf '  - none found\n'; fi
  printf -- '- **Update checksum files:**\n'
  if [ -n "${update_sha_files}" ]; then printf '%s\n' "${update_sha_files}" | sed 's#^#  - `#; s#$#`#'; else printf '  - none found\n'; fi
  printf -- '- **Update `target/SYSTEM` bytes:** `%s`\n\n' "${system_bytes}"

  printf '## Guest Seed Evidence\n\n'
  printf -- '- **Packaged guest revision:** `%s`\n' "${guest_rev:-unknown}"
  printf -- '- **Manifest seed archive:** `%s`\n' "${seed_archive:-unknown}"
  printf -- '- **Update seed payload:** `%s`\n' "${seed_payload}"
  printf -- '- **Expected seed SHA256:** `%s`\n' "${seed_sha256:-unknown}"
  printf -- '- **Actual update seed SHA256:** `%s`\n' "${actual_seed_sha256}"
  printf -- '- **Seed compatible:** `%s`\n\n' "${seed_compatible:-unknown}"

  printf '## Storage and Recovery Contract\n\n'
  printf -- '- **Guest root:** `/storage/nix-on-rock/rootfs/current`\n'
  printf -- '- **Seed directory:** `/storage/nix-on-rock/images/seeds`\n'
  printf -- '- **Explicit recovery flags:** `/flash/rocknix.no-nspawn`, `rocknix.safe=1`, `/flash/rocknix.reseed-guest`\n'
  printf -- '- **Operator notes:** `%s`\n\n' "${sm8550_doc}"

  printf '## Upstream Intake\n\n'
  printf -- '- **Upstream intake note:** `%s`\n' "${intake_note}"
  printf -- '- **Policy:** Review upstream ROCKNIX as a substrate supplier; branch-local Nix-on-ROCK gates decide this build status.\n'
} > "${out}"
