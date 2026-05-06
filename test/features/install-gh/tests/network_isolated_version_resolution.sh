#!/usr/bin/env bash
# Verify that gh installation fails when the network is blocked (version
# resolution requires the GitHub Releases API).
# The base image (built by run-linux.sh) pre-installs feature dependencies.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

fail_check "network-isolated: version resolution fails" \
  bash "${REPO_ROOT}/src/install-gh/install.bash"

reportResults
