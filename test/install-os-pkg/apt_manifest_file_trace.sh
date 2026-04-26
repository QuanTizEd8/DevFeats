#!/bin/bash
# Same checks as apt_manifest_file but run with log_level:"trace".
# The set -x trace in the build log shows exactly which code path executed,
# making it easy to diagnose manifest parsing issues in CI.
set -e

source dev-container-features-test-lib

check "tree is installed (manifest file, trace mode)" command -v tree
check "curl is installed (manifest file, trace mode)" command -v curl

reportResults
