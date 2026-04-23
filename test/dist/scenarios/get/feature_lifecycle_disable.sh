#!/usr/bin/env bash
# get/feature_lifecycle_disable.sh — Verify --no-lifecycle and
# --no-feature-lifecycle-command suppress lifecycle hooks in feature mode.
#
# What this tests:
#   • --no-lifecycle (feature-mode-only shorthand) is equivalent to
#     --no-feature-lifecycle-command all — no hook is executed.
#   • --no-feature-lifecycle-command <phase> suppresses one phase (and leaves
#     the install itself intact).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="install-os-pkg"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-feature-lifecycle-disable"
mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

_PORT=18536
_log1="$(mktemp)"
_log2="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_log1" "$_log2"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
unset SYSSET_VERSION

# ── 1. --no-lifecycle skips every feature-level phase ───────────────────────
check "get.sh install-os-pkg@${_VER} --no-lifecycle" \
  sudo -E bash "${REPO_ROOT}/get.sh" --logfile "$_log1" --no-lifecycle "${_FEAT}@${_VER}"
check "no hook markers present in log when --no-lifecycle is set" \
  bash -c "! grep -E 'onCreateCommand|updateContentCommand|postCreateCommand' '$_log1' | grep -v 'skip feature' | grep -q ."

# ── 2. --no-feature-lifecycle-command postCreateCommand skips that phase ────
check "get.sh install-os-pkg@${_VER} --no-feature-lifecycle-command postCreateCommand" \
  sudo -E bash "${REPO_ROOT}/get.sh" --logfile "$_log2" \
    --no-feature-lifecycle-command postCreateCommand "${_FEAT}@${_VER}"
check "post-create.sh was NOT invoked when that phase is disabled" \
  bash -c "! grep -q 'post-create.sh' '$_log2'"

reportResults
