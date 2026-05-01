#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

set -eu

NIX_PORTABLE_VERSION="${NIX_PORTABLE_VERSION:-v012}"
NIX_PORTABLE_ASSET="${NIX_PORTABLE_ASSET:-nix-portable-aarch64}"
NIX_PORTABLE_URL="${NIX_PORTABLE_URL:-https://github.com/DavHau/nix-portable/releases/download/${NIX_PORTABLE_VERSION}/${NIX_PORTABLE_ASSET}}"
NIX_PORTABLE_SHA256="${NIX_PORTABLE_SHA256:-af41d8defdb9fa17ee361220ee05a0c758d3e6231384a3f969a314f9133744ea}"
NIX_PORTABLE_DIR="${NIX_PORTABLE_DIR:-/storage/apps/nix-portable}"
NIX_PORTABLE_BIN="${NIX_PORTABLE_BIN:-${NIX_PORTABLE_DIR}/nix-portable}"
NIX_WRAPPER_DIR="${NIX_WRAPPER_DIR:-/storage/bin}"
NIX_PORTABLE_REQUIRED_MB="${NIX_PORTABLE_REQUIRED_MB:-512}"
NP_LOCATION="${NP_LOCATION:-/storage}"
NP_RUNTIME="${NP_RUNTIME:-proot}"

usage() {
  cat <<EOF
Usage: ${0##*/} [install|repair|doctor|status|remove]

Bootstraps storage-only Nix on ROCKNIX using nix-portable.

Installs:
  /storage/bin/nix
  /storage/bin/nix-shell
  /storage/bin/nix-run
  /storage/bin/nix-dev-shell
  /storage/bin/nix-doctor

Defaults:
  NP_RUNTIME=${NP_RUNTIME}
  NP_LOCATION=${NP_LOCATION}
  NIX_PORTABLE_DIR=${NIX_PORTABLE_DIR}
EOF
}

info() {
  echo "==> $*"
}

fail() {
  echo "${0##*/}: $*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

sha256_file() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif have openssl; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    fail "sha256sum or openssl is required"
  fi
}

check_arch() {
  arch=$(uname -m 2>/dev/null || echo unknown)
  case "${arch}" in
    aarch64|arm64) ;;
    *) fail "this bootstrap is pinned for aarch64 ROCKNIX, but this system reports '${arch}'" ;;
  esac
}

check_storage() {
  [ -d "${NP_LOCATION}" ] || fail "storage location does not exist: ${NP_LOCATION}"
  [ -w "${NP_LOCATION}" ] || fail "storage location is not writable: ${NP_LOCATION}"

  available_mb=$(df -m "${NP_LOCATION}" | awk 'NR==2 {print $4}')
  case "${available_mb}" in
    ''|*[!0-9]*) fail "could not determine free space for ${NP_LOCATION}" ;;
  esac

  if [ "${available_mb}" -lt "${NIX_PORTABLE_REQUIRED_MB}" ]; then
    fail "not enough free space on ${NP_LOCATION}: ${available_mb}MB available, ${NIX_PORTABLE_REQUIRED_MB}MB required"
  fi
}

download() {
  url=$1
  dest=$2

  case "${url}" in
    file://*)
      src=${url#file://}
      [ -f "${src}" ] || fail "local artifact does not exist: ${src}"
      cp "${src}" "${dest}"
      ;;
    /*|./*|../*)
      [ -f "${url}" ] || fail "local artifact does not exist: ${url}"
      cp "${url}" "${dest}"
      ;;
    http://*|https://*)
      if have curl; then
        curl -fL --retry 3 --connect-timeout 20 --progress-bar "${url}" -o "${dest}"
      elif have wget; then
        wget -O "${dest}" "${url}"
      else
        fail "curl or wget is required to download nix-portable"
      fi
      ;;
    *)
      fail "unsupported NIX_PORTABLE_URL: ${url}"
      ;;
  esac
}

write_runner() {
  mkdir -p "${NIX_PORTABLE_DIR}/bin"
  cat >"${NIX_PORTABLE_DIR}/bin/nix-portable-run" <<'EOF'
#!/bin/sh
set -eu
NIX_PORTABLE_DIR="${NIX_PORTABLE_DIR:-/storage/apps/nix-portable}"
NIX_PORTABLE_BIN="${NIX_PORTABLE_BIN:-${NIX_PORTABLE_DIR}/nix-portable}"
NP_LOCATION="${NP_LOCATION:-/storage}"
NP_RUNTIME="${NP_RUNTIME:-proot}"
[ -x "${NIX_PORTABLE_BIN}" ] || { echo "nix-portable missing at ${NIX_PORTABLE_BIN}" >&2; exit 1; }
[ -d "${NP_LOCATION}" ] || { echo "NP_LOCATION does not exist: ${NP_LOCATION}" >&2; exit 1; }
export NP_RUNTIME NP_LOCATION
case "${1:-}" in
  nix) shift; exec "${NIX_PORTABLE_BIN}" nix "$@" ;;
  nix-shell) shift; exec "${NIX_PORTABLE_BIN}" nix-shell "$@" ;;
  nix-run) shift; exec "${NIX_PORTABLE_BIN}" nix run "$@" ;;
  dev-shell) shift; exec "${NIX_PORTABLE_BIN}" nix shell "$@" ;;
  raw) shift; exec "${NIX_PORTABLE_BIN}" "$@" ;;
  *) echo "Usage: ${0##*/} <nix|nix-shell|nix-run|dev-shell|raw> [args...]" >&2; exit 1 ;;
esac
EOF
  chmod 0755 "${NIX_PORTABLE_DIR}/bin/nix-portable-run"
}

