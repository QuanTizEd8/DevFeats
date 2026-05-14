#!/bin/bash
# prefix=/opt/myforge (custom prefix, default prefix_discovery=auto):
# Miniforge is installed to a custom directory. In auto mode with a custom
# prefix, symlinks are created in /usr/local/bin so conda/mamba are reachable.
# No PATH export blocks are written (exports always disabled for miniforge).
set -e

source dev-container-features-test-lib

# --- custom directory structure ---
check "conda installed at /opt/myforge" test -d /opt/myforge
check "conda binary at custom dir" test -f /opt/myforge/bin/conda
check "conda binary is executable" test -x /opt/myforge/bin/conda
check "mamba binary at custom dir" test -f /opt/myforge/bin/mamba
check "mamba binary is executable" test -x /opt/myforge/bin/mamba
check "conda wrapper in condabin" test -f /opt/myforge/condabin/conda
check "mamba wrapper in condabin" test -f /opt/myforge/condabin/mamba
check "python installed in custom base env" test -f /opt/myforge/bin/python
check "conda activation script at custom dir" test -f /opt/myforge/etc/profile.d/conda.sh
check "mamba activation script at custom dir" test -f /opt/myforge/etc/profile.d/mamba.sh

# --- default directory must NOT exist ---
check "default /opt/conda NOT created" bash -c '! test -e /opt/conda'

# --- binary symlinks created in /usr/local/bin ---
echo "=== ls -la /usr/local/bin/conda /usr/local/bin/mamba ==="
ls -la /usr/local/bin/conda /usr/local/bin/mamba 2>&1 || echo "(missing)"
check "/usr/local/bin/conda symlink exists" test -L /usr/local/bin/conda
check "/usr/local/bin/mamba symlink exists" test -L /usr/local/bin/mamba
check "conda symlink points into /opt/myforge" bash -c '[ "$(readlink /usr/local/bin/conda)" = "/opt/myforge/condabin/conda" ]'
check "mamba symlink points into /opt/myforge" bash -c '[ "$(readlink /usr/local/bin/mamba)" = "/opt/myforge/condabin/mamba" ]'

# --- no PATH export files written (exports always disabled for miniforge) ---
echo "=== /etc/profile.d/${_EXPORT_PROFILE_D} (should be missing) ==="
cat "/etc/profile.d/${_EXPORT_PROFILE_D}" 2> /dev/null || echo "(missing — expected)"
check "profile.d export script NOT written" bash -c '! test -f "/etc/profile.d/${_EXPORT_PROFILE_D}"'

# --- functionality ---
check "conda --version via symlink" /usr/local/bin/conda --version
check "mamba --version via symlink" /usr/local/bin/mamba --version
check "conda info --base returns /opt/myforge" bash -c '[ "$(/opt/myforge/bin/conda info --base 2>/dev/null)" = "/opt/myforge" ]'

reportResults
