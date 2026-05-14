#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # bash -c literal script, ~/ in labels
# export_path_idempotent: setup pre-seeds one stale activation block per dotfile;
# a single feature run with default options must update that block in place
# (exactly one begin marker per file; inner line matches resolved brew prefix).
#
# Cleanup: removes activation blocks from user dotfiles on EXIT.
set -e

source dev-container-features-test-lib

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_HOME="$HOME"
_MARKER='prefix activation (install-homebrew)'
_BASH_LOGIN_FILE="$(detect_bash_login_file)"

_cleanup() {
  for f in "${_HOME}/.bash_profile" "${_HOME}/.bash_login" "${_HOME}/.profile" \
    "${_HOME}/.bashrc" "${_HOME}/.zshenv"; do
    shellenv_block_cleanup "$f"
  done
}
trap _cleanup EXIT

_test_failure_diagnostics() {
  log_install_homebrew_shell_init_diagnostics "${_HOME}" "${_BASH_LOGIN_FILE}"
  printf 'Expected brew path fragment: %s\n' "${_BREW_PREFIX}/bin/brew" >&2
  local f
  for f in "${_HOME}/.bashrc" "${_HOME}/.zshenv"; do
    echo "" >&2
    printf -- '--- %s (cat -v) ---\n' "$f" >&2
    if [[ -f "$f" ]]; then
      cat -v "$f" >&2
    else
      echo "(missing)" >&2
    fi
  done
}

# --- brew is intact ---
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- exactly one begin marker per file (no duplicates) ---
check "resolved bash login file has exactly one begin marker" \
  bash -c '[[ "$({ grep -cF "# >>> '"$_MARKER"' >>>" "$1" 2>/dev/null || echo 0; })" -eq 1 ]]' -- "$_BASH_LOGIN_FILE"
check "~/.bashrc has exactly one begin marker" \
  bash -c '[[ "$({ grep -cF "# >>> '"$_MARKER"' >>>" ~/.bashrc        2>/dev/null || echo 0; })" -eq 1 ]]'
check "~/.zshenv has exactly one begin marker" \
  bash -c '[[ "$({ grep -cF "# >>> '"$_MARKER"' >>>" ~/.zshenv        2>/dev/null || echo 0; })" -eq 1 ]]'

# --- stale placeholder must be gone; block must reference real brew ---
check "resolved bash login file block references resolved brew binary" \
  bash -c 'grep -qF "$2" "$1"' -- "$_BASH_LOGIN_FILE" "${_BREW_PREFIX}/bin/brew"
check "~/.bashrc block references resolved brew binary" \
  bash -c 'grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.bashrc'
check "~/.zshenv block references resolved brew binary" \
  bash -c 'grep -qF "'"${_BREW_PREFIX}/bin/brew"'" ~/.zshenv'
check "resolved bash login file has no stale placeholder" \
  bash -c 'awk '"'"'/# >>> prefix activation \(install-homebrew\) >>>/{in_block=1;next} /# <<< prefix activation \(install-homebrew\) <<</{in_block=0} in_block{print}'"'"' "$1" | grep -qv "__stale_prefix__"' -- "$_BASH_LOGIN_FILE"
check "~/.bashrc has no stale placeholder" \
  bash -c 'awk '"'"'/# >>> prefix activation \(install-homebrew\) >>>/{in_block=1;next} /# <<< prefix activation \(install-homebrew\) <<</{in_block=0} in_block{print}'"'"' ~/.bashrc | grep -qv "__stale_prefix__"'
check "~/.zshenv has no stale placeholder" \
  bash -c 'awk '"'"'/# >>> prefix activation \(install-homebrew\) >>>/{in_block=1;next} /# <<< prefix activation \(install-homebrew\) <<</{in_block=0} in_block{print}'"'"' ~/.zshenv | grep -qv "__stale_prefix__"'

echo "=== ~/.zshenv ==="
cat "${_HOME}/.zshenv" 2> /dev/null || echo "(missing)"

reportResults