write_doctor() {
  mkdir -p "${NIX_PORTABLE_DIR}/bin"
  cat >"${NIX_PORTABLE_DIR}/bin/nix-doctor" <<'EOF'
#!/bin/sh
set -u
NIX_PORTABLE_DIR="${NIX_PORTABLE_DIR:-/storage/apps/nix-portable}"
NIX_PORTABLE_BIN="${NIX_PORTABLE_BIN:-${NIX_PORTABLE_DIR}/nix-portable}"
NIX_PORTABLE_RUNNER="${NIX_PORTABLE_RUNNER:-${NIX_PORTABLE_DIR}/bin/nix-portable-run}"
NIX_DOCTOR="${NIX_DOCTOR:-${NIX_PORTABLE_DIR}/bin/nix-doctor}"
NIX_WRAPPER_DIR="${NIX_WRAPPER_DIR:-/storage/bin}"
NIX_PORTABLE_REQUIRED_MB="${NIX_PORTABLE_REQUIRED_MB:-512}"
NP_LOCATION="${NP_LOCATION:-/storage}"
NP_RUNTIME="${NP_RUNTIME:-proot}"
CHECK_NETWORK=1
RUN_SMOKE=1
RUN_DEV_SHELL_SMOKE=0
NIX_DEV_SHELL_SMOKE_PACKAGE="${NIX_DEV_SHELL_SMOKE_PACKAGE:-nixpkgs#jq}"
NIX_DEV_SHELL_SMOKE_COMMAND="${NIX_DEV_SHELL_SMOKE_COMMAND:-jq --version}"
FAILURES=0
WARNINGS=0

usage() {
  cat <<EOUSAGE
Usage: ${0##*/} [--offline] [--no-smoke] [--dev-shell-smoke]
EOUSAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --offline) CHECK_NETWORK=0 ;;
    --no-smoke) RUN_SMOKE=0 ;;
    --dev-shell-smoke) RUN_DEV_SHELL_SMOKE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "${0##*/}: unknown option '$1'" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

ok() { echo "OK: $*"; }
warn() { WARNINGS=$((WARNINGS + 1)); echo "WARN: $*"; }
fail_check() { FAILURES=$((FAILURES + 1)); echo "FAIL: $*"; }
have() { command -v "$1" >/dev/null 2>&1; }
sha256_file() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have openssl; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else return 1
  fi
}

arch=$(uname -m 2>/dev/null || echo unknown)
case "${arch}" in aarch64|arm64) ok "architecture is ${arch}" ;; *) warn "architecture is ${arch}; validated on SM8550/aarch64" ;; esac
root_flags=$(awk '$2 == "/" {print $4; exit}' /proc/mounts 2>/dev/null)
case ",${root_flags}," in *,ro,*) ok "root filesystem is read-only" ;; *,rw,*) warn "root filesystem appears writable" ;; *) warn "could not determine root filesystem flags" ;; esac

if [ -d "${NP_LOCATION}" ]; then ok "storage location exists: ${NP_LOCATION}"; else fail_check "storage location missing: ${NP_LOCATION}"; fi
if [ -w "${NP_LOCATION}" ]; then ok "storage location is writable: ${NP_LOCATION}"; else fail_check "storage location is not writable: ${NP_LOCATION}"; fi
available_mb=$(df -m "${NP_LOCATION}" 2>/dev/null | awk 'NR==2 {print $4}')
case "${available_mb}" in ''|*[!0-9]*) fail_check "could not determine free space for ${NP_LOCATION}" ;; *) [ "${available_mb}" -ge "${NIX_PORTABLE_REQUIRED_MB}" ] && ok "storage free space ${available_mb}MB >= ${NIX_PORTABLE_REQUIRED_MB}MB" || fail_check "storage free space ${available_mb}MB < ${NIX_PORTABLE_REQUIRED_MB}MB" ;; esac

