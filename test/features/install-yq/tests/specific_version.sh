#!/bin/bash
# version=4.44.2 + method=release: install a specific pinned version.
# Verifies the binary reports exactly 4.44.2.
set -e

source dev-container-features-test-lib

# --- binary present and executable ---
check "yq binary installed at /usr/local/bin/yq" test -f /usr/local/bin/yq
check "yq binary is executable" test -x /usr/local/bin/yq

# --- binary is callable ---
echo "=== yq --version ==="
yq --version 2>&1 || echo "(failed)"
check "yq --version succeeds" yq --version

# --- version matches requested pin ---
check "yq version is 4.44.2" bash -c \
  '[ "$(yq --version 2>/dev/null | awk "{print \$NF}" | sed "s/^v//")" = "4.44.2" ]'

reportResults
