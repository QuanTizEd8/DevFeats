#!/bin/bash
# log_file=/tmp/gh-install.log: all install output is captured to the specified file.
set -e

source dev-container-features-test-lib

# --- gh installed ---
check "gh binary installed" command -v gh
check "gh --version succeeds" gh --version

# --- log file written ---
echo "===== /tmp/gh-install.log (last 20 lines) ====="
tail -n 20 /tmp/gh-install.log 2> /dev/null || echo "(log_file missing)"
check "log_file was created" test -f /tmp/gh-install.log
check "log_file is non-empty" test -s /tmp/gh-install.log

reportResults
