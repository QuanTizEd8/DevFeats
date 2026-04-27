#!/usr/bin/env bash
# macos/sysset_json.sh — Verify that install.bash processes a devcontainer.json and
# installs features on macOS using a local HTTP file server.
#
# setup-shim is used because it requires no package manager (no ospkg__run
# call), works on macOS as root, and produces verifiable shim artifacts.
# Requires: root for install.bash manifest mode (os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-macos-json"
mkdir -p "${_MIRROR}/${_BUNDLE}"
mkdir -p "${_MIRROR}/setup-shim/${_VER}"
cp "${DIST}/sysset-setup-shim.tar.gz" "${_MIRROR}/setup-shim/${_VER}/"
cat > "${_MIRROR}/${_BUNDLE}/manifest.yaml" << EOF
bundle: ${_BUNDLE}
prior_bundle: v0.0.0
generated_at: "1970-01-01T00:00:00Z"
features:
  setup-shim: ${_VER}
EOF

_PORT=18552
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "macos ${_BUNDLE}",
  "features": {
    "ghcr.io/quantized8/sysset/setup-shim": {}
  }
}
EOF

check "install.bash processes devcontainer.json on macOS (bundle-pinned via SYSSET_VERSION)" \
  sudo env PATH="$PATH" \
  SYSSET_RAW_BASE="$SYSSET_RAW_BASE" \
  SYSSET_BASE_URL="$SYSSET_BASE_URL" \
  SYSSET_VERSION="${_BUNDLE}" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "code shim installed by setup-shim (macOS)" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
