#!/usr/bin/env bash
# Ensures if_exists=fail exits non-zero when just already exists.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "if_exists=fail exits non-zero when just exists" \
  bash "${REPO_ROOT}/src/install-just/install.bash" --if_exists fail

check "preinstalled just remains available" command -v just

reportResults
