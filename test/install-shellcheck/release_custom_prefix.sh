#!/bin/bash
# Verifies method=release installs shellcheck under a custom prefix.
set -e

source dev-container-features-test-lib

check "shellcheck binary exists under custom prefix" test -x /opt/shellcheck-bin/bin/shellcheck
check "shellcheck resolves from PATH" bash -c '
  resolved="$(command -v shellcheck)"
  test -n "$resolved"
  test -x "$resolved"
  test "$(readlink -f "$resolved" 2>/dev/null || echo "$resolved")" = "$(readlink -f /opt/shellcheck-bin/bin/shellcheck 2>/dev/null || echo /opt/shellcheck-bin/bin/shellcheck)"
'
check "custom-prefix shellcheck lints a valid script" bash -c 'printf "#!/bin/sh\necho hi\n" | /opt/shellcheck-bin/bin/shellcheck -'

reportResults
