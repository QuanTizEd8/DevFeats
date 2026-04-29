#!/bin/bash
# method=repos on Debian: verifies jq is installed via apt.
set -e

source dev-container-features-test-lib

check "jq command is available" command -v jq
check "jq processes JSON" bash -c 'echo "{}" | jq . > /dev/null 2>&1'
check "jq reports a version" bash -c 'jq --version | grep -Eq "^jq-"'

reportResults
