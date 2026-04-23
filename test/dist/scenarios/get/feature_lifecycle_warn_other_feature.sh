#!/usr/bin/env bash
# get/feature_lifecycle_warn_other_feature.sh —
# Verify that --no-feature-lifecycle-command <other-feature-id>:<phase> in
# feature mode emits a warning and is otherwise ignored (the installed
# feature's lifecycle continues to run normally).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="install-os-pkg"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-feature-warn"
mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

_PORT=18538
_log="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_log"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
unset SYSSET_VERSION

check "get.sh ignores disable entry for a different feature id (with warning)" \
  sudo -E bash "${REPO_ROOT}/get.sh" --logfile "$_log" \
    --no-feature-lifecycle-command "install-pixi:postCreateCommand" \
    "${_FEAT}@${_VER}"

check "warning was emitted about mismatched feature id" \
  bash -c "grep -Eq 'references a different feature|installed:' '$_log'"

reportResults
