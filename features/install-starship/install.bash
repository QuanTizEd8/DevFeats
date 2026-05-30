# shellcheck shell=bash

_STARSHIP_INSTALLER_URL="https://starship.rs/install.sh"

# ---------------------------------------------------------------------------
# install_starship — Download and run the official Starship installer.
# ---------------------------------------------------------------------------
install_starship() {
  local _bin_dir="${PREFIX}/bin"

  if [ -x "${_bin_dir}/starship" ]; then
    logging__info "Starship already installed at '${_bin_dir}/starship' — skipping."
    return 0
  fi

  logging__info "Installing Starship to '${_bin_dir}'..."
  local _asset_dir
  _asset_dir="$(uri__fetch_asset "$_STARSHIP_INSTALLER_URL" --chmod-exec install.sh)"
  sh "${_asset_dir}/install.sh" --yes --bin-dir "$_bin_dir" >&2

  if [ -x "${_bin_dir}/starship" ]; then
    logging__success "Starship installed to '${_bin_dir}/starship'."
  else
    logging__error "Starship installation failed."
    return 1
  fi
}

# ---------------------------------------------------------------------------
# _configure_user_starship <username>
# Injects guarded starship init hooks into the appropriate rc files.
# Zsh rcfile resolution (when zsh is in STARSHIP_SHELLS):
#   1. Run zsh as the user to read ZDOTDIR from the shell's startup chain.
#   2. _zsh_rcdir = ${ZDOTDIR:-${HOME}}
#   3. zshtheme exists → write there; .zshrc exists → create zshtheme + inject
#      source; else → write directly to .zshrc.
# Bash rcfile resolution (when bash is in STARSHIP_SHELLS):
#   Same pattern using XDG_CONFIG_HOME/bash/bashtheme and .bashrc.
# ---------------------------------------------------------------------------
_configure_user_starship() {
  local _username="$1"
  local _home
  _home="$(users__resolve_home "$_username")"
  local _group
  _group="$(users__primary_group_of "$_username" 2> /dev/null || echo "$_username")"

  logging__info "Configuring Starship for user '${_username}' (home: ${_home})..."

  local _shells="${STARSHIP_SHELLS[*]}"

  # --- Zsh hook ---
  if [[ "$_shells" == *zsh* ]]; then
    if ! command -v starship > /dev/null 2>&1 && [ ! -x "${PREFIX}/bin/starship" ]; then
      logging__warn "starship_shells includes 'zsh' but starship is not on PATH — integration injected anyway."
    fi

    local _zsh_rcfile _zsh_rcdir
    local _zdotdir=""
    if command -v zsh > /dev/null 2>&1; then
      # shellcheck disable=SC2016  # $ZDOTDIR is a zsh variable, not a shell variable
      _zdotdir="$(users__run_as "$_username" -- zsh -c 'printf "%s" "$ZDOTDIR"' \
        2> /dev/null || true)"
    fi
    _zsh_rcdir="${_zdotdir:-${_home}}"

    if [ -f "${_zsh_rcdir}/zshtheme" ]; then
      _zsh_rcfile="${_zsh_rcdir}/zshtheme"
    elif [ -f "${_zsh_rcdir}/.zshrc" ]; then
      _zsh_rcfile="${_zsh_rcdir}/zshtheme"
      # shellcheck disable=SC2016
      shell__write_block --file "${_zsh_rcdir}/.zshrc" --marker "install-starship-zsh-source" \
        --content '[ -f "${ZDOTDIR:-$HOME}/zshtheme" ] && source "${ZDOTDIR:-$HOME}/zshtheme"'
    else
      _zsh_rcfile="${_zsh_rcdir}/.zshrc"
    fi

    mkdir -p "$_zsh_rcdir"
    # shellcheck disable=SC2016
    shell__write_block --file "$_zsh_rcfile" --marker "install-starship-zsh" \
      --content 'command -v starship > /dev/null 2>&1 && eval "$(starship init zsh)"'
  fi

  # --- Bash hook ---
  if [[ "$_shells" == *bash* ]]; then
    if ! command -v starship > /dev/null 2>&1 && [ ! -x "${PREFIX}/bin/starship" ]; then
      logging__warn "starship_shells includes 'bash' but starship is not on PATH — integration injected anyway."
    fi

    local _bash_rcfile _bash_rcdir
    local _xdg_config_home=""
    # shellcheck disable=SC2016  # ${XDG_CONFIG_HOME:-} is a bash variable for the target user's shell
    _xdg_config_home="$(users__run_as "$_username" -- bash -c 'printf "%s" "${XDG_CONFIG_HOME:-}"' \
      2> /dev/null || true)"
    _bash_rcdir="${_xdg_config_home:-${_home}/.config}/bash"

    if [ -f "${_bash_rcdir}/bashtheme" ]; then
      _bash_rcfile="${_bash_rcdir}/bashtheme"
    elif [ -f "${_home}/.bashrc" ]; then
      _bash_rcfile="${_bash_rcdir}/bashtheme"
      # shellcheck disable=SC2016
      shell__write_block --file "${_home}/.bashrc" --marker "install-starship-bash-source" \
        --content '[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme"'
    else
      _bash_rcfile="${_home}/.bashrc"
    fi

    mkdir -p "$_bash_rcdir"
    # shellcheck disable=SC2016
    shell__write_block --file "$_bash_rcfile" --marker "install-starship-bash" \
      --content 'command -v starship > /dev/null 2>&1 && eval "$(starship init bash)"'
  fi

  file__chown -R "${_username}:${_group}" "$_home"
  logging__success "User '${_username}' Starship configuration complete."
}

# ===================================================================
# Install Starship
# ===================================================================
install_starship

# ===================================================================
# Per-user configuration
# ===================================================================
_STARSHIP_SHELLS="${STARSHIP_SHELLS[*]}"
if [ -n "$_STARSHIP_SHELLS" ]; then
  mapfile -t _STARSHIP_USERS < <(users__resolve_list)
  for _username in "${_STARSHIP_USERS[@]}"; do
    if ! id "$_username" > /dev/null 2>&1; then
      logging__warn "User '${_username}' does not exist — skipping."
      continue
    fi
    _configure_user_starship "$_username"
  done
else
  logging__info "starship_shells is empty — skipping per-user configuration."
fi
