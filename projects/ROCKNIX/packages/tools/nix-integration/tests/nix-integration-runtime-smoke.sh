#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM

FAKE_ARTIFACT="${TMP_DIR}/nix-portable-aarch64"
cat >"${FAKE_ARTIFACT}" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "--version" ]; then
  echo "nix (Nix) smoke-test"
  exit 0
fi
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "run" ] && [ "${3:-}" = "nixpkgs#hello" ]; then
  echo "Hello, world!"
  exit 0
fi
if [ "${1:-}" = "nix-shell" ]; then
  echo "nix-shell smoke-test"
  exit 0
fi
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "shell" ] && [ "${3:-}" = "nixpkgs#jq" ]; then
  echo "jq-1.7 smoke-test"
  exit 0
fi
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "shell" ] && [ "${3:-}" = "nixpkgs#python3" ]; then
  echo "Python 3 smoke-test"
  exit 0
fi
if [ "${1:-}" = "nix" ] && [ "${2:-}" = "shell" ] && [ "${3:-}" = "nixpkgs#does-not-exist" ]; then
  echo "error: package does not exist" >&2
  exit 42
fi
echo "fake nix-portable called: $*"
exit 0
EOF
chmod 0755 "${FAKE_ARTIFACT}"
FAKE_SHA=$(sha256sum "${FAKE_ARTIFACT}" | awk '{print $1}')

export NIX_PORTABLE_DIR="${TMP_DIR}/apps/nix-portable"
export NIX_WRAPPER_DIR="${TMP_DIR}/bin"
export NP_LOCATION="${TMP_DIR}/storage"
export NIX_PORTABLE_URL="file://${FAKE_ARTIFACT}"
export NIX_PORTABLE_SHA256="${FAKE_SHA}"
export NIX_PORTABLE_REQUIRED_MB=1
export NIX_PORTABLE_SKIP_ARCH_CHECK=1
mkdir -p "${NP_LOCATION}"

"${PKG_DIR}/scripts/nix-portable-install" install >/tmp/nix-portable-install-smoke.log
"${NIX_WRAPPER_DIR}/nix" --version | grep -q 'nix (Nix) smoke-test'
"${NIX_WRAPPER_DIR}/nix" run nixpkgs#hello | grep -q 'Hello, world!'
"${NIX_WRAPPER_DIR}/nix-shell" -p jq | grep -q 'nix-shell smoke-test'
"${NIX_WRAPPER_DIR}/nix-run" nixpkgs#hello | grep -q 'Hello, world!'
"${NIX_WRAPPER_DIR}/nix" shell nixpkgs#jq --command jq --version | grep -q 'jq-1.7 smoke-test'
"${NIX_WRAPPER_DIR}/nix-dev-shell" nixpkgs#python3 --command python3 --version | grep -q 'Python 3 smoke-test'
if "${NIX_WRAPPER_DIR}/nix" shell nixpkgs#does-not-exist >/tmp/nix-dev-shell-error.log 2>&1; then
  echo "expected missing dev-shell package to fail" >&2
  exit 1
fi
grep -q 'package does not exist' /tmp/nix-dev-shell-error.log
"${NIX_WRAPPER_DIR}/nix" --version | grep -q 'nix (Nix) smoke-test'
"${PKG_DIR}/scripts/nix-doctor" --offline --dev-shell-smoke >/tmp/nix-doctor-smoke.log
"${NIX_WRAPPER_DIR}/nix-doctor" --offline --dev-shell-smoke >/tmp/nix-doctor-wrapper-smoke.log
"${PKG_DIR}/scripts/nix-portable-install" status | grep -q 'nix-portable: installed'
grep -q 'What=/storage/.nix-root' "${PKG_DIR}/system.d/nix.mount"
grep -q 'Where=/nix' "${PKG_DIR}/system.d/nix.mount"
grep -q 'Before=nix.mount' "${PKG_DIR}/system.d/nix-storage-setup.service"
"${PKG_DIR}/scripts/nix-portable-install" remove >/tmp/nix-portable-remove-smoke.log
[ ! -e "${NIX_WRAPPER_DIR}/nix" ]
[ ! -e "${NIX_WRAPPER_DIR}/nix-dev-shell" ]
[ ! -e "${NIX_WRAPPER_DIR}/nix-doctor" ]
[ ! -d "${NIX_PORTABLE_DIR}" ]

printf 'nix-integration runtime smoke passed\n'
