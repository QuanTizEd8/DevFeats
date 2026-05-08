#!/bin/bash
# Ensures if_exists=fail exits non-zero when devcontainer already exists.
set -e

source dev-container-features-test-lib

check "preinstalled devcontainer remains available" command -v devcontainer

reportResults
