#!/usr/bin/env bash
# sysset/per_feature_tag.sh — Verify that ":tag" in the OCI features key
# pins that feature to a specific version.
#
# What this tests:
#   • features["ghcr.io/.../install-pixi:<pin-tag>"] resolves directly to
#     that tag on the local registry.
#   • Co-installed features with a different :tag resolve independently.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"
_PIXI_PIN="99.99.0-pin"
_BUNDLE_VER="99.99.0-bundle"

_PORT=18545
_manifest_dir="$(mktemp -d)"
_log_file="$(mktemp)"
trap 'stop_file_server; rm -rf "$_manifest_dir" "$_log_file"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

# Push install-pixi at the pinned tag; install-os-pkg at the bundle tag.
push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/sysset/install-pixi:${_PIXI_PIN}" \
  "${DIST}/sysset-install-pixi.tar.gz"
push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/sysset/install-os-pkg:${_BUNDLE_VER}" \
  "${DIST}/sysset-install-os-pkg.tar.gz"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "per-feature-tag test",
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:${_PIXI_PIN}": { "version": "0.66.0" },
    "ghcr.io/quantized8/sysset/install-os-pkg:${_BUNDLE_VER}": { "manifest": "${_OSP}" }
  }
}
EOF

check "install.bash honors per-feature OCI :tag on key" \
  bash "${REPO_ROOT}/install.bash" --log_file "$_log_file" "$_manifest"

check "no missing-tag resolver error was emitted" \
  bash -c "! grep -q \"no tag found for spec '${_PIXI_PIN}'\" '$_log_file'"

check "pixi installed via per-feature pinned tag" \
  command -v pixi
check "tree installed via bundle-pinned install-os-pkg" \
  command -v tree

reportResults
