#!/usr/bin/env bash
# sysset/jsonc_manifest.sh — Verify that install.bash accepts JSONC (comments +
# trailing commas) as devcontainer input and installs features via the
# local HTTP mirror.
#
# What this tests:
#   • Per-feature dist tarballs exist for the mirror.
#   • install.bash processes a .jsonc manifest with SYSSET_VERSION bundle pin.
#   • Line and block comments, and a trailing comma, are tolerated.
#   • Bundle-pinned resolution reads per-feature versions from the kit manifest.json.
#   • install-os-pkg is processed before install-pixi (graph + jq key order;
#     log markers [install-*] are emitted per feature).
#   • Both features install successfully (verified via installed artifacts).
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

check "dist has sysset-install-pixi.tar.gz" test -f "${DIST}/sysset-install-pixi.tar.gz"
check "dist has sysset-install-os-pkg.tar.gz" test -f "${DIST}/sysset-install-os-pkg.tar.gz"

# ── Mirror setup (bundle-pinned layout) ──────────────────────────────────────
_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-sysset-jsonc"
mkdir -p "${_MIRROR}"
for _f in install-pixi install-os-pkg; do
  mkdir -p "${_MIRROR}/${_f}/${_VER}"
  cp "${DIST}/sysset-${_f}.tar.gz" "${_MIRROR}/${_f}/${_VER}/"
done
offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${DIST}" \
  "install-pixi:${_VER}" "install-os-pkg:${_VER}"

_PORT=18540
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

# ── Devcontainer manifest (.jsonc with comments + trailing comma) ────────────
_manifest="${_manifest_dir}/devcontainer.jsonc"
cat > "$_manifest" << EOF
// Top-level line comment — must be stripped by json__strip_jsonc_stdin.
{
  /* Block comment on the display name. */
  "name": "dist test ${_BUNDLE}",
  "features": {
    // Pin install-pixi explicitly via its own option.
    "ghcr.io/quantized8/sysset/install-pixi": { "version": "0.66.0" },
    "ghcr.io/quantized8/sysset/install-os-pkg": { "manifest": "${_OSP}" }, // trailing comma after this entry
  },
}
EOF

# ── Run install.bash in manifest mode ─────────────────────────────────────────────
check "install.bash runs .jsonc devcontainer manifest to completion" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "pixi installed by sysset" \
  command -v pixi
check "tree installed by install-os-pkg" \
  command -v tree
reportResults
