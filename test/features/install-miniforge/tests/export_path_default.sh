#!/bin/bash
# Default options (prefix=/opt/conda, prefix_discovery=auto):
# In devcontainer mode, containerEnv puts /opt/conda/bin on $PATH before install.sh
# runs, so prefix_discovery=auto correctly skips creating symlinks. PATH exports
# are always disabled for miniforge (exports.skip=true).  Verifies that
# /opt/conda/bin is reachable via login PATH (set by the container ENV directive).
set -e

source dev-container-features-test-lib

# --- startup files not written (exports always disabled; /opt/conda/bin already in PATH) ---
echo "=== /etc/profile.d/${_EXPORT_PROFILE_D} ==="
cat "/etc/profile.d/${_EXPORT_PROFILE_D}" 2> /dev/null || echo "(missing)"
echo "=== login PATH ==="
bash -lc 'echo "$PATH"' 2>&1 || echo "(failed)"

# --- no symlink needed (default path already on PATH) ---
check "/opt/conda is a real directory not a symlink" bash -c '[ -d /opt/conda ] && [ ! -L /opt/conda ]'

# --- PATH is reachable via containerEnv ---
check "login PATH includes /opt/conda/bin" bash -lc 'echo "$PATH" | grep -q /opt/conda/bin'

reportResults
