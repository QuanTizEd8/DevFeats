#!/usr/bin/env bash
# sysset/per_feature_tag.sh — Verify that ":tag" in the OCI features key
# pins that feature to a specific version.
#
# What this tests:
#   • features["ghcr.io/.../install-pixi:<tag>"] resolves directly to
#     install-pixi/<tag>/sysset-install-pixi.tar.gz on the mirror.
#   • Co-installed features without a :tag resolve independently.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"

_BUNDLE="v99.99.0-test"
_BUNDLE_VER="99.99.0-bundle"
_PIXI_PIN="99.99.0-pin"

_MIRROR="${REPO_ROOT}/test-mirror-sysset-per-feature-tag"
mkdir -p "${_MIRROR}"
# Bundle points install-os-pkg at <bundle-ver>; install-pixi lives at <pin>.
mkdir -p "${_MIRROR}/install-os-pkg/${_BUNDLE_VER}"
mkdir -p "${_MIRROR}/install-pixi/${_PIXI_PIN}"
cp "${DIST}/sysset-install-os-pkg.tar.gz" "${_MIRROR}/install-os-pkg/${_BUNDLE_VER}/"
cp "${DIST}/sysset-install-pixi.tar.gz" "${_MIRROR}/install-pixi/${_PIXI_PIN}/"
offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${DIST}" \
  "install-pixi:${_BUNDLE_VER}" "install-os-pkg:${_BUNDLE_VER}"

_PORT=18545
_manifest_dir="$(mktemp -d)"
_log_file="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir" "$_log_file"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
# Fake ORAS tags are static by default; declare the scenario-specific pin.
export SYSSET_TEST_FAKE_ORAS_EXTRA_TAGS="${_PIXI_PIN}"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "per-feature tag ${_BUNDLE}",
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:${_PIXI_PIN}": { "version": "0.66.0" },
    "ghcr.io/quantized8/sysset/install-os-pkg": { "manifest": "${_OSP}" }
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
