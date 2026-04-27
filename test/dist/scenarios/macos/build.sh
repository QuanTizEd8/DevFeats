#!/usr/bin/env bash
# macos/build.sh — Verify that build-artifacts.sh produces correct artifacts on macOS.
#
# Checks the same layout as build/default.sh but run natively on a macOS runner.
# macOS ships BSD tar (gtar may not be present); test uses system tar.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"
DIST="${REPO_ROOT}/dist"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

check "dist/sysset-all.tar.gz exists" test -f "${DIST}/sysset-all.tar.gz"
check "dist/ does not contain install.sh" test ! -f "${DIST}/install.sh"
check "dist/scripts/ absent after build" test ! -d "${DIST}/scripts"
check "repo root install.sh exists" test -f "${REPO_ROOT}/install.sh"
check "repo root install.bash exists" test -f "${REPO_ROOT}/install.bash"

# spot-check a few features
for _feat in install-pixi install-os-pkg setup-user; do
  check "sysset-${_feat}.tar.gz exists" test -f "${DIST}/sysset-${_feat}.tar.gz"
  check "sysset-${_feat}: contains install.bash" \
    bash -c "tar -tzf '${DIST}/sysset-${_feat}.tar.gz' | grep -q 'install\.bash'"
  check "sysset-${_feat}: contains _lib/" \
    bash -c "tar -tzf '${DIST}/sysset-${_feat}.tar.gz' | grep -q '_lib/'"
  check "sysset-${_feat}: contains devcontainer-feature.json" \
    bash -c "tar -tzf '${DIST}/sysset-${_feat}.tar.gz' | grep -q 'devcontainer-feature\.json'"
done

check "sysset-all: does NOT contain scripts/sysset.sh" \
  bash -c "! tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'sysset\.sh'"

reportResults
