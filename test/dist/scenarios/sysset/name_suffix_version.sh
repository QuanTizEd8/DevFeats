#!/usr/bin/env bash
# devfeats/name_suffix_version.sh — Verify manifest name suffix is ignored.
#
# What this tests:
#   • A trailing "vX.Y.Z" in devcontainer `name` no longer drives installer
#     version resolution.
#   • Per-feature options are still applied in manifest mode.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"

_manifest_dir="$(mktemp -d)"
_pixi_dir="$(mktemp -d)"
_ospkg_dir="$(mktemp -d)"
trap 'rm -rf "$_manifest_dir" "$_pixi_dir" "$_ospkg_dir"' EXIT
tar -xzf "${DIST}/devfeats-install-pixi.tar.gz" -C "$_pixi_dir"
tar -xzf "${DIST}/devfeats-install-os-pkg.tar.gz" -C "$_ospkg_dir"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "Named bundle v99.99.0",
  "features": {
    "${_pixi_dir}": {},
    "${_ospkg_dir}": { "manifest": "${_OSP}" }
  }
}
EOF

check "install.bash ignores name suffix version and installs local-path features" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "pixi installed by devfeats (name-suffix mode)" \
  command -v pixi
check "tree installed by install-os-pkg (name-suffix mode)" \
  command -v tree

reportResults
