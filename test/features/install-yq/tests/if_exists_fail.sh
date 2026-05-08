#!/usr/bin/env bash
# Ensures if_exists=fail exits non-zero when yq already exists.
set -e

source dev-container-features-test-lib

check "preinstalled yq remains available" command -v yq

reportResults
