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
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

check "dist/ does not contain install.sh" test ! -f "${DIST}/install.sh"
check "dist/scripts/ absent after build" test ! -d "${DIST}/scripts"
check "repo root install.sh exists" test -f "${REPO_ROOT}/install.sh"
check "repo root install.bash exists" test -f "${REPO_ROOT}/install.bash"

# spot-check a few features
for _feat in install-pixi install-os-pkg setup-user; do
  check "devfeats-${_feat}.tar.gz exists" test -f "${DIST}/devfeats-${_feat}.tar.gz"
  check "devfeats-${_feat}: contains install.bash" \
    bash -c "tar -tzf '${DIST}/devfeats-${_feat}.tar.gz' | grep -q 'install\.bash'"
  check "devfeats-${_feat}: contains _lib/" \
    bash -c "tar -tzf '${DIST}/devfeats-${_feat}.tar.gz' | grep -q '_lib/'"
  check "devfeats-${_feat}: contains devcontainer-feature.json" \
    bash -c "tar -tzf '${DIST}/devfeats-${_feat}.tar.gz' | grep -q 'devcontainer-feature\.json'"
done

_f0="install-pixi"
_ver="$(grep -E '^[[:space:]]*version:' "${REPO_ROOT}/features/${_f0}/metadata.yaml" | head -1 | awk '{print $2}')"
_kit_mirror="$(mktemp -d)"
trap 'rm -rf "${_kit_mirror}"' EXIT
offline_kit_publish_mirror "${_kit_mirror}" "v0.0.777-disttest" "${DIST}" "${_f0}:${_ver}"
check "offline kit tarball exists" test -f "${_kit_mirror}/v0.0.777-disttest/devfeats-v0.0.777-disttest.tar.gz"

reportResults
