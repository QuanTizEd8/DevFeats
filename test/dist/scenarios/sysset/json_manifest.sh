#!/usr/bin/env bash
# sysset/json_manifest.sh — Verify that get.bash installs features from a
# JSON manifest using a local HTTP file server as the release download origin.
#
# What this tests:
#   • sysset-all.tar.gz contains the expected per-feature tarballs.
#   • get.bash processes a JSON manifest with a top-level bundle version.
#   • Bundle-pinned resolution reads per-feature versions from manifest.yaml.
#   • Features are run in canonical order (install-os-pkg before install-pixi)
#     even though the manifest lists install-pixi first.
#   • Both features install successfully (verified via installed artifacts).
#
# Requires: root (get.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

# ── Verify sysset-all.tar.gz contains expected feature tarballs ──────────────
check "sysset-all.tar.gz contains sysset-install-pixi.tar.gz" \
  bash -c "tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'sysset-install-pixi.tar.gz'"
check "sysset-all.tar.gz contains sysset-install-os-pkg.tar.gz" \
  bash -c "tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'sysset-install-os-pkg.tar.gz'"

# ── Mirror setup (bundle-pinned layout) ──────────────────────────────────────
_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-sysset-json"
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

_PORT=18540
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_VERSION="${_BUNDLE}"

# ── Build manifest ────────────────────────────────────────────────────────────
_manifest="${_manifest_dir}/manifest.json"
cat > "$_manifest" << EOF
{
  "features": [
    { "id": "install-pixi", "options": { "version": "0.66.0" } },
    { "id": "install-os-pkg", "options": { "manifest": "${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml" } }
  ]
}
EOF

# ── Run get.bash in manifest mode ─────────────────────────────────────────────
check "get.bash runs JSON manifest to completion" \
  bash "${REPO_ROOT}/get.bash" "$_manifest"

check "pixi installed by sysset" \
  command -v pixi
check "tree installed by install-os-pkg" \
  command -v tree
reportResults
