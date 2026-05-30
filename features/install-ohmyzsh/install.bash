# shellcheck shell=bash

# ---------------------------------------------------------------------------
# install_ohmyzsh — Clone OMZ to INSTALL_DIR, scaffold ZSH_CUSTOM,
#                   clone custom theme/plugins.
# ---------------------------------------------------------------------------
__install_run__() {
  if ! command -v zsh > /dev/null 2>&1; then
    logging__warn "Zsh not available — skipping Oh My Zsh installation."
    return 0
  fi
  local _GITHUB_BASE_URL="${_GITHUB_BASE_URL:-https://github.com}"
  local _OHMYZSH_REPO_URL="${_GITHUB_BASE_URL}/ohmyzsh/ohmyzsh"
  local _install_dir="$INSTALL_DIR"
  local _branch="$BRANCH"
  local _theme="$THEME"
  # Use an explicit system-path custom dir if given; per-user paths (~/$HOME-prefixed)
  # and the empty default are handled at configure-user time via symlinks.
  local _custom_dir
  # shellcheck disable=SC2016
  if [ -n "$CUSTOM_DIR" ] &&
    [[ "$CUSTOM_DIR" != '~'* ]] &&
    [[ "$CUSTOM_DIR" != '$HOME'* ]]; then
    _custom_dir="$CUSTOM_DIR"
  else
    _custom_dir="${_install_dir}/custom"
  fi

  logging__info "Installing Oh My Zsh to '${_install_dir}' (branch: ${_branch})..."
  local _prev_umask
  _prev_umask="$(umask)"
  umask g-w,o-w
  git__clone --url "$_OHMYZSH_REPO_URL" --dir "$_install_dir" --branch "$_branch"
  umask "$_prev_umask"

  # Set oh-my-zsh update metadata so 'omz update' knows which remote/branch.
  git -C "$_install_dir" config oh-my-zsh.remote origin
  git -C "$_install_dir" config oh-my-zsh.branch "$_branch"

  mkdir -p "${_custom_dir}/themes" "${_custom_dir}/plugins"

  if [ -n "$_theme" ]; then
    local _theme_repo_name
    _theme_repo_name="$(basename "$_theme")"
    git__clone --url "${_GITHUB_BASE_URL}/${_theme}" --dir "${_custom_dir}/themes/${_theme_repo_name}"
    logging__info "Installed custom theme '${_theme}'."
  fi

  local _slug
  for _slug in "${PLUGINS[@]}"; do
    _slug="${_slug// /}"
    [ -z "$_slug" ] && continue
    if [[ "$_slug" != */* ]]; then
      logging__info "'${_slug}' is a built-in plugin — skipping clone."
      continue
    fi
    local _plugin_name
    _plugin_name="$(basename "$_slug")"
    git__clone --url "${_GITHUB_BASE_URL}/${_slug}" --dir "${_custom_dir}/plugins/${_plugin_name}"
    logging__info "Installed custom plugin '${_slug}'."
  done

  logging__success "Oh My Zsh installation complete."
}

# ---------------------------------------------------------------------------
# _resolve_custom_dir <raw_value> <user_home>
# Expands ~- and $HOME-prefixed paths; passes absolute paths through unchanged.
# ---------------------------------------------------------------------------
_resolve_custom_dir() {
  local _raw="$1" _home="$2"
  # shellcheck disable=SC2016
  if [[ "$_raw" == '~'* ]]; then
    printf '%s%s' "$_home" "${_raw#\~}"
  elif [[ "$_raw" == '$HOME'* ]]; then
    printf '%s%s' "$_home" "${_raw#'$HOME'}"
  else
    printf '%s' "$_raw"
  fi
}

# ---------------------------------------------------------------------------
# _link_custom_items <src_custom_dir> <dest_custom_dir> <theme_slug> <mode> [<plugin_slug>...]
# Creates symlinks in dest for exactly the named items declared in theme_slug + plugin slugs.
#   overwrite: removes existing symlink for that name, creates fresh one (skips real dirs)
#   augment:   creates symlink only if name not already present (symlink or real dir)
# User-added real dirs (non-symlinks) are never removed.
_link_custom_items() {
  local _src="$1" _dest="$2" _theme_slug="$3" _mode="$4"
  shift 4
  mkdir -p "${_dest}/themes" "${_dest}/plugins"

  local -a _items=()
  if [ -n "$_theme_slug" ]; then
    _items+=("themes/$(basename "$_theme_slug")")
  fi
  local _slug
  for _slug in "$@"; do
    _slug="${_slug// /}"
    [ -z "$_slug" ] && continue
    [[ "$_slug" != */* ]] && continue # built-in plugin, no clone
    _items+=("plugins/$(basename "$_slug")")
  done

  local _item _src_path _dest_path
  for _item in "${_items[@]}"; do
    _src_path="${_src}/${_item}"
    _dest_path="${_dest}/${_item}"
    [ -d "$_src_path" ] || continue # not cloned, skip
    if [[ "$_mode" == "overwrite" ]]; then
      [ -L "$_dest_path" ] && rm "$_dest_path"
      [ ! -e "$_dest_path" ] && ln -sf "$_src_path" "$_dest_path"
    else
      [ ! -e "$_dest_path" ] && ln -sf "$_src_path" "$_dest_path"
    fi
  done
}

