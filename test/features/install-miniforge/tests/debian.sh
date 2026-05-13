#!/bin/bash
# debian:latest: verifies the full installation
# path works on Debian (glibc, apt) to complement the Ubuntu-based scenarios.
set -e

source dev-container-features-test-lib

# --- installation directory structure ---
check "conda directory exists" test -d /opt/conda
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda
check "mamba binary installed" test -f /opt/conda/bin/mamba
check "mamba binary is executable" test -x /opt/conda/bin/mamba
check "python installed in base env" test -f /opt/conda/bin/python
check "pip installed in base env" test -f /opt/conda/bin/pip

# --- activation scripts ---
check "conda activation script exists" test -f /opt/conda/etc/profile.d/conda.sh
check "mamba activation script exists" test -f /opt/conda/etc/profile.d/mamba.sh

# --- PATH is reachable (via containerEnv; export_path=auto skips file writes) ---
echo "=== conda --version ==="
/opt/conda/bin/conda --version 2>&1 || echo "(failed)"
check "login PATH includes /opt/conda/bin" bash -lc 'echo "$PATH" | grep -q /opt/conda/bin'

# --- functionality ---
check "conda --version succeeds" /opt/conda/bin/conda --version
check "mamba --version succeeds" /opt/conda/bin/mamba --version
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'
check "base environment accessible" /opt/conda/bin/conda env list

reportResults
