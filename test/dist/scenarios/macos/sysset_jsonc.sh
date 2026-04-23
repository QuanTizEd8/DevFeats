#!/usr/bin/env bash
# macos/sysset_jsonc.sh — Same as sysset_json.sh but uses a .jsonc file so
# json__strip_jsonc_stdin and duplicate-key checks are exercised.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-macos-jsonc"
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

check "get.bash processes devcontainer.jsonc (comments stripped)" \
  sudo env PATH="$PATH" \
  SYSSET_RAW_BASE="$SYSSET_RAW_BASE" \
  SYSSET_BASE_URL="$SYSSET_BASE_URL" \
  SYSSET_VERSION="${_BUNDLE}" \
  bash "${REPO_ROOT}/get.bash" "$_manifest"

check "code shim installed" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
