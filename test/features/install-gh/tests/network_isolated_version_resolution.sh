#!/usr/bin/env bash
# Verify that gh installation fails when the network is blocked (version
# resolution requires the GitHub Releases API).
# The base image (built by run-linux.sh) pre-installs feature dependencies.
set -euo pipefail

# shellcheck source=test/support/assert.sh
source dev-container-features-test-lib

reportResults
