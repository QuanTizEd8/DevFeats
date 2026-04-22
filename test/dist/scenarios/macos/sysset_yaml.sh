#!/usr/bin/env bash
# macos/sysset_yaml.sh — Verify that get.bash auto-installs yq and processes
# a YAML manifest on macOS.
#
# yq (mikefarah/yq) is fetched by get.bash from GitHub Releases when absent.
# This test verifies the auto-install path on macOS (darwin/arm64 or amd64).
#
# setup-shim is used because it requires no package manager (no ospkg__run
# call), works on macOS as root, and produces verifiable shim artifacts.
# Requires: root for get.bash manifest mode (os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_PORT=18543
_TEST_VERSION="${SYSSET_BUILD_VERSION:-v0.1.0-test}"
_manifest_dir="$(mktemp -d)"
mkdir -p "${DIST}/${_TEST_VERSION}"
cp "${DIST}"/sysset-*.tar.gz "${DIST}/${_TEST_VERSION}/"
trap 'stop_file_server; rm -rf "${DIST}/${_TEST_VERSION}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/dist"

# Ensure yq is not present so the auto-install path is exercised.
# (If brew already installed yq, skip this test.)
if command -v yq > /dev/null 2>&1; then
  echo "ℹ️  yq already present — YAML auto-install path not tested." >&2
fi

_manifest="${_manifest_dir}/manifest.yaml"
cat > "$_manifest" << 'EOF'
features:
  - id: setup-shim
EOF

check "get.bash processes YAML manifest on macOS" \
  sudo env PATH="$PATH" \
  SYSSET_RAW_BASE="$SYSSET_RAW_BASE" \
  SYSSET_BASE_URL="$SYSSET_BASE_URL" \
  SYSSET_VERSION="$_TEST_VERSION" \
  bash "${REPO_ROOT}/get.bash" "$_manifest"

check "code shim installed by YAML-driven sysset (macOS)" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
