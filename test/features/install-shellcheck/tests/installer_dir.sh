#!/bin/bash
# installer_dir=/tmp/shellcheck-trace: the downloaded archive must remain in
# installer_dir after installation completes.
set -e

source dev-container-features-test-lib

# --- shellcheck installed and functional ---
check "shellcheck binary installed" test -f /usr/local/bin/shellcheck
check "shellcheck --version succeeds" shellcheck --version

# --- installer_dir still exists ---
echo "=== /tmp/shellcheck-trace/ contents ==="
ls -la /tmp/shellcheck-trace/ 2>/dev/null || echo "(directory missing)"
check "installer_dir exists" test -d /tmp/shellcheck-trace

# --- archive preserved ---
check "shellcheck archive preserved in installer_dir" bash -c \
  'ls /tmp/shellcheck-trace/shellcheck-v*.tar.xz 2>/dev/null | grep -q .'

reportResults
