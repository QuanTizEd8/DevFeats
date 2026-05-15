#!/bin/bash
# shellenv_remote_user: remoteUser="vscode" with default options.
# Root process installs as linuxbrew; activation is written system-wide
# (profile.d + bash.bashrc + zshenv). No per-user files are written.
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew
_MARKER='prefix activation (install-homebrew)'
_PROFILE_D="QuanTizEd8-DevFeats-install-homebrew-prefix-activation.sh"

# --- brew is functional ---
check "brew binary installed" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- system-wide activation blocks (root + Linux) ---
echo "=== /etc/profile.d/${_PROFILE_D} ==="
cat "/etc/profile.d/${_PROFILE_D}" 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc (tail 10) ==="
tail -10 /etc/bash.bashrc 2> /dev/null || echo "(missing)"

check "profile.d activation file has marker" grep -qF "$_MARKER" "/etc/profile.d/${_PROFILE_D}"
check "profile.d activation file has brew shellenv eval" grep -qF 'shellenv' "/etc/profile.d/${_PROFILE_D}"
check "bash.bashrc has activation marker" grep -qF "$_MARKER" /etc/bash.bashrc

reportResults
