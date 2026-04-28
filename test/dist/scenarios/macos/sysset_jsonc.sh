#!/usr/bin/env bash
# macos/sysset_jsonc.sh — Same as sysset_json.sh but uses a .jsonc file so
# json__strip_jsonc_stdin and duplicate-key checks are exercised.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

DIST="${REPO_ROOT}/dist"

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-macos-jsonc"
mkdir -p "${_MIRROR}"
mkdir -p "${_MIRROR}/setup-shim/${_VER}"
cp "${DIST}/sysset-setup-shim.tar.gz" "${_MIRROR}/setup-shim/${_VER}/"
offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${DIST}" "setup-shim:${_VER}"

_PORT=18554
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL

_manifest="${_manifest_dir}/devcontainer.jsonc"
cat > "$_manifest" << 'EOF'
{
  // devcontainer with JSONC
  "name": "jsonc",
  "features": {
    "ghcr.io/quantized8/sysset/setup-shim": {}
  }
}
EOF

check "install.bash processes devcontainer.jsonc (comments stripped)" \
  sudo env PATH="$PATH" \
  SYSSET_RAW_BASE="$SYSSET_RAW_BASE" \
  SYSSET_BASE_URL="$SYSSET_BASE_URL" \
  SYSSET_VERSION="${_BUNDLE}" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "code shim installed" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
