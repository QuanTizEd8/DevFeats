#!/usr/bin/env bash
# sysset/fail_partial.sh — Verify that get.bash reports failure when one
# feature fails, but continues to attempt the remaining features.
#
# Strategy: manifest includes a non-existent feature alongside a valid one.
# The valid feature (install-pixi) is listed in the bundle manifest and
# installs successfully; the bogus "does-not-exist" feature is missing from
# the bundle manifest and must fail without aborting the loop.
#
# Requires: root (get.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-sysset-fail-partial"
mkdir -p "${_MIRROR}/${_BUNDLE}"
mkdir -p "${_MIRROR}/install-pixi/${_VER}"
cp "${DIST}/sysset-install-pixi.tar.gz" "${_MIRROR}/install-pixi/${_VER}/"
cat > "${_MIRROR}/${_BUNDLE}/manifest.yaml" << EOF
bundle: ${_BUNDLE}
prior_bundle: v0.0.0
generated_at: "1970-01-01T00:00:00Z"
features:
  install-pixi: ${_VER}
EOF

_PORT=18542
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_VERSION="${_BUNDLE}"

# "does-not-exist" is absent from the bundle manifest; install-pixi is valid.
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
