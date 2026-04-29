#!/bin/bash
# version=4.44.2 + if_exists=fail + yq 4.44.2 pre-installed (see version_match_idempotency/Dockerfile).
# The version-match guard must fire BEFORE if_exists dispatch, so the feature exits 0
# even though if_exists=fail would otherwise abort.
# The binary must remain at 4.44.2 and be functional.
set -e

source dev-container-features-test-lib

# --- original binary is still present ---
check "yq binary still present at /usr/local/bin/yq" test -f /usr/local/bin/yq
check "yq binary is still executable" test -x /usr/local/bin/yq

# --- binary is still functional ---
echo "=== yq --version ==="
yq --version 2>&1 || echo "(failed)"
check "yq --version succeeds" yq --version

# --- version is unchanged at 4.44.2 (feature did not reinstall) ---
check "yq version is still 4.44.2" bash -c \
  '[ "$(yq --version 2>/dev/null | awk "{print \$NF}" | sed "s/^v//")" = "4.44.2" ]'

reportResults
