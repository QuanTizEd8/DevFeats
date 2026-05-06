#!/usr/bin/env bash
# Verify that pixi installation fails when the network is blocked (version
# resolution requires the GitHub Releases API).
# The base image (built by run-linux.sh) pre-installs feature dependencies.
set -euo pipefail

source dev-container-features-test-lib

fail_check "network-isolated: GitHub API unreachable" \
  bash "${REPO_ROOT}/src/install-pixi/install.bash"

reportResults
