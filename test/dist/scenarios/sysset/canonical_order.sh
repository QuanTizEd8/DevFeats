#!/usr/bin/env bash
# sysset/canonical_order.sh — Verify that install.bash orders features using the
# graph (and jq key order / priorities), with install-os-pkg before install-pixi
# when there is no override privileging pixi.
#
# Strategy: use a devcontainer with both features. Log lines
# "ℹ️  [install-os-pkg]…" and "ℹ️  [install-pixi]…" record install order.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"

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
_log_file="$(mktemp)"
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_log_file" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "canonical ${_BUNDLE}",
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi": { "version": "0.66.0" },
    "ghcr.io/quantized8/sysset/install-os-pkg": { "manifest": "${_OSP}" }
  }
}
EOF

check "install.bash completes with canonical-order manifest" \
  bash "${REPO_ROOT}/install.bash" --log_file "$_log_file" "$_manifest"

# In the log, install-os-pkg should appear before install-pixi.
# NOTE: Use the "running install.sh" marker to match only the installation
# phase, not the staging phase (which logs [feature-id] in alphabetical order).
check "install-os-pkg ran before install-pixi" \
  bash -c '
    log="'"$_log_file"'"
    line_ospkg=$(grep -n "\[install-os-pkg\] running install\.sh" "$log" | head -1 | cut -d: -f1)
    line_pixi=$(grep -n "\[install-pixi\] running install\.sh" "$log" | head -1 | cut -d: -f1)
    [[ -n "$line_ospkg" && -n "$line_pixi" && "$line_ospkg" -lt "$line_pixi" ]]
  '

reportResults
