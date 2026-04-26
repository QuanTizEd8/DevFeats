#!/bin/bash
# log_file=/tmp/pixi.log: all install output is captured to the specified file.
set -e

source dev-container-features-test-lib

# --- pixi installed ---
check "pixi binary installed" test -f /usr/local/bin/pixi
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- log file written ---
echo "===== /tmp/pixi.log (last 20 lines) ====="
tail -n 20 /tmp/pixi.log 2> /dev/null || echo "(log_file missing)"
check "log_file was created" test -f /tmp/pixi.log
check "log_file is non-empty" test -s /tmp/pixi.log
check "log_file contains install marker" grep -q "Pixi" /tmp/pixi.log

reportResults
