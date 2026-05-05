#!/bin/bash
# Verifies auto mode yields a compatible yq on Linux.
set -e

source dev-container-features-test-lib

check "yq command is available" command -v yq
check "yq supports -o=json mode" bash -c 'yq -o=json "." /dev/null > /dev/null 2>&1'

reportResults
