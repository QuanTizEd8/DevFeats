#!/bin/bash
# home_dir=/var/pixi: PIXI_HOME is set during install and export_pixi_home=auto
# writes an export block to system-wide profile.d so the variable is available
# at runtime in every shell session.
set -e

source dev-container-features-test-lib

# --- pixi installed ---
check "pixi binary installed" test -f /usr/local/bin/pixi
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- PIXI_HOME export written to system-wide profile.d ---
echo "=== /etc/profile.d/${_EXPORT_PROFILE_D} ==="
cat "/etc/profile.d/${_EXPORT_PROFILE_D}" 2> /dev/null || echo "(missing)"
check "profile.d export file written" test -f "/etc/profile.d/${_EXPORT_PROFILE_D}"
check "profile.d export file has PIXI_HOME marker" grep -Fq 'pixi PIXI_HOME (install-pixi)' "/etc/profile.d/${_EXPORT_PROFILE_D}"
check "profile.d export file exports /var/pixi" grep -Fq '/var/pixi' "/etc/profile.d/${_EXPORT_PROFILE_D}"

# --- PIXI_HOME export also written to the other startup files used by auto mode ---
echo "=== /etc/environment ==="
cat /etc/environment 2> /dev/null || echo "(missing)"
echo "=== /etc/bashenv ==="
cat /etc/bashenv 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc ==="
cat /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"
check "BASH_ENV registered in /etc/environment" grep -Fq 'BASH_ENV=' /etc/environment
check "/etc/bashenv has PIXI_HOME marker" grep -Fq 'pixi PIXI_HOME (install-pixi)' /etc/bashenv
check "/etc/bash.bashrc has PIXI_HOME marker" grep -Fq 'pixi PIXI_HOME (install-pixi)' /etc/bash.bashrc
check "/etc/zsh/zshenv has PIXI_HOME marker" grep -Fq 'pixi PIXI_HOME (install-pixi)' /etc/zsh/zshenv

# --- no PATH block written (prefix=/usr/local, no-op) ---
check "no pixi PATH block in export file" bash -c '! grep -Fq "pixi PATH (install-pixi)" "/etc/profile.d/${_EXPORT_PROFILE_D}" 2>/dev/null'

reportResults
