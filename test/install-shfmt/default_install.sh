#!/bin/bash
# Verifies default install installs a working shfmt.
set -e

source dev-container-features-test-lib

check "shfmt command is available" command -v shfmt
check "shfmt reports a version" bash -c 'shfmt --version | grep -Eq "^v?[0-9]+\.[0-9]+\.[0-9]+"'
check "shfmt formats shell code" bash -c 'printf "if true\nthen\necho hi\nfi\n" | shfmt -'

reportResults
