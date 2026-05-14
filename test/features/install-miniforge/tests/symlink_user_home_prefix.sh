#!/bin/bash
# prefix=/root/myforge, prefix_discovery=symlink:
# Miniforge is installed under root's home directory. Binary symlinks are
# created in /usr/local/bin (root install, prefix_discovery=symlink).
# No directory symlinks are created.
set -e

source dev-container-features-test-lib

# --- conda installed at user home prefix ---
check "conda installed at /root/myforge" test -d /root/myforge
check "/root/myforge/bin/conda exists" test -f /root/myforge/bin/conda
check "conda wrapper in /root/myforge/condabin" test -f /root/myforge/condabin/conda
check "mamba wrapper in /root/myforge/condabin" test -f /root/myforge/condabin/mamba

# --- binary symlinks created in /usr/local/bin ---
echo "=== ls -la /usr/local/bin/conda /usr/local/bin/mamba ==="
ls -la /usr/local/bin/conda /usr/local/bin/mamba 2>&1 || echo "(missing)"
check "/usr/local/bin/conda symlink exists" test -L /usr/local/bin/conda
check "/usr/local/bin/mamba symlink exists" test -L /usr/local/bin/mamba
check "conda reachable via symlink" /usr/local/bin/conda --version

# --- no legacy directory-level symlink ---
check "no /opt/conda directory symlink" bash -c '! test -L /opt/conda && ! test -e /opt/conda'
check "no /root/miniforge3 directory symlink" bash -c '! test -L /root/miniforge3'

reportResults
