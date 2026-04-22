#!/usr/bin/env bash
# get/install_pixi.sh — Verify that get.sh can download and install install-pixi
# using a local HTTP file server as the release download origin.
#
# What this tests:
#   • SYSSET_BASE_URL override directs downloads to the local server.
#   • get.sh extracts the tarball and runs the bootstrap correctly.
#   • The installed binary (pixi) is present afterwards.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

# ── Start local file server on an ephemeral port ──────────────────────────────
# Serve the repo root so both get.bash/lib/ (SYSSET_RAW_BASE) and the feature
# tarballs under dist/ (SYSSET_BASE_URL) are reachable from a single server.
_PORT=18531

# Create a versioned subdirectory so get.bash can resolve the URL as
# ${SYSSET_BASE_URL}/${SYSSET_VERSION}/sysset-<feature>.tar.gz.
_TEST_VERSION="${SYSSET_BUILD_VERSION:-v0.1.0-test}"
mkdir -p "${REPO_ROOT}/dist/${_TEST_VERSION}"
cp "${REPO_ROOT}/dist"/sysset-*.tar.gz "${REPO_ROOT}/dist/${_TEST_VERSION}/"
trap 'stop_file_server; rm -rf "${REPO_ROOT}/dist/${_TEST_VERSION}"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/dist"
export SYSSET_VERSION="$_TEST_VERSION"

# ── Run get.sh ────────────────────────────────────────────────────────────────
# install-pixi requires root (ospkg__require_root); installs pixi to /usr/local/bin.
check "get.sh installs install-pixi successfully" \
  sudo -E bash "${REPO_ROOT}/get.sh" install-pixi

check "pixi binary present in PATH after install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
