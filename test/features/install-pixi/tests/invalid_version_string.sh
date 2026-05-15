#!/usr/bin/env bash
# Verify that a clearly invalid version string (not a numeric spec) fails resolution.
set -euo pipefail

source dev-container-features-test-lib

reportResults
