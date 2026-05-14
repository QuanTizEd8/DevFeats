#!/bin/bash
# All defaults: full Miniforge installation.
# Verifies conda and mamba are installed under /opt/conda, the base environment
# is functional, and activation scripts are in place.  In devcontainer mode,
# containerEnv puts /opt/conda/bin on $PATH before install.sh runs, so
# prefix_discovery=auto skips creating symlinks when prefix is already on PATH.
set -e

source dev-container-features-test-lib

# --- installation directory structure ---
check "conda directory exists" test -d /opt/conda
check "conda/bin directory exists" test -d /opt/conda/bin
check "conda/envs directory exists" test -d /opt/conda/envs
check "conda/pkgs directory exists" test -d /opt/conda/pkgs

# --- executables ---
check "conda binary installed" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda
check "mamba binary installed" test -f /opt/conda/bin/mamba
check "mamba binary is executable" test -x /opt/conda/bin/mamba
check "python installed in base env" test -f /opt/conda/bin/python
check "pip installed in base env" test -f /opt/conda/bin/pip

# --- activation scripts ---
check "conda activation script exists" test -f /opt/conda/etc/profile.d/conda.sh
check "mamba activation script exists" test -f /opt/conda/etc/profile.d/mamba.sh

# --- PATH is reachable (exports permanently disabled; PATH comes from containerEnv) ---
check "login PATH includes /opt/conda/bin" bash -lc 'echo "$PATH" | grep -q /opt/conda/bin'

# --- conda functionality ---
check "conda --version succeeds" /opt/conda/bin/conda --version
check "mamba --version succeeds" /opt/conda/bin/mamba --version
check "conda info exits zero" /opt/conda/bin/conda info
check "conda env list shows base" /opt/conda/bin/conda env list
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'
check "conda list for base env succeeds" /opt/conda/bin/conda list -n base

# --- no stray installer artifacts (keep_installer=false by default) ---
check "installer dir cleaned up" bash -c '! test -f /tmp/miniforge-installer/*.sh 2>/dev/null'

reportResults
