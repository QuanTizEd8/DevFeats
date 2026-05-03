#!/usr/bin/env bash
# Ensures if_exists=fail exits non-zero when jq already exists.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/support/assert.sh
source "${REPO_ROOT}/test/support/assert.sh"

fail_check "if_exists=fail exits non-zero when jq exists" \
  bash "${REPO_ROOT}/src/install-jq/install.bash" --method auto --if_exists fail

check "preinstalled jq remains available" command -v jq

reportResults
