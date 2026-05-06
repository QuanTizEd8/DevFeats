#!/usr/bin/env bash
# Verify that a clearly invalid version string (not X.Y or X.Y.Z) fails validation.
set -euo pipefail

source dev-container-features-test-lib

fail_check "invalid version string 'not_a_semver_string' exits non-zero" \
  bash "${REPO_ROOT}/src/install-pixi/install.bash" \
  --version not_a_semver_string

reportResults
