#!/usr/bin/env bash
# get/forward_options.sh — Verify feature-install options are forwarded
# verbatim by get.sh to the feature's install.sh (rolling mode with @spec).
#
# Strategy: pass --version <specific_version> to install-pixi and confirm the
# installed binary reports that exact version.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_PIXI_VERSION="0.41.4"
_FEAT="install-pixi"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-forward-options"
mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

_PORT=18532
trap 'stop_file_server; rm -rf "${_MIRROR}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
unset SYSSET_VERSION

check "get.sh installs pixi with explicit --version (forwarded)" \
  sudo -E bash "${REPO_ROOT}/get.sh" "${_FEAT}@${_VER}" \
  --version "$_PIXI_VERSION"

check "installed pixi reports expected version" \
  bash -c "pixi --version | grep -q '${_PIXI_VERSION}'"

reportResults
