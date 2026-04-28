#!/usr/bin/env bash
# sysset/fail_partial.sh — Verify that install.bash reports failure when one
# feature fails, after attempting features from the devcontainer.
#
# Strategy: devcontainer includes a non-existent OCI feature alongside a
# valid one. The valid feature (install-pixi) is listed in the bundle manifest;
# the bogus "does-not-exist" feature is missing from the bundle manifest and
# must fail without blocking install-pixi.
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
_MIRROR="${REPO_ROOT}/test-mirror-sysset-fail-partial"
mkdir -p "${_MIRROR}"
mkdir -p "${_MIRROR}/install-pixi/${_VER}"
cp "${DIST}/sysset-install-pixi.tar.gz" "${_MIRROR}/install-pixi/${_VER}/"
offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${DIST}" "install-pixi:${_VER}"

_PORT=18542
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "partial ${_BUNDLE}",
  "features": {
    "ghcr.io/quantized8/sysset/does-not-exist": {},
    "ghcr.io/quantized8/sysset/install-pixi": { "version": "0.66.0" }
  }
}
EOF

# install.bash should exit non-zero overall.
fail_check "install.bash exits non-zero when a feature fails" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "install-pixi still installed despite partial failure" \
  command -v pixi

reportResults
