#!/bin/bash
# Ensures if_exists=fail exits non-zero when shfmt already exists.
set -e

source dev-container-features-test-lib

check "preinstalled shfmt remains available" command -v shfmt

reportResults
