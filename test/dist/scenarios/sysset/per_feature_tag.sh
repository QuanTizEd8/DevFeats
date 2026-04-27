#!/usr/bin/env bash
# sysset/per_feature_tag.sh — Verify that ":tag" in the OCI features key
# pins that feature to a specific version, overriding bundle resolution.
#
# What this tests:
#   • features["ghcr.io/.../install-pixi:<tag>"] resolves directly to
#     install-pixi/<tag>/sysset-install-pixi.tar.gz on the mirror.
#   • Co-installed features without a :tag keep using the bundle mapping.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"

_BUNDLE="v99.99.0-test"
_BUNDLE_VER="99.99.0-bundle"
_PIXI_PIN="99.99.0-pin"

_MIRROR="${REPO_ROOT}/test-mirror-sysset-per-feature-tag"
mkdir -p "${_MIRROR}/${_BUNDLE}"
# Bundle points install-os-pkg at <bundle-ver>; install-pixi lives at <pin>.
mkdir -p "${_MIRROR}/install-os-pkg/${_BUNDLE_VER}"
mkdir -p "${_MIRROR}/install-pixi/${_PIXI_PIN}"
cp "${DIST}/sysset-install-os-pkg.tar.gz" "${_MIRROR}/install-os-pkg/${_BUNDLE_VER}/"
cp "${DIST}/sysset-install-pixi.tar.gz" "${_MIRROR}/install-pixi/${_PIXI_PIN}/"
cat > "${_MIRROR}/${_BUNDLE}/manifest.yaml" << EOF
bundle: ${_BUNDLE}
prior_bundle: v0.0.0
generated_at: "1970-01-01T00:00:00Z"
features:
  install-pixi: ${_BUNDLE_VER}
  install-os-pkg: ${_BUNDLE_VER}
EOF

_PORT=18545
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

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

# The bundle manifest deliberately uses a different install-pixi version at the
# bundle path; if install.bash honors the per-feature :tag, the install will
# fetch install-pixi/${_PIXI_PIN}/... and succeed. Otherwise the mirror has
# no tarball at install-pixi/${_BUNDLE_VER}/ so the install would fail.
check "install.bash honors per-feature OCI :tag over bundle mapping" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "pixi installed via per-feature pinned tag" \
  command -v pixi
check "tree installed via bundle-pinned install-os-pkg" \
  command -v tree

reportResults
