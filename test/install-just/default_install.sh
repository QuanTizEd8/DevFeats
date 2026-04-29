#!/bin/bash
# Verifies default install path installs just.
set -e

source dev-container-features-test-lib

check "just command is available" command -v just
check "just reports a version" bash -c 'just --version | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+"'

reportResults
