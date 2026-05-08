#!/usr/bin/env bash
# update_false: update=false must skip the 'brew update' step while still
# installing brew (if_exists=skip, since brew is pre-installed) and exporting
# shellenv.
#
# The log_file option is used to capture installer output so the absence of
# 'brew update' can be verified.
#
# Cleanup: removes the log_file and shellenv blocks from user dotfiles on EXIT.
set -e

source dev-container-features-test-lib

_HOME="$HOME"
_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_LOG_FILE="/tmp/brew-update-false-test.log"

_cleanup() {
  rm -f "$_LOG_FILE"
  block_cleanup_all "brew shellenv (install-homebrew)"
}
trap _cleanup EXIT

# --- brew is intact (if_exists=skip) ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- shellenv still written (export_path=auto by default) ---
check "a user dotfile has shellenv marker" \
  bash -c 'grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.profile      2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.bashrc       2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.zprofile     2>/dev/null ||
             grep -qF "# >>> brew shellenv (install-homebrew) >>>" ~/.zshrc        2>/dev/null'

# --- brew update was NOT run (log_file must not contain the update completion marker) ---
echo "===== ${_LOG_FILE} (last 30 lines) ====="
tail -30 "$_LOG_FILE" 2> /dev/null || echo "(missing)"
check "log_file was created" test -f "$_LOG_FILE"
check "log_file is non-empty" test -s "$_LOG_FILE"
check "brew update NOT run" \
  bash -c '! grep -q "brew update completed" "'"$_LOG_FILE"'"'
check "install completed successfully" \
  grep -q "Homebrew Installation script finished successfully" "$_LOG_FILE"

reportResults
