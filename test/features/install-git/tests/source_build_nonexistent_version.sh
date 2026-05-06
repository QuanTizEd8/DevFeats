#!/usr/bin/env bash
# Verify that requesting a nonexistent version (0.0.0) fails the source build.
#
# ospkg__run installs build deps (including curl) before the download attempt,
# so no SETUP_CMD is needed — the feature handles its own dep installation.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

fail_check "source build: nonexistent version 0.0.0 exits non-zero" \
  bash "${REPO_ROOT}/src/install-git/install.bash" \
  --method source \
  --version 0.0.0

reportResults
