#!/bin/bash
# installer_dir=/tmp/miniforge-trace: the Miniforge installer script and its
# .sha256 sidecar must remain in installer_dir after installation completes.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- installer artifacts preserved ---
echo "=== ls /tmp/miniforge-trace/ ==="
ls -la /tmp/miniforge-trace/ 2> /dev/null || echo "(missing or empty)"
check "installer directory preserved" test -d /tmp/miniforge-trace
check "installer .sh file preserved" bash -c 'ls /tmp/miniforge-trace/Miniforge3-*.sh 2>/dev/null | grep -q .'
check "installer sidecar preserved" bash -c 'ls /tmp/miniforge-trace/Miniforge3-*.sh.sha256 2>/dev/null | grep -q .'

reportResults
