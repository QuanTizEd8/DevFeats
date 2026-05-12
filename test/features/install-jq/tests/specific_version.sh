#!/bin/bash
# version=1.8.1 + method=binary: install a specific pinned version.
# Verifies the binary reports exactly 1.8.1.
set -e

source dev-container-features-test-lib

# --- binary present and executable ---
check "jq binary installed at /usr/local/bin/jq" test -f /usr/local/bin/jq
check "jq binary is executable" test -x /usr/local/bin/jq

# --- binary is callable ---
echo "=== jq --version ==="
jq --version 2>&1 || echo "(failed)"
check "jq --version succeeds" jq --version

# --- version matches requested pin ---
check "jq version is 1.8.1" bash -c \
  '[ "$(jq --version 2>/dev/null | sed "s/^jq-//")" = "1.8.1" ]'

# --- binary is functional ---
check "jq processes JSON" bash -c 'echo "{}" | jq . > /dev/null 2>&1'

reportResults
