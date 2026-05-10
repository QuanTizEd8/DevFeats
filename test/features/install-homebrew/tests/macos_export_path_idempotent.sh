#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # bash -c literal script, ~/ in labels
# export_path_idempotent: setup pre-seeds one stale shellenv block per dotfile;
# a single feature run with export_path=auto must update that block in place
# (exactly one begin marker per file; inner line matches resolved brew prefix).
#
# Cleanup: removes shellenv blocks from all four user dotfiles on EXIT.
set -e

source dev-container-features-test-lib

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_HOME="$HOME"
_BASH_LOGIN_FILE="$(detect_bash_login_file)"

_cleanup() {
  for f in "${_HOME}/.bash_profile" "${_HOME}/.bash_login" "${_HOME}/.profile" \
    "${_HOME}/.bashrc" "${_HOME}/.zprofile" "${_HOME}/.zshrc"; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT

# --- brew is intact ---
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- exactly one begin marker per file (no duplicates) ---
_count_marker() {
  local f="$1"
  [[ -f "$f" ]] || echo 0
  grep -cF '# >>> brew shellenv (install-homebrew) >>>' "$f" 2> /dev/null || echo 0
}
export -f _count_marker 2> /dev/null || true

check "resolved bash login file has exactly one begin marker" \
  bash -c '[[ "$({ grep -cF "# >>> brew shellenv (install-homebrew) >>>" "$1" 2>/dev/null || echo 0; })" -eq 1 ]]' -- "$_BASH_LOGIN_FILE"
check "~/.bashrc has exactly one begin marker" \
  bash -c '[[ "$({ grep -cF "# >>> brew shellenv (install-homebrew) >>>" ~/.bashrc        2>/dev/null || echo 0; })" -eq 1 ]]'
check "~/.zprofile has exactly one begin marker" \
  bash -c '[[ "$({ grep -cF "# >>> brew shellenv (install-homebrew) >>>" ~/.zprofile      2>/dev/null || echo 0; })" -eq 1 ]]'
check "~/.zshrc has exactly one begin marker" \
  bash -c '[[ "$({ grep -cF "# >>> brew shellenv (install-homebrew) >>>" ~/.zshrc         2>/dev/null || echo 0; })" -eq 1 ]]'

# --- stale placeholder must be gone; block must reference real brew ---
check "resolved bash login file block references resolved brew binary" \
  bash -c 'grep -qF "$2" "$1"' -- "$_BASH_LOGIN_FILE" "${_BREW_PREFIX}/bin/brew"
check "~/.bashrc block references resolved brew binary" \
  bash -c 'grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.bashrc'
check "~/.zprofile block references resolved brew binary" \
  bash -c 'grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.zprofile'
check "~/.zshrc block references resolved brew binary" \
  bash -c 'grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.zshrc'
check "resolved bash login file shellenv snippet has no stale placeholder" \
  bash -c 'awk '"'"'/# >>> brew shellenv \(install-homebrew\) >>>/{in_block=1;next} /# <<< brew shellenv \(install-homebrew\) <<</{in_block=0} in_block{print}'"'"' "$1" | grep -qv "__stale_prefix__"' -- "$_BASH_LOGIN_FILE"
check "~/.bashrc shellenv snippet has no stale placeholder" \
  bash -c 'awk '"'"'/# >>> brew shellenv \(install-homebrew\) >>>/{in_block=1;next} /# <<< brew shellenv \(install-homebrew\) <<</{in_block=0} in_block{print}'"'"' ~/.bashrc | grep -qv "__stale_prefix__"'
check "~/.zprofile shellenv snippet has no stale placeholder" \
  bash -c 'awk '"'"'/# >>> brew shellenv \(install-homebrew\) >>>/{in_block=1;next} /# <<< brew shellenv \(install-homebrew\) <<</{in_block=0} in_block{print}'"'"' ~/.zprofile | grep -qv "__stale_prefix__"'
check "~/.zshrc shellenv snippet has no stale placeholder" \
  bash -c 'awk '"'"'/# >>> brew shellenv \(install-homebrew\) >>>/{in_block=1;next} /# <<< brew shellenv \(install-homebrew\) <<</{in_block=0} in_block{print}'"'"' ~/.zshrc | grep -qv "__stale_prefix__"'

echo "=== ~/.zprofile ==="
cat "${_HOME}/.zprofile" 2> /dev/null || echo "(missing)"
echo "=== ~/.zshrc ==="
cat "${_HOME}/.zshrc" 2> /dev/null || echo "(missing)"

reportResults
