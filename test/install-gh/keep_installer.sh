#!/bin/bash
# method=binary, keep_installer=true, installer_dir=/tmp/gh-trace:
# The downloaded archive and checksums file must remain in /tmp/gh-trace after install.
set -e

source dev-container-features-test-lib

# --- gh installed and functional ---
check "gh binary installed" test -f /usr/local/bin/gh
check "gh --version succeeds" gh --version

# --- installer_dir still exists ---
echo "=== /tmp/gh-trace/ contents ==="
ls -la /tmp/gh-trace/ 2> /dev/null || echo "(directory missing)"
check "installer_dir exists" test -d /tmp/gh-trace

# --- archive preserved ---
check "gh archive preserved in installer_dir" bash -c \
  'ls /tmp/gh-trace/gh_*.tar.gz 2>/dev/null | grep -q .'

# --- checksums file preserved ---
check "checksums file preserved in installer_dir" bash -c \
  'test -f /tmp/gh-trace/checksums.txt'

reportResults
