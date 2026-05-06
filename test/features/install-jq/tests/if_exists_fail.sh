#!/bin/bash
# Ensures if_exists=fail exits non-zero when jq already exists.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

fail_check "if_exists=fail exits non-zero when jq exists" \
  bash "${REPO_ROOT}/src/install-jq/install.bash" --method auto --if_exists fail

check "preinstalled jq remains available" command -v jq

reportResults
