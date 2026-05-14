#!/usr/bin/env bash
# shellcheck disable=SC2088  # ~/ in check labels is intentional (display only)
# export_path_disabled: prefix_activations="" skips all activation writes.
# Verifies that brew is intact (if_exists=skip) and that no activation blocks
# are written to any user dotfiles.
set -e

source dev-container-features-test-lib

_BREW_PREFIX="$(brew --prefix 2> /dev/null)"
_BREW="${_BREW_PREFIX}/bin/brew"
_MARKER='prefix activation (install-homebrew)'

# No cleanup needed: this scenario must not write to any file.

# --- brew is intact ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew binary present" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- no activation blocks written to any file ---
check "~/.bash_profile has NO activation marker" \
  bash -c '! grep -qF "'"$_MARKER"'" ~/.bash_profile 2>/dev/null'
check "~/.bashrc has NO activation marker" \
  bash -c '! grep -qF "'"$_MARKER"'" ~/.bashrc 2>/dev/null'
check "~/.zshenv has NO activation marker" \
  bash -c '! grep -qF "'"$_MARKER"'" ~/.zshenv 2>/dev/null'

reportResults
