#!/usr/bin/env bash
# Ensures if_exists=fail exits non-zero when devcontainer already exists.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "if_exists=fail exits non-zero when devcontainer exists" \
  bash "${REPO_ROOT}/src/install-devcontainer-cli/install.bash" --method script --if_exists fail

check "preinstalled devcontainer remains available" command -v devcontainer

reportResults
