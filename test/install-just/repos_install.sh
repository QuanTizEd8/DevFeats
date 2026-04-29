#!/bin/bash
# Verifies repository-based installation.
set -e

source dev-container-features-test-lib

check "just command is available" command -v just
check "just --version succeeds" just --version

reportResults
