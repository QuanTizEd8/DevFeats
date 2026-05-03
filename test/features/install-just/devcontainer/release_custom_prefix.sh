#!/bin/bash
# Verifies release install to a custom prefix.
set -e

source dev-container-features-test-lib

check "just binary exists in custom prefix" test -x /opt/just-bin/bin/just
check "custom-prefix just reports version" /opt/just-bin/bin/just --version

reportResults
