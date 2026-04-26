#!/bin/bash
# log_file=/tmp/conda-env.log: all script output is captured to the log file.
# Verifies the file is created, is non-empty, and contains expected markers.
set -e

source dev-container-features-test-lib

# --- conda environment created ---
check "logenv environment is listed" bash -c '/opt/conda/bin/conda env list | grep -q logenv'
check "logenv directory exists" test -d /opt/conda/envs/logenv

# --- log file written ---
check "log_file was created" test -f /tmp/conda-env.log
check "log_file is non-empty" test -s /tmp/conda-env.log
check "log_file contains env name" grep -q "logenv" /tmp/conda-env.log
check "log_file contains success marker" grep -q "Conda Environment Installation script finished successfully" /tmp/conda-env.log

reportResults
