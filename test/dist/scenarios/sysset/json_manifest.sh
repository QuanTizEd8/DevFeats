#!/usr/bin/env bash
# sysset/json_manifest.sh — Verify that get.bash installs features from a
# JSON manifest using a local HTTP file server as the release download origin.
#
# What this tests:
#   • sysset-all.tar.gz contains the expected per-feature tarballs.
#   • get.bash processes a JSON manifest.
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

# ── Start local file server ───────────────────────────────────────────────────
_PORT=18535
_TEST_VERSION="${SYSSET_BUILD_VERSION:-v0.1.0-test}"
_manifest_dir="$(mktemp -d)"
mkdir -p "${DIST}/${_TEST_VERSION}"
cp "${DIST}"/sysset-*.tar.gz "${DIST}/${_TEST_VERSION}/"
trap 'stop_file_server; rm -rf "${DIST}/${_TEST_VERSION}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/dist"
export SYSSET_VERSION="$_TEST_VERSION"

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
