# Phase 1 skeleton — mechanically extracted from install-shell/install.bash
# Feature: install-bash-completion
# Not yet functional. Wired up in this feature's own semantic phase.
# shellcheck shell=bash

# --- Step 2.5 header + bash-completion sub-block + blank (original lines 641–648) ---
# ===================================================================
# Step 2.5: Install shell tool integrations
# ===================================================================
if [[ "$INSTALL_BASH_COMPLETION" == true ]]; then
  logging__install "Installing bash-completion..."
  ospkg__run --manifest $'packages:\n  - name: bash-completion\n    brew: bash-completion@2'
fi

# --- configure_user preamble: vars used by the bash-completion block (from configure_user()) ---
_cu_bashtheme_content=""

# --- configure_user: bash-completion Homebrew hook + trailing blank (original lines 506–518) ---
# Source bash-completion entry point for Homebrew.
# On Linux, the package installs to /etc/profile.d/ which is auto-sourced;
# on Homebrew the entry point lives at $HOMEBREW_PREFIX/etc/profile.d/ and
# must be sourced explicitly.
# Check for the actual installed file (not just brew presence) to avoid
# injecting the hook when brew exists but a different PM installed the pkg.
if [[ "$INSTALL_BASH_COMPLETION" == true ]] &&
  command -v brew > /dev/null 2>&1 &&
  [[ -f "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]]; then
  # shellcheck disable=SC2016
  _cu_bashtheme_content+='[[ -n "${HOMEBREW_PREFIX:-}" ]] && [[ -s "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]] && . "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh"'$'\n'
fi
