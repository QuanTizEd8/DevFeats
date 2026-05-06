#!/bin/bash
set -e

source dev-container-features-test-lib

check "devcontainer command is available" command -v devcontainer
check "devcontainer --version succeeds" devcontainer --version

reportResults
