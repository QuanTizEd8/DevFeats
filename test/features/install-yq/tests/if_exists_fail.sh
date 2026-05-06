#!/usr/bin/env bash
# Ensures if_exists=fail exits non-zero when yq already exists.
set -e

source dev-container-features-test-lib

fail_check "if_exists=fail exits non-zero when yq exists" \
  bash "${REPO_ROOT}/src/install-yq/install.bash" --method auto --if_exists fail

check "preinstalled yq remains available" command -v yq

reportResults
