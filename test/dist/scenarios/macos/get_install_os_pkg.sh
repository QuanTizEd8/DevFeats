#!/usr/bin/env bash
# macos/get_install_os_pkg.sh — Verify get.sh downloads and installs a feature
# on macOS using a local HTTP file server.
#
# setup-shim is used because it requires no package manager (no ospkg__run
# call), works on macOS as root, and produces verifiable shim artifacts.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="setup-shim"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-macos-get"

mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

_PORT=18551
trap 'stop_file_server; rm -rf "${_MIRROR}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"

check "get.sh installs setup-shim on macOS (rolling mode, @spec)" \
  sudo env PATH="$PATH" \
  SYSSET_RAW_BASE="$SYSSET_RAW_BASE" \
  SYSSET_BASE_URL="$SYSSET_BASE_URL" \
  bash "${REPO_ROOT}/get.sh" "${_FEAT}@${_VER}"

check "code shim installed by setup-shim" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
