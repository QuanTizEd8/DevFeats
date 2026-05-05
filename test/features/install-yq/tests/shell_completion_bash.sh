#!/bin/bash
# shell_completions=bash (root):
# Verifies yq bash completion file is written to the system-wide bash_completion.d.
set -e

source dev-container-features-test-lib

# --- yq installed ---
check "yq binary installed" command -v yq
check "yq --version succeeds" yq --version

# --- bash completion file written ---
echo "=== /etc/bash_completion.d/yq ==="
cat /etc/bash_completion.d/yq 2> /dev/null | head -5 || echo "(missing)"
check "bash completion file exists" test -f /etc/bash_completion.d/yq
check "bash completion file is non-empty" bash -c 'test -s /etc/bash_completion.d/yq'
check "bash completion file is valid bash" bash -n /etc/bash_completion.d/yq

reportResults
