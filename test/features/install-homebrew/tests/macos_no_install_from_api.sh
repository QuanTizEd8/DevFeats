#!/usr/bin/env bash
# no_install_from_api: with a pre-seeded HOMEBREW_NO_INSTALL_FROM_API=1 block
# in user dotfiles, a default run (no_install_from_api=false) must remove it.
#
# Brew is pre-installed (if_exists=skip).
#
# Cleanup: removes both the shellenv block and the no_install_from_api block
# from all user init files on EXIT.
set -e

source dev-container-features-test-lib

_HOME="$HOME"
_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_BASH_LOGIN_FILE="$(detect_bash_login_file)"

_cleanup() {
  block_cleanup_all "brew shellenv (install-homebrew)"
  block_cleanup_all "HOMEBREW_NO_INSTALL_FROM_API (install-homebrew)"
}
trap _cleanup EXIT

_test_failure_diagnostics() {
  log_install_homebrew_shell_init_diagnostics "${_HOME}" "${_BASH_LOGIN_FILE}"
  echo "" >&2
  echo "--- lines mentioning HOMEBREW_NO_INSTALL_FROM_API in resolved login file ---" >&2
  grep -nF 'HOMEBREW_NO_INSTALL_FROM_API' "${_BASH_LOGIN_FILE}" 2> /dev/null || echo "(no matches)" >&2
}

# --- brew is intact ---
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- pre-seeded HOMEBREW_NO_INSTALL_FROM_API block removed on default run ---
check "NO_INSTALL_FROM_API marker block absent from resolved bash login file after run" \
  bash -c '! grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" "$1" 2>/dev/null' -- "$_BASH_LOGIN_FILE"
check "NO_INSTALL_FROM_API block absent from ~/.bashrc after run" \
  bash -c '! grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.bashrc 2>/dev/null'
check "NO_INSTALL_FROM_API block absent from ~/.zprofile after run" \
  bash -c '! grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.zprofile 2>/dev/null'
check "NO_INSTALL_FROM_API block absent from ~/.zshrc after run" \
  bash -c '! grep -qF "# >>> HOMEBREW_NO_INSTALL_FROM_API (install-homebrew) >>>" ~/.zshrc 2>/dev/null'

reportResults
