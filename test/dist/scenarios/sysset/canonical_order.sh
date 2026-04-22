#!/usr/bin/env bash
# sysset/canonical_order.sh — Verify that get.bash enforces canonical install
# order regardless of the order features appear in the manifest.
#
# Strategy: list features in reverse canonical order in the manifest
# (install-pixi first, install-os-pkg second), then confirm execution log
# shows install-os-pkg was processed before install-pixi.
#
# Requires: root (get.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_PORT=18533
_TEST_VERSION="${SYSSET_BUILD_VERSION:-v0.1.0-test}"
_logfile="$(mktemp)"
_manifest_dir="$(mktemp -d)"
mkdir -p "${DIST}/${_TEST_VERSION}"
cp "${DIST}"/sysset-*.tar.gz "${DIST}/${_TEST_VERSION}/"
trap 'stop_file_server; rm -rf "${DIST}/${_TEST_VERSION}" "$_logfile" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/dist"
export SYSSET_VERSION="$_TEST_VERSION"

# Manifest lists install-pixi BEFORE install-os-pkg (reverse canonical order).
_manifest="${_manifest_dir}/manifest.json"
cat > "$_manifest" << EOF
{
  "features": [
    { "id": "install-pixi", "options": { "version": "0.66.0" } },
    { "id": "install-os-pkg", "options": { "manifest": "${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml" } }
  ]
}
EOF

check "get.bash completes with canonical-order manifest" \
  bash "${REPO_ROOT}/get.bash" --logfile "$_logfile" "$_manifest"

# In the log, install-os-pkg should appear before install-pixi.
check "install-os-pkg ran before install-pixi (canonical order enforced)" \
  bash -c '
    log="'"$_logfile"'"
    line_ospkg=$(grep -n "\[install-os-pkg\]" "$log" | head -1 | cut -d: -f1)
    line_pixi=$(grep -n "\[install-pixi\]" "$log" | head -1 | cut -d: -f1)
    [[ -n "$line_ospkg" && -n "$line_pixi" && "$line_ospkg" -lt "$line_pixi" ]]
  '

reportResults
