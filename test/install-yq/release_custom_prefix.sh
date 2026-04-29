#!/bin/bash
# Verifies method=release installs yq under custom prefix.
set -e

source dev-container-features-test-lib

check "yq binary exists under custom prefix" test -x /opt/yq-bin/bin/yq
check "yq resolves from PATH" bash -c '
  resolved="$(command -v yq)"
  test -n "$resolved"
  test -x "$resolved"
  test "$(readlink -f "$resolved" 2> /dev/null || echo "$resolved")" = "$(readlink -f /opt/yq-bin/bin/yq 2> /dev/null || echo /opt/yq-bin/bin/yq)"
'
check "custom-prefix yq supports -o=json mode" bash -c '/opt/yq-bin/bin/yq -o=json "." /dev/null > /dev/null 2>&1'

reportResults
