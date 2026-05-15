#!/usr/bin/env bash
# shellcheck disable=SC2088  # ~/ in check labels is intentional (display only)
# default: all options at their defaults.
#
# macOS runners have Homebrew pre-installed → if_exists=skip (default) applies.
# The runner is non-root → activation snippets are written to the install
# user's personal dotfiles: login bash file, ~/.bashrc, and ~/.zshenv.
#
# Cleanup: removes activation blocks from dotfiles via trap on EXIT.
set -e

source dev-container-features-test-lib

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_HOME="$HOME"

_cleanup() {
  for f in "${_HOME}/.bash_profile" "${_HOME}/.bash_login" "${_HOME}/.profile" \
    "${_HOME}/.bashrc" "${_HOME}/.zshenv"; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT

# --- brew is intact (if_exists=skip) ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- login bash file receives activation block ---
# The feature picks the first of .bash_profile / .bash_login / .profile that
# exists, or creates .bash_profile.  Check all three candidates collectively.
check "a login bash file has begin marker" \
  bash -c 'grep -qF "# >>> prefix activation (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> prefix activation (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> prefix activation (install-homebrew) >>>" ~/.profile      2>/dev/null'
check "a login bash file has shellenv eval" \
  bash -c 'grep -qF "shellenv" ~/.bash_profile 2>/dev/null ||
             grep -qF "shellenv" ~/.bash_login  2>/dev/null ||
             grep -qF "shellenv" ~/.profile      2>/dev/null'

# --- ~/.bashrc ---
check "~/.bashrc has begin marker" grep -qF '# >>> prefix activation (install-homebrew) >>>' "${_HOME}/.bashrc"
check "~/.bashrc has shellenv eval" grep -qF 'shellenv' "${_HOME}/.bashrc"

# --- ~/.zshenv (activation written to zshenv, not zprofile/zshrc) ---
check "~/.zshenv has begin marker" grep -qF '# >>> prefix activation (install-homebrew) >>>' "${_HOME}/.zshenv"
check "~/.zshenv has shellenv eval" grep -qF 'shellenv' "${_HOME}/.zshenv"

# --- system-wide files NOT written (non-root) ---
check "system activation profile.d NOT written" bash -c '! test -f /etc/profile.d/QuanTizEd8-DevFeats-install-homebrew-prefix-activation.sh'

reportResults
