#!/usr/bin/env bash
# get/bundle_pinned.sh — Bundle-pinned resolution via SYSSET_VERSION.
#
# What this tests:
#   • SYSSET_VERSION=<bundle-tag> drives bundle-pinned mode.
#   • install.bash downloads sysset-v<bundle>.tar.gz from the mirror and reads
#     manifest.json from that kit.
#   • Per-feature versions are read from the manifest and used to construct
#     <feature>/<X.Y.Z>/sysset-<feature>.tar.gz URLs.
#   • The mirror also hosts a foreign feature's tag (install-shell/0.1.0) to
#     verify that install.bash ignores unrelated features present in the mirror.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

_BUNDLE="v99.99.0-test"
_PIXI_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-bundle-pinned"

mkdir -p "${_MIRROR}/${_BUNDLE}"
mkdir -p "${_MIRROR}/install-pixi/${_PIXI_VER}"
mkdir -p "${_MIRROR}/install-shell/0.1.0"

offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${REPO_ROOT}/dist" \
  "install-pixi:${_PIXI_VER}"

cp "${REPO_ROOT}/dist/sysset-install-pixi.tar.gz" \
  "${_MIRROR}/install-pixi/${_PIXI_VER}/"
if [[ -f "${REPO_ROOT}/dist/sysset-install-shell.tar.gz" ]]; then
  cp "${REPO_ROOT}/dist/sysset-install-shell.tar.gz" \
    "${_MIRROR}/install-shell/0.1.0/"
fi

_PORT=18534
trap 'stop_file_server; rm -rf "${_MIRROR}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

check "install.sh installs install-pixi via bundle-pinned kit (${_BUNDLE} → ${_PIXI_VER})" \
  sudo -E bash "${REPO_ROOT}/install.sh" install-pixi

check "pixi binary present in PATH after bundle-pinned install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
