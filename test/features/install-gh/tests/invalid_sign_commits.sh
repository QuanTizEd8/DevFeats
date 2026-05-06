#!/usr/bin/env bash
# Verify that passing an invalid sign_commits value causes the installer to exit non-zero.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

fail_check "invalid sign_commits value exits non-zero" \
  bash "${REPO_ROOT}/src/install-gh/install.bash" --sign_commits invalid

reportResults
