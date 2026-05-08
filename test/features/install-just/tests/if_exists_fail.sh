#!/bin/bash
# Ensures if_exists=fail exits non-zero when just already exists.
set -e

source dev-container-features-test-lib

check "preinstalled just remains available" command -v just

reportResults
