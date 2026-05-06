#!/bin/bash
# Ensures if_exists=fail exits non-zero when shfmt already exists.
set -e

source dev-container-features-test-lib

fail_check "if_exists=fail exits non-zero when shfmt exists" \
  bash "${REPO_ROOT}/src/install-shfmt/install.bash" --method auto --if_exists fail

check "preinstalled shfmt remains available" command -v shfmt

reportResults
