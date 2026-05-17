#!/bin/bash
# installer_dir=/tmp/pixi-trace: the downloaded .tar.gz archive and its
# .tar.gz.sha256 sidecar must remain in installer_dir after installation completes.
set -e

source dev-container-features-test-lib

# --- pixi installed and functional ---
check "pixi binary installed" test -f /usr/local/bin/pixi
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- installer_dir artifacts preserved ---
echo "=== /tmp/pixi-trace/ contents ==="
ls -la /tmp/pixi-trace/ 2> /dev/null || echo "(directory missing)"
check "installer_dir exists" test -d /tmp/pixi-trace
check "pixi archive preserved" bash -c 'ls /tmp/pixi-trace/pixi-*.tar.gz 2>/dev/null | grep -q .'
check "pixi sidecar preserved" bash -c 'ls /tmp/pixi-trace/pixi-*.tar.gz.sha256 2>/dev/null | grep -q .'

reportResults
