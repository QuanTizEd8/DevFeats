#!/bin/bash
# prefix=/opt/pixi, symlink=false:
# Verifies pixi is installed to $prefix/bin/pixi, a PATH export block
# is written to profile.d (because prefix != /usr/local), and no symlink
# is created at /usr/local/bin/pixi.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "pixi binary installed at /opt/pixi/bin/pixi" test -f /opt/pixi/bin/pixi
check "pixi binary is executable" test -x /opt/pixi/bin/pixi

# --- binary is callable directly ---
echo "=== /opt/pixi/bin/pixi --version ==="
/opt/pixi/bin/pixi --version 2>&1 || echo "(failed)"
check "/opt/pixi/bin/pixi --version succeeds" /opt/pixi/bin/pixi --version

# --- PATH block written to system-wide profile.d (root + non-default prefix) ---
echo "=== /etc/profile.d/${_EXPORT_PROFILE_D} ==="
cat "/etc/profile.d/${_EXPORT_PROFILE_D}" 2> /dev/null || echo "(missing)"
check "profile.d export file written" test -f "/etc/profile.d/${_EXPORT_PROFILE_D}"
check "profile.d script has pixi PATH marker" grep -Fq 'pixi PATH (install-pixi)' "/etc/profile.d/${_EXPORT_PROFILE_D}"
check "profile.d script exports /opt/pixi/bin" grep -Fq '/opt/pixi/bin' "/etc/profile.d/${_EXPORT_PROFILE_D}"

# --- no symlink at /usr/local/bin/pixi ---
check "no symlink at /usr/local/bin/pixi" bash -c '! test -L /usr/local/bin/pixi'

reportResults
