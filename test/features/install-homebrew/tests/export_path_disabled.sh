#!/bin/bash
# export_path_disabled: prefix_activations="" skips all activation snippet writes.
# Verifies that brew installs successfully but no activation blocks are
# written to any shell startup file.
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew
_MARKER='prefix activation (install-homebrew)'
_PROFILE_D="QuanTizEd8-DevFeats-install-homebrew-prefix-activation.sh"

# --- brew installed and functional ---
check "brew binary installed" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds" "$_BREW" --version

# --- no activation blocks written anywhere ---
echo "=== /etc/profile.d/${_PROFILE_D} ==="
cat "/etc/profile.d/${_PROFILE_D}" 2> /dev/null || echo "(missing — expected)"
echo "=== /etc/bash.bashrc (tail) ==="
tail -5 /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"

check "profile.d activation file NOT written" bash -c '! test -f "/etc/profile.d/${_PROFILE_D}"'
check "bash.bashrc has NO activation marker" bash -c '! grep -qF "'"$_MARKER"'" /etc/bash.bashrc 2>/dev/null'
check "zshenv has NO activation marker" bash -c '! grep -qF "'"$_MARKER"'" /etc/zsh/zshenv 2>/dev/null && ! grep -qF "'"$_MARKER"'" /etc/zshenv 2>/dev/null'

reportResults
