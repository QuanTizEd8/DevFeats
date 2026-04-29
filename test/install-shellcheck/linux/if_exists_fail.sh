#!/usr/bin/env bash
# Ensures if_exists=fail exits non-zero when shellcheck already exists.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "if_exists=fail exits non-zero when shellcheck exists" \
  bash "${REPO_ROOT}/src/install-shellcheck/install.bash" --method auto --if_exists fail

check "preinstalled shellcheck remains available" command -v shellcheck

reportResults
