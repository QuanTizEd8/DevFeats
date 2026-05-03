#!/usr/bin/env bash
# Verifies that method=source builds jq from the release tarball and produces
# a working binary at the expected prefix.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/support/assert.sh
source "${REPO_ROOT}/test/support/assert.sh"

check "method=source installs jq successfully" \
  bash "${REPO_ROOT}/src/install-jq/install.bash" \
  --method source \
  --version 1.8.1 \
  --prefix /usr/local

check "jq binary present at /usr/local/bin/jq" test -f /usr/local/bin/jq
check "jq binary is executable" test -x /usr/local/bin/jq
check "jq --version succeeds" /usr/local/bin/jq --version
check "jq version is 1.8.1" bash -c \
  '[ "$(/usr/local/bin/jq --version 2>/dev/null | sed "s/^jq-//")" = "1.8.1" ]'
check "jq processes JSON" bash -c 'echo "{}" | /usr/local/bin/jq . > /dev/null 2>&1'

reportResults
