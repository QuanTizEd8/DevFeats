#!/bin/bash
# version=1.7.1 + method=release + if_exists=reinstall + jq 1.8.1 pre-installed (see reinstall/Dockerfile).
# Verifies that if_exists=reinstall replaces the existing binary and the new
# version is reported correctly.
set -e

source dev-container-features-test-lib

# --- binary is present ---
check "jq binary present at /usr/local/bin/jq" test -f /usr/local/bin/jq
check "jq binary is executable" test -x /usr/local/bin/jq

# --- binary is callable ---
echo "=== jq --version ==="
jq --version 2>&1 || echo "(failed)"
check "jq --version succeeds" jq --version

# --- version has been replaced to 1.7.1 ---
check "jq version is 1.7.1 (reinstalled)" bash -c \
  '[ "$(jq --version 2>/dev/null | sed "s/^jq-//")" = "1.7.1" ]'

# --- binary is functional ---
check "jq processes JSON" bash -c 'echo "{}" | jq . > /dev/null 2>&1'

reportResults
