#!/usr/bin/env bash
# sysset/compatible_prefix.sh — Verify that OCI feature keys from any registry
# prefix are accepted and installed.
#
# What this tests:
#   • OCI keys outside `ghcr.io/quantized8/sysset/` are not filtered out.
#   • Mixed-prefix manifests install successfully when referenced feature IDs
#     are available in the local bundle/mirror.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

DIST="${REPO_ROOT}/dist"

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-sysset-compat-prefix"
mkdir -p "${_MIRROR}"
mkdir -p "${_MIRROR}/install-pixi/${_VER}"
mkdir -p "${_MIRROR}/install-os-pkg/${_VER}"
cp "${DIST}/sysset-install-pixi.tar.gz" "${_MIRROR}/install-pixi/${_VER}/"
cp "${DIST}/sysset-install-os-pkg.tar.gz" "${_MIRROR}/install-os-pkg/${_VER}/"
offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${DIST}" "install-pixi:${_VER}" "install-os-pkg:${_VER}"

_PORT=18547
_manifest_dir="$(mktemp -d)"
_log_file="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir" "$_log_file"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "compat ${_BUNDLE}",
  "features": {
    "ghcr.io/example/features/install-pixi": { "version": "0.66.0" },
    "ghcr.io/quantized8/sysset/install-os-pkg": {}
  }
}
EOF

check "install.bash completes with mixed-prefix OCI keys" \
  bash "${REPO_ROOT}/install.bash" --log_file "$_log_file" "$_manifest"

check "no prefix-filter warning was emitted" \
  bash -c "! grep -q 'not sysset-compatible\\|not OCI ref or local-path feature' '$_log_file'"

check "install-pixi installed from non-sysset prefix key" \
  command -v pixi

check "install-os-pkg sibling feature also installed" \
  command -v tree

reportResults