if [ -x "${NIX_PORTABLE_BIN}" ]; then ok "nix-portable executable exists: ${NIX_PORTABLE_BIN}"; else fail_check "nix-portable missing or not executable: ${NIX_PORTABLE_BIN}"; fi
if [ -f "${NIX_PORTABLE_BIN}.sha256" ] && [ -x "${NIX_PORTABLE_BIN}" ]; then
  expected=$(awk 'NR==1 {print $1}' "${NIX_PORTABLE_BIN}.sha256")
  if actual=$(sha256_file "${NIX_PORTABLE_BIN}"); then [ "${actual}" = "${expected}" ] && ok "nix-portable checksum matches recorded sha256" || fail_check "nix-portable checksum mismatch: expected ${expected}, got ${actual}"; else fail_check "sha256sum or openssl is required to verify nix-portable"; fi
else
  fail_check "missing checksum metadata: ${NIX_PORTABLE_BIN}.sha256"
fi

[ -x "${NIX_PORTABLE_RUNNER}" ] && ok "runner exists: ${NIX_PORTABLE_RUNNER}" || fail_check "runner missing or not executable: ${NIX_PORTABLE_RUNNER}"
[ -x "${NIX_DOCTOR}" ] && ok "doctor exists: ${NIX_DOCTOR}" || warn "doctor helper is not installed in storage: ${NIX_DOCTOR}"
for wrapper in nix nix-shell nix-run nix-dev-shell nix-doctor; do
  [ -x "${NIX_WRAPPER_DIR}/${wrapper}" ] && ok "wrapper exists: ${NIX_WRAPPER_DIR}/${wrapper}" || fail_check "wrapper missing or not executable: ${NIX_WRAPPER_DIR}/${wrapper}"
done

[ "${NP_RUNTIME}" = "proot" ] && ok "NP_RUNTIME is proot" || warn "NP_RUNTIME is '${NP_RUNTIME}', but ROCKNIX SM8550 currently requires proot"
if [ "${RUN_SMOKE}" -eq 1 ]; then
  if output=$(NP_RUNTIME="${NP_RUNTIME}" NP_LOCATION="${NP_LOCATION}" "${NIX_WRAPPER_DIR}/nix" --version 2>&1); then ok "nix smoke command succeeded: ${output}"; else fail_check "nix smoke command failed: ${output}"; fi
else
  warn "nix smoke command skipped"
fi
if [ "${RUN_DEV_SHELL_SMOKE}" -eq 1 ]; then
  if output=$(NP_RUNTIME="${NP_RUNTIME}" NP_LOCATION="${NP_LOCATION}" "${NIX_WRAPPER_DIR}/nix" shell "${NIX_DEV_SHELL_SMOKE_PACKAGE}" --command sh -c "${NIX_DEV_SHELL_SMOKE_COMMAND}" 2>&1); then ok "dev shell smoke command succeeded: ${output}"; else fail_check "dev shell smoke command failed for ${NIX_DEV_SHELL_SMOKE_PACKAGE}: ${output}"; fi
fi
if [ "${CHECK_NETWORK}" -eq 0 ]; then
  warn "network checks skipped"
elif have curl && curl -fsSI --connect-timeout 10 https://cache.nixos.org >/dev/null 2>&1; then
  ok "can reach https://cache.nixos.org"
elif have wget && wget --spider -T 10 https://cache.nixos.org >/dev/null 2>&1; then
  ok "can reach https://cache.nixos.org"
else
  fail_check "cannot reach https://cache.nixos.org"
fi

if [ "${FAILURES}" -eq 0 ]; then echo "nix-doctor: passed with ${WARNINGS} warning(s)"; exit 0; fi
echo "nix-doctor: failed with ${FAILURES} failure(s) and ${WARNINGS} warning(s)"
exit 1
EOF
  chmod 0755 "${NIX_PORTABLE_DIR}/bin/nix-doctor"
}

