#!/bin/bash
# Verifies method=package installs a working shfmt.
set -e

source dev-container-features-test-lib

check "shfmt command is available" command -v shfmt
check "shfmt formats shell code" bash -c 'printf "if true\nthen\necho hi\nfi\n" | shfmt -'

reportResults
