#!/usr/bin/env bash
# get/bad_feature.sh — Verify that install.sh exits non-zero when the requested
# feature is unknown.
#
# With SYSSET_REGISTRY_HOST pointing to the local test registry, a ref for a
# feature that was never pushed fails at tag resolution (oras repo tags returns
# empty for a non-existent repo).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_PORT=18533
trap 'stop_file_server' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

# "does-not-exist" was never pushed — install.sh should exit non-zero.
fail_check "install.sh exits non-zero for unknown feature" \
  bash "${REPO_ROOT}/install.sh" does-not-exist

reportResults
