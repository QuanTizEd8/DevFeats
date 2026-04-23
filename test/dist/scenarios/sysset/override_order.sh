#!/usr/bin/env bash
# sysset/override_order.sh — Verify that overrideFeatureInstallOrder raises
# priority for earlier entries so a listed feature can run before another in
# the same round when the graph has no hard edges between them.
#
# Strategy: override lists install-pixi before install-os-pkg. With empty
# dependsOn, both are in the first round; higher priority (pixi) should run
# first. Log order should show [install-pixi] before [install-os-pkg].
#
# Requires: root (get.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"

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
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "override ${_BUNDLE}",
  "overrideFeatureInstallOrder": [
    "ghcr.io/quantized8/sysset/install-pixi",
    "ghcr.io/quantized8/sysset/install-os-pkg"
  ],
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi": { "version": "0.66.0" },
    "ghcr.io/quantized8/sysset/install-os-pkg": { "manifest": "${_OSP}" }
  }
}
EOF

check "get.bash completes with overrideFeatureInstallOrder" \
  bash "${REPO_ROOT}/get.bash" --logfile "$_logfile" "$_manifest"

# install-pixi should appear before install-os-pkg in the log.
check "install-pixi ran before install-os-pkg (override order)" \
  bash -c '
    log="'"$_logfile"'"
    line_pixi=$(grep -n "\[install-pixi\]" "$log" | head -1 | cut -d: -f1)
    line_ospkg=$(grep -n "\[install-os-pkg\]" "$log" | head -1 | cut -d: -f1)
    [[ -n "$line_pixi" && -n "$line_ospkg" && "$line_pixi" -lt "$line_ospkg" ]]
  '

reportResults
