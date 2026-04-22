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

_PORT=18541

_TEST_VERSION="${SYSSET_BUILD_VERSION:-v0.1.0-test}"
mkdir -p "${REPO_ROOT}/dist/${_TEST_VERSION}"
cp "${REPO_ROOT}/dist"/sysset-*.tar.gz "${REPO_ROOT}/dist/${_TEST_VERSION}/"
trap 'stop_file_server; rm -rf "${REPO_ROOT}/dist/${_TEST_VERSION}"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/dist"

check "get.sh installs setup-shim on macOS" \
  sudo env PATH="$PATH" \
  SYSSET_RAW_BASE="$SYSSET_RAW_BASE" \
  SYSSET_BASE_URL="$SYSSET_BASE_URL" \
  SYSSET_VERSION="$_TEST_VERSION" \
  bash "${REPO_ROOT}/get.sh" setup-shim

check "code shim installed by setup-shim" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
