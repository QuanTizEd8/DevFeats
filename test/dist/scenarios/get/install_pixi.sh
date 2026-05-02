#!/usr/bin/env bash
# get/install_pixi.sh — Feature mode with an explicit :version spec.
#
# What this tests:
#   • install.sh resolves `install-pixi:<ver>` against the local test registry.
#   • The tarball is extracted, the bootstrap runs, and pixi is installed.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="install-pixi"
_VER="99.99.0-test"
_PORT=18531
trap 'stop_file_server' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/devfeats/${_FEAT}:${_VER}" \
  "${REPO_ROOT}/dist/devfeats-${_FEAT}.tar.gz"

# install-pixi requires root (ospkg__require_root); installs pixi to /usr/local/bin.
check "install.sh installs ${_FEAT}:${_VER} successfully" \
  sudo -E bash "${REPO_ROOT}/install.sh" "${_FEAT}:${_VER}"

check "pixi binary present in PATH after install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
