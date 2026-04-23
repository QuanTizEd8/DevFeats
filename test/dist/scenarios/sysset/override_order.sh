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

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-sysset-override-order"
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

_PORT=18543
_logfile="$(mktemp)"
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_logfile" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_VERSION="${_BUNDLE}"

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
