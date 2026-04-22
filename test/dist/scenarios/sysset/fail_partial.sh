#!/usr/bin/env bash
# sysset/fail_partial.sh — Verify that get.bash reports failure when one
# feature fails, but continues to attempt the remaining features.
#
# Strategy: include a non-existent feature alongside a valid one.
# The valid feature (install-pixi) should still be installed, but get.bash
# must exit non-zero because the bogus feature download failed.
#
# Requires: root (get.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_PORT=18534
_TEST_VERSION="${SYSSET_BUILD_VERSION:-v0.1.0-test}"
_manifest_dir="$(mktemp -d)"
mkdir -p "${DIST}/${_TEST_VERSION}"
cp "${DIST}"/sysset-*.tar.gz "${DIST}/${_TEST_VERSION}/"
trap 'stop_file_server; rm -rf "${DIST}/${_TEST_VERSION}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/dist"
export SYSSET_VERSION="$_TEST_VERSION"

# "does-not-exist" has no tarball; install-pixi is valid.
_manifest="${_manifest_dir}/manifest.json"
cat > "$_manifest" << EOF
{
  "features": [
    { "id": "install-pixi", "options": { "version": "0.66.0" } },
    { "id": "does-not-exist", "options": {} }
  ]
}
EOF

# get.bash should exit non-zero overall.
fail_check "get.bash exits non-zero when a feature fails" \
  bash "${REPO_ROOT}/get.bash" "$_manifest"

# But install-pixi (canonical order: before does-not-exist) should have run.
check "install-pixi still installed despite partial failure" \
  command -v pixi

reportResults
