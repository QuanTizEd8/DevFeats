#!/usr/bin/env bash
# get/forward_options.sh — Verify that feature-install options are forwarded
# verbatim by get.sh to the feature's install.sh.
#
# Strategy: pass --version <specific_version> to install-pixi and confirm the
# installed binary reports that exact version.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_PIXI_VERSION="0.41.4"

_PORT=18532

_TEST_VERSION="${SYSSET_BUILD_VERSION:-v0.1.0-test}"
mkdir -p "${REPO_ROOT}/dist/${_TEST_VERSION}"
cp "${REPO_ROOT}/dist"/sysset-*.tar.gz "${REPO_ROOT}/dist/${_TEST_VERSION}/"
trap 'stop_file_server; rm -rf "${REPO_ROOT}/dist/${_TEST_VERSION}"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/dist"
export SYSSET_VERSION="$_TEST_VERSION"

check "get.sh installs pixi with explicit --version" \
  sudo -E bash "${REPO_ROOT}/get.sh" install-pixi \
  --version "$_PIXI_VERSION"

check "installed pixi reports expected version" \
  bash -c "pixi --version | grep -q '${_PIXI_VERSION}'"

reportResults
