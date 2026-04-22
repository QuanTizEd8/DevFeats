#!/usr/bin/env bash
# sysset/override_order.sh — Verify that override_install_order: true causes
# features to run in manifest order, not canonical order.
#
# Strategy: manifest lists install-pixi before install-os-pkg with
# override_install_order: true. The log should show install-pixi first.
#
# Requires: root (get.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_PORT=18536
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

_manifest="${_manifest_dir}/manifest.json"
cat > "$_manifest" << EOF
{
  "override_install_order": true,
  "features": [
    { "id": "install-pixi", "options": { "version": "0.66.0" } },
    { "id": "install-os-pkg", "options": { "manifest": "${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml" } }
  ]
}
EOF

check "get.bash completes with override_install_order: true" \
  bash "${REPO_ROOT}/get.bash" --logfile "$_logfile" "$_manifest"

# install-pixi should appear BEFORE install-os-pkg in the log.
check "install-pixi ran before install-os-pkg (override order respected)" \
  bash -c '
    log="'"$_logfile"'"
    line_pixi=$(grep -n "\[install-pixi\]" "$log" | head -1 | cut -d: -f1)
    line_ospkg=$(grep -n "\[install-os-pkg\]" "$log" | head -1 | cut -d: -f1)
    [[ -n "$line_pixi" && -n "$line_ospkg" && "$line_pixi" -lt "$line_ospkg" ]]
  '

reportResults
