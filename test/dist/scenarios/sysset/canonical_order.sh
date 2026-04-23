#!/usr/bin/env bash
# sysset/canonical_order.sh — Verify that get.bash enforces canonical install
# order regardless of the order features appear in the manifest.
#
# Strategy: list features in reverse canonical order in the manifest
# (install-pixi first, install-os-pkg second), then confirm execution log
# shows install-os-pkg was processed before install-pixi. Uses bundle-pinned
# mode to exercise the new URL scheme.
#
# Requires: root (get.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-sysset-canonical"
mkdir -p "${_MIRROR}/${_BUNDLE}"
for _f in install-pixi install-os-pkg; do
  mkdir -p "${_MIRROR}/${_f}/${_VER}"
  cp "${DIST}/sysset-${_f}.tar.gz" "${_MIRROR}/${_f}/${_VER}/"
done
cat > "${_MIRROR}/${_BUNDLE}/manifest.yaml" << EOF
bundle: ${_BUNDLE}
prior_bundle: v0.0.0
generated_at: "1970-01-01T00:00:00Z"
features:
  install-pixi: ${_VER}
  install-os-pkg: ${_VER}
EOF

_PORT=18541
_logfile="$(mktemp)"
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_logfile" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_VERSION="${_BUNDLE}"

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
