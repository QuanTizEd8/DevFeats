#!/usr/bin/env bash
# Verify that requesting a nonexistent version (0.0.0) fails the source build.
#
# ospkg__run installs build deps (including curl) before the download attempt,
# so no SETUP_CMD is needed — the feature handles its own dep installation.
set -euo pipefail

# shellcheck source=test/support/assert.sh
source dev-container-features-test-lib

reportResults
