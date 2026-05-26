# Phase 1 skeleton — mechanically extracted from install-shell/install.bash
# Feature: install-direnv
# Not yet functional. Wired up in this feature's own semantic phase.
# shellcheck shell=bash

# --- direnv sub-block of Step 2.5 + blank (original lines 654–658) ---
if [[ "$INSTALL_DIRENV" == true ]]; then
  logging__install "Installing direnv..."
  ospkg__install_user direnv
fi

# --- configure_user preamble: vars used by the direnv blocks (from configure_user()) ---
_cu_zshtheme_content=""
_cu_bashtheme_content=""

# --- configure_user: direnv zsh hook + trailing blank (original lines 462–467) ---
# Append direnv hook for zsh.
if [[ "$INSTALL_DIRENV" == true ]]; then
  # shellcheck disable=SC2016
  _cu_zshtheme_content+='command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"'$'\n'
fi

# --- configure_user: direnv bash hook + trailing blank (original lines 579–584) ---
# Append direnv hook for bash.
if [[ "$INSTALL_DIRENV" == true ]]; then
  # shellcheck disable=SC2016
  _cu_bashtheme_content+='command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"'$'\n'
fi
