#!/bin/bash
set -e

source dev-container-features-test-lib

check "devcontainer command is available" bash -lc "command -v devcontainer"
check "devcontainer --version succeeds" bash -lc "devcontainer --version"

reportResults
