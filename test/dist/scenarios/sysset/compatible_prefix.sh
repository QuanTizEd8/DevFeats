#!/usr/bin/env bash
# devfeats/compatible_prefix.sh — Verify that OCI feature keys from any registry
# prefix are accepted and installed.
#
# What this tests:
#   • OCI keys outside `ghcr.io/quantized8/devfeats/` are not filtered out.
#   • Mixed-prefix manifests install successfully when referenced feature IDs
#     are valid OCI refs pointing to the local test registry.
#
# Note: only `ghcr.io/${SYSSET_GHCR_NAMESPACE}/` refs are auto-redirected to
# SYSSET_REGISTRY_HOST. For external-prefix refs we use the registry host
# directly in the manifest key.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"
_VER="99.99.0-test"

_PORT=18547
_manifest_dir="$(mktemp -d)"
_log_file="$(mktemp)"
trap 'stop_file_server; rm -rf "$_manifest_dir" "$_log_file"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

# Push install-pixi under the "example/features" org on the local registry
# (simulates a non-devfeats OCI prefix that is NOT auto-redirected).
push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "example/features/install-pixi:${_VER}" \
  "${DIST}/devfeats-install-pixi.tar.gz"

# Push install-os-pkg under the devfeats namespace (gets auto-redirected).
push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/devfeats/install-os-pkg:${_VER}" \
  "${DIST}/devfeats-install-os-pkg.tar.gz"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "compat-prefix test",
  "features": {
    "${SYSSET_REGISTRY_HOST}/example/features/install-pixi:${_VER}": { "version": "0.66.0" },
    "ghcr.io/quantized8/devfeats/install-os-pkg:${_VER}": { "manifest": "${_OSP}" }
  }
}
EOF

check "install.bash completes with mixed-prefix OCI keys" \
  bash "${REPO_ROOT}/install.bash" --log_file "$_log_file" "$_manifest"

check "no prefix-filter warning was emitted" \
  bash -c "! grep -q 'not devfeats-compatible\|not OCI ref or local-path feature' '$_log_file'"

check "install-pixi feature was attempted from mixed-prefix manifest" \
  bash -c "grep -q '\[install-pixi\] running install\.sh' '$_log_file'"
check "install-os-pkg sibling feature was attempted" \
  bash -c "grep -q '\[install-os-pkg\] running install\.sh' '$_log_file'"

reportResults
