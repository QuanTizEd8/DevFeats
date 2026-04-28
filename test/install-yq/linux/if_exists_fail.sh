#!/usr/bin/env bash
# Ensures if_exists=fail exits non-zero when yq already exists.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "if_exists=fail exits non-zero when yq exists" \
  bash "${REPO_ROOT}/src/install-yq/install.bash" --method auto --if_exists fail

check "preinstalled yq remains available" command -v yq

reportResults
