#!/usr/bin/env bash
# get/bundle_pinned.sh — Verify SYSSET_VERSION is ignored in installer runtime.
#
# What this tests:
#   • Setting SYSSET_VERSION has no effect on local-path feature installs.
#   • Feature-mode local path short-circuits remote resolution/fetch.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_TMP="$(mktemp -d)"
trap 'rm -rf "${_TMP}"' EXIT

mkdir -p "${_TMP}/feature"
tar -xzf "${REPO_ROOT}/dist/sysset-install-pixi.tar.gz" -C "${_TMP}/feature"
export SYSSET_VERSION="v99.99.0-test"
check "install.sh local-path install succeeds even when SYSSET_VERSION is set" \
  sudo -E bash "${REPO_ROOT}/install.sh" "${_TMP}/feature"

check "pixi binary present in PATH after local-path install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
