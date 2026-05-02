#!/usr/bin/env bash
# get/per_feature_override.sh — Local path install ignores SYSSET_VERSION.
#
# What this tests:
#   • Local-path feature installs short-circuit remote resolution.
#   • SYSSET_VERSION being set does not alter local-path install behavior.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
_TMP="$(mktemp -d)"
trap 'rm -rf "${_TMP}"' EXIT
mkdir -p "${_TMP}/feature"
tar -xzf "${REPO_ROOT}/dist/devfeats-install-pixi.tar.gz" -C "${_TMP}/feature"
export SYSSET_VERSION="v99.99.0-test"

check "install.sh local-path install succeeds while SYSSET_VERSION is set" \
  sudo -E bash "${REPO_ROOT}/install.sh" "${_TMP}/feature"

check "pixi binary present in PATH after override install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
