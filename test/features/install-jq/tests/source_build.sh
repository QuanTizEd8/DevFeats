#!/bin/bash
# Verifies that method=source builds jq from source and produces a working binary.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

check "jq binary present at /usr/local/bin/jq" test -f /usr/local/bin/jq
check "jq binary is executable" test -x /usr/local/bin/jq
check "jq --version succeeds" /usr/local/bin/jq --version
check "jq version is 1.8.1" bash -c \
  '[ "$(/usr/local/bin/jq --version 2>/dev/null | sed "s/^jq-//")" = "1.8.1" ]'
check "jq processes JSON" bash -c 'echo "{}" | /usr/local/bin/jq . > /dev/null 2>&1'

reportResults
