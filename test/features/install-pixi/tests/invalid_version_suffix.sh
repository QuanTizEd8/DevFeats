#!/usr/bin/env bash
# Verify that a version string with an invalid suffix (e.g. "1.2beta") is rejected
# by the semver validator — only X.Y or X.Y.Z with digits are accepted.
set -euo pipefail

source dev-container-features-test-lib

reportResults
