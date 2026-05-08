#!/usr/bin/env bash
# Verify that a clearly invalid version string (not X.Y or X.Y.Z) fails validation.
set -euo pipefail

source dev-container-features-test-lib

reportResults
