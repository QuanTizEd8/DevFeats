#!/bin/bash
# prefix=/opt/myforge, prefix_discovery=symlink:
# Binary symlinks must be created in /usr/local/bin pointing into condabin.
# No directory symlinks (behavior removed). No PATH export blocks.
set -e

source dev-container-features-test-lib

# --- conda at custom dir ---
check "conda installed at /opt/myforge" test -d /opt/myforge
check "conda binary at custom dir" test -f /opt/myforge/bin/conda
check "mamba binary at custom dir" test -f /opt/myforge/bin/mamba
check "conda wrapper in condabin" test -f /opt/myforge/condabin/conda
check "mamba wrapper in condabin" test -f /opt/myforge/condabin/mamba

# --- binary symlinks created ---
echo "=== ls -la /usr/local/bin/conda /usr/local/bin/mamba ==="
ls -la /usr/local/bin/conda /usr/local/bin/mamba 2>&1 || echo "(missing)"
check "/usr/local/bin/conda symlink exists" test -L /usr/local/bin/conda
check "/usr/local/bin/mamba symlink exists" test -L /usr/local/bin/mamba
check "conda symlink points into /opt/myforge/condabin" bash -c '[ "$(readlink /usr/local/bin/conda)" = "/opt/myforge/condabin/conda" ]'
check "mamba symlink points into /opt/myforge/condabin" bash -c '[ "$(readlink /usr/local/bin/mamba)" = "/opt/myforge/condabin/mamba" ]'
check "conda reachable via symlink" /usr/local/bin/conda --version

# --- no directory symlink at /opt/conda ---
check "no /opt/conda directory symlink" bash -c '! test -e /opt/conda'

# --- no PATH export files written ---
check "profile.d export script NOT written" bash -c '! test -f "/etc/profile.d/${_EXPORT_PROFILE_D}"'

reportResults
