#!/usr/bin/env bash
# get/forward_options.sh — Verify feature-install options are forwarded
# verbatim by install.sh to the feature's install.sh (rolling mode with explicit :version).
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
_PORT=18532
trap 'stop_file_server' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/sysset/${_FEAT}:${_VER}" \
  "${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz"

check "install.sh installs pixi with explicit --version (forwarded)" \
  sudo -E bash "${REPO_ROOT}/install.sh" "${_FEAT}:${_VER}" \
  --version "$_PIXI_VERSION" --if_exists reinstall

check "installed pixi reports expected version" \
  bash -c "pixi --version | grep -q '${_PIXI_VERSION}'"

reportResults
