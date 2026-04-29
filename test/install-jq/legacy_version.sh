#!/bin/bash
# version=1.6 + method=release: install the legacy 1.6 release.
# jq 1.6 uses the legacy asset naming convention (jq-linux64 / jq-osx-amd64)
# instead of the modern jq-linux-amd64 form. Verifies the binary installs and
# reports exactly 1.6.
set -e

source dev-container-features-test-lib

# --- binary present and executable ---
check "jq binary installed at /usr/local/bin/jq" test -f /usr/local/bin/jq
check "jq binary is executable" test -x /usr/local/bin/jq

# --- binary is callable ---
echo "=== jq --version ==="
jq --version 2>&1 || echo "(failed)"
check "jq --version succeeds" jq --version

# --- version matches 1.6 ---
check "jq version is 1.6" bash -c \
  '[ "$(jq --version 2>/dev/null | sed "s/^jq-//")" = "1.6" ]'

# --- binary is functional ---
check "jq processes JSON" bash -c 'echo "{}" | jq . > /dev/null 2>&1'

reportResults
