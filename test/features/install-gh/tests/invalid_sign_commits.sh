#!/usr/bin/env bash
# Verify that passing an invalid sign_commits value causes the installer to exit non-zero.
set -euo pipefail

# shellcheck source=test/support/assert.sh
source dev-container-features-test-lib

reportResults
