#!/bin/bash
# Ensures if_exists=fail exits non-zero when shellcheck already exists.
set -e

source dev-container-features-test-lib

check "preinstalled shellcheck remains available" command -v shellcheck

reportResults
