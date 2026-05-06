#!/usr/bin/env bash
# Verify that passing an unknown method value causes the installer to exit non-zero.
set -euo pipefail

# shellcheck source=test/support/assert.sh
source dev-container-features-test-lib

fail_check "invalid method value exits non-zero" \
  bash "${REPO_ROOT}/src/install-gh/install.bash" --method invalid

reportResults
