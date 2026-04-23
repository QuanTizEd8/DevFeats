#!/usr/bin/env bash
# get/per_feature_override.sh — Per-feature @spec overrides the bundle pin.
#
# What this tests:
#   • SYSSET_VERSION sets bundle-pinned mode.
#   • The bundle manifest lists install-pixi → <bogus>.
#   • The real @spec at the CLI (install-pixi@<working>) takes precedence.
#   • Only the working tarball is staged in the mirror, so the test would fail
#     if the bundle's version were used.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_BUNDLE="v99.99.0-test"
_BOGUS_VER="0.0.99"   # listed in bundle manifest, but no tarball at this path
_GOOD_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-per-feature-override"

mkdir -p "${_MIRROR}/${_BUNDLE}"
mkdir -p "${_MIRROR}/install-pixi/${_GOOD_VER}"

cat > "${_MIRROR}/${_BUNDLE}/manifest.yaml" << EOF
bundle: ${_BUNDLE}
prior_bundle: v0.0.0
generated_at: "1970-01-01T00:00:00Z"
features:
  install-pixi: ${_BOGUS_VER}
EOF

cp "${REPO_ROOT}/dist/sysset-install-pixi.tar.gz" \
  "${_MIRROR}/install-pixi/${_GOOD_VER}/"

_PORT=18535
trap 'stop_file_server; rm -rf "${_MIRROR}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_VERSION="${_BUNDLE}"

check "get.sh installs install-pixi@${_GOOD_VER} overriding bundle manifest (${_BOGUS_VER})" \
  sudo -E bash "${REPO_ROOT}/get.sh" "install-pixi@${_GOOD_VER}"

check "pixi binary present in PATH after override install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
