#!/bin/bash
# log_file=/tmp/miniforge.log: all output is
# captured to the specified log file in addition to stdout/stderr.
set -e

source dev-container-features-test-lib

# --- conda installed ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda --version succeeds" /opt/conda/bin/conda --version

# --- log file written ---
check "log_file was created" test -f /tmp/miniforge.log
check "log_file is non-empty" test -s /tmp/miniforge.log
echo "===== /tmp/miniforge.log contents =====" && cat /tmp/miniforge.log && echo "===== end of log =====" || echo "(log_file missing)"
check "log_file contains install marker" grep -q "Miniforge" /tmp/miniforge.log
check "log_file contains success marker" grep -q "Miniforge Installation script finished successfully" /tmp/miniforge.log
check "log_file contains bin_dir path" grep -q "/opt/conda" /tmp/miniforge.log
check "log_file records conda info output" grep -q "platform :" /tmp/miniforge.log

reportResults
