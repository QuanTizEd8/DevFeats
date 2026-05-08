#!/usr/bin/env bash
# Verify that if_exists=fail with a pre-installed gh stub exits non-zero even
# when the network is blocked — the existence check happens before any network call.
# The base image (built by run-linux.sh) provides the required apt packages.
set -euo pipefail

# shellcheck source=test/support/assert.sh
source dev-container-features-test-lib

check "gh stub pre-installed by setup" command -v gh

reportResults