write_wrapper() {
  name=$1
  command=$2
  mkdir -p "${NIX_WRAPPER_DIR}"
  cat >"${NIX_WRAPPER_DIR}/${name}" <<EOF
#!/bin/sh
exec "${NIX_PORTABLE_DIR}/bin/nix-portable-run" ${command} "\$@"
EOF
  chmod 0755 "${NIX_WRAPPER_DIR}/${name}"
}

install_toolbox() {
  check_arch
  check_storage

  mkdir -p "${NIX_PORTABLE_DIR}" "${NIX_WRAPPER_DIR}"
  tmp="${NIX_PORTABLE_DIR}/.${NIX_PORTABLE_ASSET}.tmp.$$"
  trap 'rm -f "${tmp}"' EXIT INT TERM

  if [ -x "${NIX_PORTABLE_BIN}" ]; then
    current=$(sha256_file "${NIX_PORTABLE_BIN}")
    if [ "${current}" = "${NIX_PORTABLE_SHA256}" ]; then
      info "Using existing verified nix-portable at ${NIX_PORTABLE_BIN}"
    else
      info "Existing nix-portable checksum differs; downloading pinned artifact"
      download "${NIX_PORTABLE_URL}" "${tmp}"
      actual=$(sha256_file "${tmp}")
      [ "${actual}" = "${NIX_PORTABLE_SHA256}" ] || fail "checksum mismatch: expected ${NIX_PORTABLE_SHA256}, got ${actual}"
      mv "${tmp}" "${NIX_PORTABLE_BIN}"
      chmod 0755 "${NIX_PORTABLE_BIN}"
    fi
  else
    info "Downloading ${NIX_PORTABLE_URL}"
    download "${NIX_PORTABLE_URL}" "${tmp}"
    actual=$(sha256_file "${tmp}")
    [ "${actual}" = "${NIX_PORTABLE_SHA256}" ] || fail "checksum mismatch: expected ${NIX_PORTABLE_SHA256}, got ${actual}"
    mv "${tmp}" "${NIX_PORTABLE_BIN}"
    chmod 0755 "${NIX_PORTABLE_BIN}"
  fi

  printf '%s\n' "${NIX_PORTABLE_SHA256}" >"${NIX_PORTABLE_BIN}.sha256"
  printf '%s\n' "${NIX_PORTABLE_VERSION}" >"${NIX_PORTABLE_DIR}/version"
  printf '%s\n' "${NIX_PORTABLE_URL}" >"${NIX_PORTABLE_DIR}/url"

  write_runner
  write_doctor
  write_wrapper nix nix
  write_wrapper nix-shell nix-shell
  write_wrapper nix-run nix-run
  write_wrapper nix-dev-shell dev-shell
  cat >"${NIX_WRAPPER_DIR}/nix-doctor" <<EOF
#!/bin/sh
exec "${NIX_PORTABLE_DIR}/bin/nix-doctor" "\$@"
EOF
  chmod 0755 "${NIX_WRAPPER_DIR}/nix-doctor"

  info "Installed storage-only Nix wrappers to ${NIX_WRAPPER_DIR}"
  "${NIX_WRAPPER_DIR}/nix-doctor" --offline --no-smoke
}

remove_toolbox() {
  rm -f "${NIX_WRAPPER_DIR}/nix" "${NIX_WRAPPER_DIR}/nix-shell" "${NIX_WRAPPER_DIR}/nix-run" "${NIX_WRAPPER_DIR}/nix-dev-shell" "${NIX_WRAPPER_DIR}/nix-doctor"
  rm -rf "${NIX_PORTABLE_DIR}"
  info "Removed storage-only Nix bootstrap state"
}

status_toolbox() {
  [ -x "${NIX_PORTABLE_BIN}" ] && echo "nix-portable: installed at ${NIX_PORTABLE_BIN}" || echo "nix-portable: missing at ${NIX_PORTABLE_BIN}"
  for wrapper in nix nix-shell nix-run nix-dev-shell nix-doctor; do
    [ -x "${NIX_WRAPPER_DIR}/${wrapper}" ] && echo "wrapper: ${NIX_WRAPPER_DIR}/${wrapper}" || echo "wrapper missing: ${NIX_WRAPPER_DIR}/${wrapper}"
  done
}

case "${1:-install}" in
  install|repair) install_toolbox ;;
  doctor)
    shift
    if [ $# -eq 0 ]; then
      "${NIX_WRAPPER_DIR}/nix-doctor" --dev-shell-smoke
    else
      "${NIX_WRAPPER_DIR}/nix-doctor" "$@"
    fi
    ;;
  status) status_toolbox ;;
  remove) remove_toolbox ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 1 ;;
esac
