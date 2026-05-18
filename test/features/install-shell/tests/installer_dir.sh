#!/bin/bash
# installer_dir=/tmp/shell-trace: the downloaded fzf archive and checksums file
# must remain in installer_dir after installation completes.
set -e

source dev-container-features-test-lib

# --- fzf installed and functional ---
check "fzf binary installed" test -f /usr/local/bin/fzf
check "fzf --version succeeds" fzf --version

# --- installer_dir still exists ---
echo "=== /tmp/shell-trace/ contents ==="
ls -la /tmp/shell-trace/ 2>/dev/null || echo "(directory missing)"
check "installer_dir exists" test -d /tmp/shell-trace

# --- fzf archive preserved ---
check "fzf archive preserved in installer_dir" bash -c \
  'ls /tmp/shell-trace/fzf-*.tar.gz 2>/dev/null | grep -q .'

# --- checksums file preserved ---
check "fzf checksums file preserved in installer_dir" bash -c \
  'ls /tmp/shell-trace/fzf_*_checksums.txt 2>/dev/null | grep -q .'

reportResults
