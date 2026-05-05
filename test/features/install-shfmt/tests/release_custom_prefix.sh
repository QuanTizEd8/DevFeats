#!/bin/bash
# Verifies method=release installs shfmt under a custom prefix.
set -e

source dev-container-features-test-lib

check "shfmt binary exists under custom prefix" test -x /opt/shfmt-bin/bin/shfmt
check "shfmt resolves from PATH" bash -c '
  resolved="$(command -v shfmt)"
  test -n "$resolved"
  test -x "$resolved"
  test "$(readlink -f "$resolved" 2>/dev/null || echo "$resolved")" = "$(readlink -f /opt/shfmt-bin/bin/shfmt 2>/dev/null || echo /opt/shfmt-bin/bin/shfmt)"
'
check "custom-prefix shfmt formats shell code" bash -c 'printf "if true\nthen\necho hi\nfi\n" | /opt/shfmt-bin/bin/shfmt -'

reportResults
