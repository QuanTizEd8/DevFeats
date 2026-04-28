#!/bin/bash
# Verifies method=repos installs yq from distro packages.
set -e

source dev-container-features-test-lib

check "yq command is available" command -v yq
check "yq supports -o=json mode" bash -c 'yq -o=json "." /dev/null > /dev/null 2>&1'
check "yq package is installed on apt systems" bash -c 'dpkg-query -W -f="${Status}" yq 2>/dev/null | grep -Fq "install ok installed"'

reportResults
