#!/bin/bash
# prefix=/opt/myforge, prefix_discovery=symlink, remoteUser=vscode:
# When the install runs as root but remoteUser=vscode, binary symlinks are
# created in /usr/local/bin (root target). vscode's home is not touched.
set -e

source dev-container-features-test-lib

# --- installation at custom prefix ---
check "conda binary at /opt/myforge/bin/conda" test -f /opt/myforge/bin/conda
check "conda binary is executable" test -x /opt/myforge/bin/conda
check "conda wrapper in condabin" test -f /opt/myforge/condabin/conda
check "mamba wrapper in condabin" test -f /opt/myforge/condabin/mamba

# --- binary symlinks created in /usr/local/bin (root install) ---
echo "=== ls -la /usr/local/bin/conda /usr/local/bin/mamba ==="
ls -la /usr/local/bin/conda /usr/local/bin/mamba 2>&1 || echo "(missing)"
check "/usr/local/bin/conda symlink exists" test -L /usr/local/bin/conda
check "/usr/local/bin/mamba symlink exists" test -L /usr/local/bin/mamba
check "conda reachable via symlink" /usr/local/bin/conda --version

# --- no directory symlink at /opt/conda ---
check "no /opt/conda directory symlink" bash -c '! test -e /opt/conda'

# --- no user-scoped symlink created ---
check "no \$HOME/miniforge3 symlink for vscode" bash -c '! test -e /home/vscode/miniforge3'

reportResults
