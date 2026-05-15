#!/usr/bin/env bash
# Verify that a version string with an invalid suffix (e.g. "1.2beta") is rejected
# by github__resolve_version — no stable release will match the spec.
set -euo pipefail

source dev-container-features-test-lib

reportResults
