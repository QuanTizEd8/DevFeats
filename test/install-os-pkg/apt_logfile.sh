#!/bin/bash
# Verifies that when the log_file option is set, a log file is created at the
# specified path and contains installation output.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "log_file was created" test -f /tmp/install-os-pkg.log
check "log_file contains installation output" \
  grep -q "OS Package Installation script finished successfully." /tmp/install-os-pkg.log

reportResults
