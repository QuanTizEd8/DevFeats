#!/usr/bin/env bash
# brew_git_remote: with a pre-seeded HOMEBREW_BREW_GIT_REMOTE block in user
# dotfiles, a default run (brew_git_remote unset) must remove that block.
#
# Brew is pre-installed (if_exists=skip), and setup pre-seeds the block so this
# scenario validates the cleanup path equivalent to the old second run.
#
# Cleanup: removes shellenv and brew_git_remote blocks from user dotfiles.
set -e

source dev-container-features-test-lib

_HOME="$HOME"
_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"

# Derive the Homebrew/brew git repository path (same logic as detect_brew_repository).
if [[ "$(uname -m)" == "arm64" ]]; then
  _BREW_REPO="$_BREW_PREFIX"
else
  _BREW_REPO="${_BREW_PREFIX}/Homebrew"
fi

# Use the current remote URL so the git set-url call is a safe no-op.
_REMOTE_URL="$(git -C "$_BREW_REPO" remote get-url origin 2> /dev/null ||
  echo "https://github.com/Homebrew/brew")"
echo "ℹ️  Using brew_git_remote: ${_REMOTE_URL}"

_cleanup() {
  block_cleanup_all "brew shellenv (install-homebrew)"
  block_cleanup_all "HOMEBREW_BREW_GIT_REMOTE (install-homebrew)"
}
trap _cleanup EXIT

# --- brew is intact ---
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- git remote on the brew repository is still correct ---
check "brew git origin URL unchanged" bash -c \
  'git -C "'"$_BREW_REPO"'" remote get-url origin | grep -qF "'"$_REMOTE_URL"'"'

# --- pre-seeded HOMEBREW_BREW_GIT_REMOTE block removed on default run ---
check "BREW_GIT_REMOTE block absent from ~/.bash_profile after run" \
  bash -c '! grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.bash_profile 2>/dev/null'
check "BREW_GIT_REMOTE block absent from ~/.bashrc after run" \
  bash -c '! grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.bashrc 2>/dev/null'
check "BREW_GIT_REMOTE block absent from ~/.zprofile after run" \
  bash -c '! grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.zprofile 2>/dev/null'
check "BREW_GIT_REMOTE block absent from ~/.zshrc after run" \
  bash -c '! grep -qF "HOMEBREW_BREW_GIT_REMOTE" ~/.zshrc 2>/dev/null'

reportResults
