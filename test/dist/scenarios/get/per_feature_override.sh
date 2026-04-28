#!/usr/bin/env bash
# get/per_feature_override.sh — Per-feature :spec overrides the bundle pin.
#
# What this tests:
#   • SYSSET_VERSION sets bundle-pinned mode.
#   • The bundle manifest lists install-pixi → <bogus>.
#   • The real CLI spec (install-pixi:<working>) takes precedence.
#   • Only the working tarball is staged in the mirror, so the test would fail
#     if the bundle's version were used.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

_BUNDLE="v99.99.0-test"
_BOGUS_VER="0.0.99" # listed in bundle manifest, but no tarball at this path
_GOOD_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-per-feature-override"

mkdir -p "${_MIRROR}"
mkdir -p "${_MIRROR}/install-pixi/${_GOOD_VER}"

offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${REPO_ROOT}/dist" "install-pixi:${_BOGUS_VER}"

cp "${REPO_ROOT}/dist/sysset-install-pixi.tar.gz" \
  "${_MIRROR}/install-pixi/${_GOOD_VER}/"

_PORT=18535
trap 'stop_file_server; rm -rf "${_MIRROR}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

check "install.sh installs install-pixi:${_GOOD_VER} overriding bundle manifest (${_BOGUS_VER})" \
  sudo -E bash "${REPO_ROOT}/install.sh" "install-pixi:${_GOOD_VER}"

check "pixi binary present in PATH after override install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
