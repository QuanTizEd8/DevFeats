#!/bin/bash
# Ensures if_exists=fail exits non-zero when just already exists.
set -e

source dev-container-features-test-lib

fail_check "if_exists=fail exits non-zero when just exists" \
  bash "${REPO_ROOT}/src/install-just/install.bash" --if_exists fail

check "preinstalled just remains available" command -v just

reportResults
