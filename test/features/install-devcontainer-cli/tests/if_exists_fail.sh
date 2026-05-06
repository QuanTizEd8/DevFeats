#!/bin/bash
# Ensures if_exists=fail exits non-zero when devcontainer already exists.
set -e

source dev-container-features-test-lib

fail_check "if_exists=fail exits non-zero when devcontainer exists" \
  bash "${REPO_ROOT}/src/install-devcontainer-cli/install.bash" --method script --if_exists fail

check "preinstalled devcontainer remains available" command -v devcontainer

reportResults
