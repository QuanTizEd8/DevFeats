#!/bin/bash
# log_file=/tmp/brew.log: all installer output is mirrored to the specified
# log file in addition to stdout/stderr.
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- brew installed and functional ---
check "brew binary installed" test -f "$_BREW"
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds" "$_BREW" --version

# --- log file written ---
echo "===== /tmp/brew.log (last 20 lines) =====" && tail -20 /tmp/brew.log 2> /dev/null || echo "(log_file missing)"
check "log_file was created" test -f /tmp/brew.log
check "log_file is non-empty" test -s /tmp/brew.log
check "log_file contains install-homebrew header" grep -q 'install-homebrew' /tmp/brew.log
check "log_file contains success marker" grep -q 'Homebrew Installation script finished successfully' /tmp/brew.log
check "log_file contains brew prefix path" grep -q '/home/linuxbrew/.linuxbrew' /tmp/brew.log

reportResults