# ---------------------------------------------------------------------------
# _configure_user_ohmyzsh <username>
# Injects a guarded OMZ setup block into the appropriate rc file for the user.
# Rcfile resolution (when RCFILE option is empty):
#   1. Run zsh as the user to read ZDOTDIR from the shell's startup chain.
#   2. _rcdir = ${ZDOTDIR:-${HOME}} (zsh native default when ZDOTDIR unset).
#   3. If ${_rcdir}/zshtheme exists  → write there (install-shell integration).
#   4. Else if ${_rcdir}/.zshrc exists → create zshtheme + inject source line.
#   5. Else → create .zshrc and write the OMZ block directly there.
# ---------------------------------------------------------------------------
__configure_user() {
  local _username="$1"
  local _home
  _home="$(users__resolve_home "$_username")"
  local _group
  _group="$(users__primary_group_of "$_username" 2> /dev/null || echo "$_username")"

  logging__info "Configuring Oh My Zsh for user '${_username}' (home: ${_home})..."

  # Resolve rcfile and the directory used as ZDOTDIR for ZSH_CUSTOM default.
  local _rcfile _rcdir _inject_source=false
  if [ -n "$RCFILE" ]; then
    # shellcheck disable=SC2016
    if [[ "$RCFILE" == '~'* ]]; then
      _rcfile="${_home}${RCFILE#\~}"
    elif [[ "$RCFILE" == '$HOME'* ]]; then
      _rcfile="${_home}${RCFILE#'$HOME'}"
    else
      _rcfile="$RCFILE"
    fi
    _rcdir="$(dirname "$_rcfile")"
  else
    local _zdotdir=""
    if command -v zsh > /dev/null 2>&1; then
      # shellcheck disable=SC2016  # $ZDOTDIR is a zsh variable, not a shell variable
      _zdotdir="$(users__run_as "$_username" -- zsh -c 'printf "%s" "$ZDOTDIR"' \
        2> /dev/null || true)"
    fi
    _rcdir="${_zdotdir:-${_home}}"
    if [ -f "${_rcdir}/zshtheme" ]; then
      _rcfile="${_rcdir}/zshtheme"
    elif [ -f "${_rcdir}/.zshrc" ]; then
      _rcfile="${_rcdir}/zshtheme"
      _inject_source=true
    else
      _rcfile="${_rcdir}/.zshrc"
    fi
  fi

  local _custom_dir_raw="${CUSTOM_DIR:-}"
  [ -z "$_custom_dir_raw" ] && _custom_dir_raw="${_rcdir}/custom"
  local _effective_custom_dir
  _effective_custom_dir="$(_resolve_custom_dir "$_custom_dir_raw" "$_home")"

  local _is_per_user=false
  [[ "$_effective_custom_dir" == "${_home}"* ]] && _is_per_user=true

  local _is_p10k=false
  [[ "$THEME" == *powerlevel10k* ]] && _is_p10k=true

  local _theme_value=""
  if [ -n "$THEME" ]; then
    _theme_value="$(shell__resolve_omz_theme \
      --theme_slug "$THEME" \
      --custom_dir "${INSTALL_DIR}/custom")"
  fi

  local _plugin_names=""
  if ((${#PLUGINS[@]})); then
    _plugin_names="$(str__basename_each "${PLUGINS[@]}" | tr '\n' ' ')"
    _plugin_names="${_plugin_names% }"
  fi

  # shellcheck disable=SC2016
  local _content
  _content="export ZSH=\"${INSTALL_DIR}\""$'\n'
  # shellcheck disable=SC2016
  _content+='ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"'$'\n'
  # shellcheck disable=SC2016
  _content+='[ -d "$ZSH_CACHE_DIR" ] || mkdir -p "$ZSH_CACHE_DIR"'$'\n'
  # shellcheck disable=SC2016
  _content+='ZSH_COMPDUMP="${ZSH_CACHE_DIR}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"'$'\n'
  _content+="ZSH_CUSTOM=\"${_effective_custom_dir}\""$'\n'

  if [ -n "$_theme_value" ]; then
    _content+="ZSH_THEME=\"${_theme_value}\""$'\n'
  else
    _content+='ZSH_THEME=""'$'\n'
  fi

  if [ -n "$_plugin_names" ]; then
    _content+="plugins=(${_plugin_names})"$'\n'
  else
    _content+='plugins=()'$'\n'
  fi

  _content+="zstyle ':omz:update' mode disabled"$'\n'

  if [[ "$_is_p10k" == true ]]; then
    _content+='POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true'$'\n'
  fi

  # shellcheck disable=SC2016
  _content+='[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"'$'\n'

  if [[ "$_is_p10k" == true ]]; then
    # shellcheck disable=SC2016
    _content+='[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"'$'\n'
  fi

  mkdir -p "$_rcdir"
  shell__write_block --file "$_rcfile" --marker "install-ohmyzsh" --content "$_content"

  # Case 4: .zshrc existed but zshtheme didn't — wire up the source line.
  if [[ "$_inject_source" == true ]]; then
    # shellcheck disable=SC2016
    shell__write_block --file "${_rcdir}/.zshrc" --marker "install-ohmyzsh-source" \
      --content '[ -f "${ZDOTDIR:-$HOME}/zshtheme" ] && source "${ZDOTDIR:-$HOME}/zshtheme"'
  fi

  if [[ "$_is_per_user" == true ]]; then
    _link_custom_items \
      "${INSTALL_DIR}/custom" \
      "$_effective_custom_dir" \
      "$THEME" \
      "$USER_CONFIG_MODE" \
      "${PLUGINS[@]}"
  fi

  local _p10k_skel="${_FEAT_FILES_DIR}/skel/p10k.zsh"
  if [[ "$_is_p10k" == true ]] && [ -f "$_p10k_skel" ]; then
    case "$USER_CONFIG_MODE" in
      overwrite) cp -f "$_p10k_skel" "${_home}/.p10k.zsh" ;;
      augment) [ ! -f "${_home}/.p10k.zsh" ] && cp "$_p10k_skel" "${_home}/.p10k.zsh" ;;
    esac
  fi

  file__chown -R "${_username}:${_group}" "$_home"
  logging__success "User '${_username}' Oh My Zsh configuration complete."
}

__install_finish_post() {
  __feat_do_configure_users__
}
