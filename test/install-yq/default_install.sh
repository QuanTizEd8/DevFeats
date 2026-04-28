#!/bin/bash
# Verifies default install path installs a compatible yq.
set -e

source dev-container-features-test-lib

check "yq command is available" command -v yq
check "yq supports -o=json mode" bash -c 'yq -o=json "." /dev/null > /dev/null 2>&1'
check "yq reports a version" bash -c 'yq --version | grep -Eiq "version|yq"'

reportResults
