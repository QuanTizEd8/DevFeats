#!/usr/bin/env bash
# sysset/name_suffix_version.sh — Verify that a trailing "vX.Y.Z" inside the
# devcontainer `name` field drives bundle-pinned resolution (no SYSSET_VERSION).
#
# What this tests:
#   • devcontainer__name_version_suffix extracts the trailing vX.Y.Z.
#   • install.bash uses the extracted version as the bundle spec when SYSSET_VERSION
#     is not set, fetches the bundle kit and installs per-feature
#     versions listed there.
#   • Per-feature versions in the manifest (not the bundle tag itself) govern
#     the downloaded tarball URLs.
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

# Use a plain vX.Y.Z suffix (no pre-release tail) so str__extract_version_suffix
# matches ^v[0-9]+\.[0-9]+\.[0-9]+$.
_BUNDLE="v99.99.0"
_VER="99.99.0-name"
_MIRROR="${REPO_ROOT}/test-mirror-sysset-name-suffix"
mkdir -p "${_MIRROR}"
for _f in install-pixi install-os-pkg; do
  mkdir -p "${_MIRROR}/${_f}/${_VER}"
  cp "${DIST}/sysset-${_f}.tar.gz" "${_MIRROR}/${_f}/${_VER}/"
done
offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${DIST}" \
  "install-pixi:${_VER}" "install-os-pkg:${_VER}"

_PORT=18544
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
# SYSSET_VERSION is intentionally unset — the bundle must be pinned via the
# vX.Y.Z suffix inside the "name" field.
unset SYSSET_VERSION

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "Named bundle ${_BUNDLE}",
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi": { "version": "0.66.0" },
    "ghcr.io/quantized8/sysset/install-os-pkg": { "manifest": "${_OSP}" }
  }
}
EOF

check "install.bash uses name-suffix version to drive bundle pin" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "pixi installed by sysset (name-suffix mode)" \
  command -v pixi
check "tree installed by install-os-pkg (name-suffix mode)" \
  command -v tree

reportResults
