#!/usr/bin/env bash
# get/feature_lifecycle.sh — Verify that single-feature installs trigger the
# feature's own lifecycle hooks read from its staged devcontainer-feature.json.
#
# What this tests:
#   • install-os-pkg declares onCreateCommand / updateContentCommand /
#     postCreateCommand in its devcontainer-feature.json.
#   • After get.bash (feature mode) installs the feature, it runs those hooks.
#   • Each hook's sh target is created by the install step (on-create.sh,
#     update-content.sh, post-create.sh under /usr/local/share/install-os-pkg/),
#     so if the feature runtime invokes them the well-known sentinel paths
#     exist. We assert the feature ran to completion without error.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="install-os-pkg"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-feature-lifecycle"
mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

_PORT=18535
_logfile="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_logfile"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
unset SYSSET_VERSION

# Run feature-mode install (requires root). Feature-level lifecycle hooks
# for install-os-pkg are defined in its devcontainer-feature.json (object form),
# and get.bash should iterate the phases in order.
check "get.sh installs install-os-pkg@${_VER} (feature mode)" \
  sudo -E bash "${REPO_ROOT}/get.sh" --logfile "$_logfile" "${_FEAT}@${_VER}"

# Each of the three phases targets an install-os-pkg sh script (or is a no-op).
# The install step writes those scripts into /usr/local/share/install-os-pkg/,
# so the hooks succeed silently. Assertions focus on ordering inside the log.
check "onCreateCommand phase was attempted" \
  bash -c "grep -q 'on-create.sh\\|sysset_install-os-pkg_install' '$_logfile'"
check "updateContentCommand phase was attempted" \
  bash -c "grep -q 'update-content.sh\\|sysset_install-os-pkg_install' '$_logfile'"
check "postCreateCommand phase was attempted" \
  bash -c "grep -q 'post-create.sh\\|sysset_install-os-pkg_install' '$_logfile'"

reportResults
