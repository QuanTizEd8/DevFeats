#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # bash -c literal script, ~/ in labels
# fresh_install: env `macos-latest-fresh-install` bootstraps with the official
# Homebrew uninstall (see test/environments.yaml), then the feature install runs —
# full macOS path (fetch, official install script, Case B shellenv). Assert post-install
# only; use "${_BREW_PREFIX}/bin/brew" — bare `brew` is not on PATH (no path_prepend).
#
# ⚠️  DESTRUCTIVE for the job: env bootstrap removes Homebrew; the feature reinstalls it.
#
# Cleanup: removes shellenv blocks from user dotfiles on EXIT (brew stays installed).
set -e

source dev-container-features-test-lib

_HOME="$HOME"

_cleanup() {
  block_cleanup_all "prefix activation (install-homebrew)"
}
trap _cleanup EXIT

# Prefix the feature chooses (same as detect_brew_prefix).
if [[ "$(uname -m)" == "arm64" ]]; then
  _BREW_PREFIX="/opt/homebrew"
else
  _BREW_PREFIX="/usr/local"
fi
_BREW="${_BREW_PREFIX}/bin/brew"

echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"

check "brew prefix directory exists" test -d "$_BREW_PREFIX"
check "brew binary installed" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
check "brew --version succeeds" "$_BREW" --version
check "brew --version reports Homebrew" bash -c '"$1" --version | grep -q Homebrew' -- "$_BREW"

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

check "shellenv block references correct brew prefix" \
  bash -c 'grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.zshenv 2>/dev/null ||
             grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.bash_profile 2>/dev/null'

_ACTUAL_PREFIX="$("${_BREW}" --prefix 2> /dev/null || true)"
echo "=== brew --prefix: ${_ACTUAL_PREFIX} ==="
check "brew --prefix returns expected prefix" test "$_ACTUAL_PREFIX" = "$_BREW_PREFIX"

reportResults
