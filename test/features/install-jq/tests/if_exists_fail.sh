#!/bin/bash
# Ensures if_exists=fail exits non-zero when jq already exists.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

check "preinstalled jq remains available" command -v jq

reportResults
