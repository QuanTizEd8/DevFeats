#!/usr/bin/env bash
# devfeats/override_order.sh — Verify that overrideFeatureInstallOrder raises
# priority for earlier entries so a listed feature can run before another in
# the same round when the graph has no hard edges between them.
#
# Strategy: override lists install-pixi before install-os-pkg. With empty
# dependsOn, both are in the first round; higher priority (pixi) should run
# first. Log order should show [install-pixi] before [install-os-pkg].
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"
_VER="99.99.0-test"

_PORT=18543
_log_file="$(mktemp)"
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "$_log_file" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

for _f in install-pixi install-os-pkg; do
  push_oci_feature "${SYSSET_REGISTRY_HOST}" \
    "quantized8/devfeats/${_f}:${_VER}" \
    "${DIST}/devfeats-${_f}.tar.gz"
done

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "override-order test",
  "overrideFeatureInstallOrder": [
    "ghcr.io/quantized8/devfeats/install-pixi",
    "ghcr.io/quantized8/devfeats/install-os-pkg"
  ],
  "features": {
    "ghcr.io/quantized8/devfeats/install-pixi:${_VER}": { "version": "0.66.0" },
    "ghcr.io/quantized8/devfeats/install-os-pkg:${_VER}": { "manifest": "${_OSP}" }
  }
}
EOF

check "install.bash completes with overrideFeatureInstallOrder" \
  bash "${REPO_ROOT}/install.bash" --log_file "$_log_file" "$_manifest"

# install-pixi should appear before install-os-pkg in the log.
check "install-pixi ran before install-os-pkg (override order)" \
  bash -c '
    log="'"$_log_file"'"
    line_pixi=$(grep -n "\[install-pixi\] running install\.sh" "$log" | head -1 | cut -d: -f1)
    line_ospkg=$(grep -n "\[install-os-pkg\] running install\.sh" "$log" | head -1 | cut -d: -f1)
    [[ -n "$line_pixi" && -n "$line_ospkg" && "$line_pixi" -lt "$line_ospkg" ]]
  '

reportResults
