#!/bin/bash
# Verifies default installation provides devcontainer CLI.
set -e

source dev-container-features-test-lib

check "devcontainer command is available" command -v devcontainer
check "devcontainer reports a version" bash -c 'devcontainer --version | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+"'

reportResults
