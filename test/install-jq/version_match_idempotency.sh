#!/bin/bash
# version=1.8.1 + if_exists=fail + jq 1.8.1 pre-installed (see version_match_idempotency/Dockerfile).
# The version-match guard must fire BEFORE if_exists dispatch, so the feature exits 0
# even though if_exists=fail would otherwise abort.
# The binary must remain at 1.8.1 and be functional.
set -e

source dev-container-features-test-lib

# --- original binary is still present ---
check "jq binary still present at /usr/local/bin/jq" test -f /usr/local/bin/jq
check "jq binary is still executable" test -x /usr/local/bin/jq

# --- binary is still functional ---
echo "=== jq --version ==="
jq --version 2>&1 || echo "(failed)"
check "jq --version succeeds" jq --version

# --- version is unchanged at 1.8.1 (feature did not reinstall) ---
check "jq version is still 1.8.1" bash -c \
  '[ "$(jq --version 2>/dev/null | sed "s/^jq-//")" = "1.8.1" ]'

# --- binary is functional ---
check "jq processes JSON" bash -c 'echo "{}" | jq . > /dev/null 2>&1'

reportResults
