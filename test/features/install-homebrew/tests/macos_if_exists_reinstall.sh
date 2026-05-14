#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # bash -c literal script, ~/ in labels
# if_exists_reinstall: Homebrew is already installed (by the runner or the
# preceding fresh_install scenario).  Running the feature with if_exists=reinstall
# must uninstall then reinstall Homebrew from scratch and then run post-install
# steps (shellenv export).
#
# Cleanup: removes shellenv blocks from user dotfiles on EXIT.
set -e

source dev-container-features-test-lib

_HOME="$HOME"

_cleanup() {
  block_cleanup_all "prefix activation (install-homebrew)"
}
trap _cleanup EXIT

# ── Pre-condition: brew is present ────────────────────────────────────────────
_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
check "brew present before reinstall (pre-condition)" test -f "$_BREW"

# ── Verify brew is functional after reinstall ────────────────────────────────
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"

check "brew prefix directory exists after reinstall" test -d "$_BREW_PREFIX"
check "brew binary present after reinstall" test -f "$_BREW"
check "brew binary is executable after reinstall" test -x "$_BREW"
check "brew --version succeeds after reinstall" "$_BREW" --version
check "brew --version reports Homebrew" bash -c '"$1" --version | grep -q Homebrew' -- "$_BREW"

# ── Verify shellenv blocks written (Case B: non-root on macOS) ───────────────
echo "=== ~/.zshenv ==="
cat "${_HOME}/.zshenv" 2> /dev/null || echo "(missing)"

check "a login bash file has shellenv marker" \
  bash -c 'grep -qF "# >>> prefix activation (install-homebrew) >>>" ~/.bash_profile 2>/dev/null ||
             grep -qF "# >>> prefix activation (install-homebrew) >>>" ~/.bash_login  2>/dev/null ||
             grep -qF "# >>> prefix activation (install-homebrew) >>>" ~/.profile      2>/dev/null'
check "~/.bashrc has shellenv marker" \
  grep -qF '# >>> prefix activation (install-homebrew) >>>' "${_HOME}/.bashrc"
check "~/.zshenv has shellenv marker" \
  grep -qF '# >>> prefix activation (install-homebrew) >>>' "${_HOME}/.zshenv"

reportResults
