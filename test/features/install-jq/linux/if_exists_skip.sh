#!/usr/bin/env bash
# Ensures if_exists=skip succeeds when jq already exists and leaves the
# existing binary untouched.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/support/assert.sh
source "${REPO_ROOT}/test/support/assert.sh"

check "if_exists=skip exits zero when jq exists" \
  bash "${REPO_ROOT}/src/install-jq/install.bash" --method auto --if_exists skip

check "jq remains available after skip" command -v jq

# The fake binary reports 9.9.9 — confirm it was not replaced.
check "existing jq version unchanged (skip did not reinstall)" bash -c \
  'jq --version 2>&1 | grep -q "9.9.9"'

reportResults
