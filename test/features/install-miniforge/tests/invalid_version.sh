#!/usr/bin/env bash
# Verify that requesting a nonexistent Miniforge version (0.0.0) fails because
# the GitHub Releases API returns no matching tag.
set -euo pipefail

source dev-container-features-test-lib

reportResults
