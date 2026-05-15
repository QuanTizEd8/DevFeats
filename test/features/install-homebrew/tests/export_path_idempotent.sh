#!/bin/bash
# export_path_idempotent: activation blocks are pre-written in the image
# (see scenario setup). The feature re-runs with default options (if_exists=skip)
# and must UPDATE each block in-place — the begin marker must appear exactly
# once per file (no duplicate appends).
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew
_MARKER='prefix activation (install-homebrew)'
_PROFILE_D="QuanTizEd8-DevFeats-install-homebrew-prefix-activation.sh"

# --- brew is functional ---
check "brew binary installed" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- blocks are present in each file ---
check "profile.d file has begin marker" grep -qF "# >>> ${_MARKER} >>>" "/etc/profile.d/${_PROFILE_D}"
check "bash.bashrc has begin marker" grep -qF "# >>> ${_MARKER} >>>" /etc/bash.bashrc
check "zshenv has begin marker" grep -qF "# >>> ${_MARKER} >>>" /etc/zsh/zshenv

# --- exactly one copy of the block per file (no duplicates) ---
echo "=== /etc/profile.d/${_PROFILE_D} ==="
cat "/etc/profile.d/${_PROFILE_D}" 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc (tail) ==="
tail -15 /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"

check "profile.d file has exactly one begin marker" \
  bash -c '[ "$(grep -cF "# >>> '"${_MARKER}"' >>>" "/etc/profile.d/'"${_PROFILE_D}"'")" -eq 1 ]'
check "bash.bashrc has exactly one begin marker" \
  bash -c '[ "$(grep -cF "# >>> '"${_MARKER}"' >>>" /etc/bash.bashrc)" -eq 1 ]'
check "zshenv has exactly one begin marker" \
  bash -c '[ "$(grep -cF "# >>> '"${_MARKER}"' >>>" /etc/zsh/zshenv)" -eq 1 ]'

# --- the content references the correct brew prefix ---
check "profile.d block references correct brew prefix" \
  grep -qF '/home/linuxbrew/.linuxbrew/bin/brew' "/etc/profile.d/${_PROFILE_D}"
check "bash.bashrc block references correct brew prefix" \
  grep -qF '/home/linuxbrew/.linuxbrew/bin/brew' /etc/bash.bashrc
check "zshenv block references correct brew prefix" \
  grep -qF '/home/linuxbrew/.linuxbrew/bin/brew' /etc/zsh/zshenv

reportResults
