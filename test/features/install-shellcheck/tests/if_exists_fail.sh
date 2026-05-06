#!/bin/bash
# Ensures if_exists=fail exits non-zero when shellcheck already exists.
set -e

source dev-container-features-test-lib

fail_check "if_exists=fail exits non-zero when shellcheck exists" \
  bash "${REPO_ROOT}/src/install-shellcheck/install.bash" --method auto --if_exists fail

check "preinstalled shellcheck remains available" command -v shellcheck

reportResults
