#!/bin/bash
# installer_dir=/tmp/just-trace: the downloaded archive and SHA256SUMS file must
# remain in installer_dir after installation completes.
set -e

source dev-container-features-test-lib

# --- just installed and functional ---
check "just binary installed" test -f /usr/local/bin/just
check "just --version succeeds" just --version

# --- installer_dir still exists ---
echo "=== /tmp/just-trace/ contents ==="
ls -la /tmp/just-trace/ 2>/dev/null || echo "(directory missing)"
check "installer_dir exists" test -d /tmp/just-trace

# --- archive preserved ---
check "just archive preserved in installer_dir" bash -c \
  'ls /tmp/just-trace/just-*.tar.gz 2>/dev/null | grep -q .'

# --- checksums file preserved ---
check "SHA256SUMS preserved in installer_dir" bash -c \
  'ls /tmp/just-trace/SHA256SUMS 2>/dev/null | grep -q .'

reportResults
