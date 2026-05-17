#!/bin/bash
# installer_dir=/tmp/gh-trace: the downloaded archive and checksums file must
# remain in installer_dir after installation completes.
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

# --- checksums file preserved (named after original URL basename) ---
check "checksums file preserved in installer_dir" bash -c \
  'ls /tmp/gh-trace/gh_*_checksums.txt 2>/dev/null | grep -q .'

reportResults
