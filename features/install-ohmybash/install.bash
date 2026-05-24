# shellcheck shell=bash

_GITHUB_BASE_URL="${_GITHUB_BASE_URL:-https://github.com}"
_OHMYBASH_REPO_URL="${_GITHUB_BASE_URL}/${OHMYBASH_GH_REPO}"

# ---------------------------------------------------------------------------
# install_ohmybash — Clone OMB to INSTALL_DIR, scaffold OSH_CUSTOM,
#                    clone custom theme/plugins.
# ---------------------------------------------------------------------------
install_ohmybash() {
  local _install_dir="$INSTALL_DIR"
  local _branch="$BRANCH"
  local _theme="$THEME"
  local _custom_dir
  # shellcheck disable=SC2016
  if [ -n "$CUSTOM_DIR" ] &&
    [[ "$CUSTOM_DIR" != '~'* ]] &&
    [[ "$CUSTOM_DIR" != '$HOME'* ]]; then
    _custom_dir="$CUSTOM_DIR"
  else
    _custom_dir="${_install_dir}/custom"
  fi

  logging__info "Installing Oh My Bash to '${_install_dir}' (branch: ${_branch})..."
  local _prev_umask
  _prev_umask="$(umask)"
  umask g-w,o-w
  git__clone --url "$_OHMYBASH_REPO_URL" --dir "$_install_dir" --branch "$_branch"
  umask "$_prev_umask"

  # Set update metadata so 'omb update' knows which remote/branch.
  git -C "$_install_dir" config oh-my-bash.remote origin
  git -C "$_install_dir" config oh-my-bash.branch "$_branch"

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

  logging__success "Oh My Bash installation complete."
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
# _configure_user_ohmybash <username>
# Injects a guarded OMB setup block into the appropriate rc file for the user.
# Rcfile resolution (when RCFILE option is empty):
#   1. Run bash as the user to read XDG_CONFIG_HOME from the shell's startup chain.
#   2. _rcdir = ${XDG_CONFIG_HOME:-${HOME}/.config}/bash
#   3. If ${_rcdir}/bashtheme exists  → write there (install-shell integration).
#   4. Else if ${_home}/.bashrc exists → create bashtheme + inject source line.
#   5. Else → write OMB block directly into .bashrc.
# ---------------------------------------------------------------------------
_configure_user_ohmybash() {
  local _username="$1"
  local _home
  _home="$(users__resolve_home "$_username")"
  local _group
  _group="$(users__primary_group_of "$_username" 2> /dev/null || echo "$_username")"

  logging__info "Configuring Oh My Bash for user '${_username}' (home: ${_home})..."

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
    local _xdg_config_home=""
    _xdg_config_home="$(users__run_as "$_username" -- bash -c 'printf "%s" "${XDG_CONFIG_HOME:-}"' \
      2> /dev/null || true)"
    _rcdir="${_xdg_config_home:-${_home}/.config}/bash"
    if [ -f "${_rcdir}/bashtheme" ]; then
      _rcfile="${_rcdir}/bashtheme"
    elif [ -f "${_home}/.bashrc" ]; then
      _rcfile="${_rcdir}/bashtheme"
      _inject_source=true
    else
      _rcfile="${_home}/.bashrc"
    fi
  fi

  local _custom_dir_raw="${CUSTOM_DIR:-}"
  [ -z "$_custom_dir_raw" ] && _custom_dir_raw="${_rcdir}/custom"
  local _effective_custom_dir
  _effective_custom_dir="$(_resolve_custom_dir "$_custom_dir_raw" "$_home")"

  local _is_per_user=false
  [[ "$_effective_custom_dir" == "${_home}"* ]] && _is_per_user=true

  local _theme_value=""
  [ -n "$THEME" ] && _theme_value="$(basename "$THEME")"

  local _plugin_names=""
  if ((${#PLUGINS[@]})); then
    _plugin_names="$(str__basename_each "${PLUGINS[@]}" | tr '\n' ' ')"
    _plugin_names="${_plugin_names% }"
  fi

  # shellcheck disable=SC2016
  local _content
  _content="export OSH=\"${INSTALL_DIR}\""$'\n'
  # shellcheck disable=SC2016
  _content+='OSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-bash"'$'\n'
  # shellcheck disable=SC2016
  _content+='[ -d "$OSH_CACHE_DIR" ] || mkdir -p "$OSH_CACHE_DIR"'$'\n'
  _content+="OSH_CUSTOM=\"${_effective_custom_dir}\""$'\n'

  if [ -n "$_theme_value" ]; then
    _content+="OSH_THEME=\"${_theme_value}\""$'\n'
  else
    _content+='OSH_THEME=""'$'\n'
  fi

  if [ -n "$_plugin_names" ]; then
    _content+="plugins=(${_plugin_names})"$'\n'
  else
    _content+='plugins=()'$'\n'
  fi

  # shellcheck disable=SC2016
  _content+='[ -f "$OSH/oh-my-bash.sh" ] && source "$OSH/oh-my-bash.sh"'$'\n'

  mkdir -p "$_rcdir"
  shell__write_block --file "$_rcfile" --marker "install-ohmybash" --content "$_content"

  # Case 4: .bashrc existed but bashtheme didn't — wire up the source line.
  if [[ "$_inject_source" == true ]]; then
    # shellcheck disable=SC2016
    shell__write_block --file "${_home}/.bashrc" --marker "install-ohmybash-source" \
      --content '[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme"'
  fi

  if [[ "$_is_per_user" == true ]] && [[ "$USER_CONFIG_MODE" != "skip" ]]; then
    _link_custom_items \
      "${INSTALL_DIR}/custom" \
      "$_effective_custom_dir" \
      "$THEME" \
      "$USER_CONFIG_MODE" \
      "${PLUGINS[@]}"
  fi

  file__chown -R "${_username}:${_group}" "$_home"
  logging__success "User '${_username}' Oh My Bash configuration complete."
}

# ===================================================================
# Install Oh My Bash
# ===================================================================
if ! command -v bash > /dev/null 2>&1; then
  logging__warn "Bash not available — skipping Oh My Bash installation."
else
  install_ohmybash
fi

# ===================================================================
# Per-user configuration
# ===================================================================
mapfile -t _OMB_USERS < <(users__resolve_list)
for _username in "${_OMB_USERS[@]}"; do
  if ! id "$_username" > /dev/null 2>&1; then
    logging__warn "User '${_username}' does not exist — skipping."
    continue
  fi
  _configure_user_ohmybash "$_username"
done
