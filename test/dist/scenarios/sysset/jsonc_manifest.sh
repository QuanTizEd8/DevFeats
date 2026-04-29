#!/usr/bin/env bash
# sysset/jsonc_manifest.sh — Verify that install.bash accepts JSONC (comments +
# trailing commas) as devcontainer input and installs features via the
# local OCI registry.
#
# What this tests:
#   • install.bash processes a .jsonc manifest with JSONC syntax.
#   • Line and block comments, and a trailing comma, are tolerated.
#   • install-os-pkg is processed before install-pixi (graph + jq key order).
#   • Both features install successfully.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"
_VER="99.99.0-test"

check "dist has sysset-install-pixi.tar.gz" test -f "${DIST}/sysset-install-pixi.tar.gz"
check "dist has sysset-install-os-pkg.tar.gz" test -f "${DIST}/sysset-install-os-pkg.tar.gz"

_PORT=18540
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

for _f in install-pixi install-os-pkg; do
  push_oci_feature "${SYSSET_REGISTRY_HOST}" \
    "quantized8/sysset/${_f}:${_VER}" \
    "${DIST}/sysset-${_f}.tar.gz"
done

# ── Devcontainer manifest (.jsonc with comments + trailing comma) ────────────
_manifest="${_manifest_dir}/devcontainer.jsonc"
cat > "$_manifest" << EOF
// Top-level line comment — must be stripped by json__strip_jsonc_stdin.
{
  /* Block comment on the display name. */
  "name": "dist test jsonc",
  "features": {
    // Pin install-pixi explicitly via its own option.
    "ghcr.io/quantized8/sysset/install-pixi:${_VER}": { "version": "0.66.0" },
    "ghcr.io/quantized8/sysset/install-os-pkg:${_VER}": { "manifest": "${_OSP}" }, // trailing comma
  },
}
EOF

check "install.bash runs .jsonc devcontainer manifest to completion" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "pixi installed by sysset" \
  command -v pixi
check "tree installed by install-os-pkg" \
  command -v tree

reportResults
