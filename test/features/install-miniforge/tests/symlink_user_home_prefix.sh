#!/bin/bash
# prefix=/root/myforge, prefix_discovery=symlink:
# Miniforge is installed under root's home directory. Because the prefix falls
# under ${HOME}/, binary symlinks are created in ${HOME}/.local/bin (same
# target as for non-root users). No directory symlinks are created.
set -e

source dev-container-features-test-lib

# --- conda installed at user home prefix ---
check "conda installed at /root/myforge" test -d /root/myforge
check "/root/myforge/bin/conda exists" test -f /root/myforge/bin/conda
check "conda wrapper in /root/myforge/condabin" test -f /root/myforge/condabin/conda
check "mamba wrapper in /root/myforge/condabin" test -f /root/myforge/condabin/mamba

# --- binary symlinks created in /root/.local/bin ---
echo "=== ls -la /root/.local/bin/conda /root/.local/bin/mamba ==="
ls -la /root/.local/bin/conda /root/.local/bin/mamba 2>&1 || echo "(missing)"
check "/root/.local/bin/conda symlink exists" test -L /root/.local/bin/conda
check "/root/.local/bin/mamba symlink exists" test -L /root/.local/bin/mamba
check "conda reachable via symlink" /root/.local/bin/conda --version

# --- no legacy directory-level symlink ---
check "no /opt/conda directory symlink" bash -c '! test -L /opt/conda && ! test -e /opt/conda'
check "no /root/miniforge3 directory symlink" bash -c '! test -L /root/miniforge3'

reportResults
