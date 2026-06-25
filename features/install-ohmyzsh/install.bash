# shellcheck shell=bash

# ---------------------------------------------------------------------------
# _clone_custom_dir — Print the physical directory used for theme/plugin clones.
# User-relative CUSTOM_DIR (~/... or $HOME/...) is not used directly for clones;
# those always land under ${_RESOLVED_PREFIX}/custom so they are shared across users.
# ---------------------------------------------------------------------------
_clone_custom_dir() {
  # shellcheck disable=SC2016
  if [ -n "${CUSTOM_DIR:-}" ] &&
    [[ "${CUSTOM_DIR}" != '~'* ]] &&
    [[ "${CUSTOM_DIR}" != '$HOME'* ]]; then
    printf '%s' "${CUSTOM_DIR}"
  else
    printf '%s' "${_RESOLVED_PREFIX}/custom"
  fi
}

# ---------------------------------------------------------------------------
# __install_run_git_clone_post — OMZ-specific scaffolding after the clone.
# Sets up the custom directory structure and clones any theme/plugin repos.
# Theme and plugin values accept either a full git URI (https://...) or a
# GitHub owner/repo slug (which gets https://github.com/ prepended).
# ---------------------------------------------------------------------------
__install_run_git_clone_post() {
  local _custom_dir
  _custom_dir="$(_clone_custom_dir)"
  file__mkdir "${_custom_dir}/themes" "${_custom_dir}/plugins"

  if [ -n "${THEME:-}" ]; then
    if [[ "${THEME}" != */* && "${THEME}" != *://* ]]; then
      logging__info "'${THEME}' is a built-in theme — skipping clone."
    else
      local _theme_uri
      [[ "${THEME}" == *://* ]] && _theme_uri="${THEME}" ||
        _theme_uri="https://github.com/${THEME}"
      git__clone --url "${_theme_uri}" --dir "${_custom_dir}/themes/$(basename "${THEME}")"
      logging__info "Installed custom theme '${THEME}'."
    fi
  fi

  local _slug
  for _slug in "${PLUGINS[@]+"${PLUGINS[@]}"}"; do
    _slug="${_slug// /}"
    [ -z "${_slug}" ] && continue
    if [[ "${_slug}" != */* && "${_slug}" != *://* ]]; then
      logging__info "'${_slug}' is a built-in plugin — skipping clone."
      continue
    fi
    local _plugin_uri
    [[ "${_slug}" == *://* ]] && _plugin_uri="${_slug}" ||
      _plugin_uri="https://github.com/${_slug}"
    git__clone --url "${_plugin_uri}" --dir "${_custom_dir}/plugins/$(basename "${_slug%/}")"
    logging__info "Installed custom plugin '${_slug}'."
  done
  logging__success "Oh My Zsh repository scaffolding complete."
}

# ---------------------------------------------------------------------------
# __uninstall_finish_post — Strip OMZ config blocks from all users' rc files.
# ---------------------------------------------------------------------------
__uninstall_finish_post() {
  local -a _users=()
  mapfile -t _users < <(users__resolve_list)
  local _user
  for _user in "${_users[@]+"${_users[@]}"}"; do
    users__uid_of_user "${_user}" > /dev/null 2>&1 || continue
    local _home
    _home="$(users__resolve_home "${_user}")"
    local _zdotdir
    _zdotdir="$(shell__detect_zdotdir --user "${_user}" --home "${_home}")"
    local _candidates
    _candidates="${_home}/.zshrc"$'\n'"${_zdotdir}/zshtheme"
    # Only add ${_zdotdir}/.zshrc when ZDOTDIR differs from HOME; when they are the same
    # ${_home}/.zshrc is already listed and processing it twice would run awk twice on the
    # same already-modified file.
    [[ "${_zdotdir}" != "${_home}" ]] && _candidates+=$'\n'"${_zdotdir}/.zshrc"
    shell__sync_block --files "${_candidates}" --marker "install-ohmyzsh"
    shell__sync_block --files "${_candidates}" --marker "install-ohmyzsh-source"
  done
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
  file__mkdir "${_dest}/themes" "${_dest}/plugins"

  local -a _items=()
  if [ -n "$_theme_slug" ]; then
    [[ "$_theme_slug" == */* || "$_theme_slug" == *://* ]] &&
      _items+=("themes/$(basename "$_theme_slug")")
  fi
  local _slug
  for _slug in "$@"; do
    _slug="${_slug// /}"
    [ -z "$_slug" ] && continue
    [[ "$_slug" != */* && "$_slug" != *://* ]] && continue # built-in plugin, no clone
    _items+=("plugins/$(basename "$_slug")")
  done

  local _item _src_path _dest_path
  for _item in "${_items[@]}"; do
    _src_path="${_src}/${_item}"
    _dest_path="${_dest}/${_item}"
    [ -d "$_src_path" ] || continue # not cloned, skip
    if [[ "$_mode" == "overwrite" ]]; then
      [ -L "$_dest_path" ] && rm "$_dest_path"
      [ ! -e "$_dest_path" ] && file__ln -sf "$_src_path" "$_dest_path"
    else
      [ ! -e "$_dest_path" ] && file__ln -sf "$_src_path" "$_dest_path"
    fi
  done
}

# ---------------------------------------------------------------------------
# __configure_user <username>
# Injects a guarded OMZ setup block into the user's Zsh theme file.
# Rcfile resolution is delegated to shell__resolve_zsh_theme_file (see lib/shell.sh):
# always targets $ZDOTDIR/zshtheme, creating it with a source line in
# $ZDOTDIR/.zshrc when absent.  The ZDOTDIR option overrides auto-detection.
# ---------------------------------------------------------------------------
__configure_user() {
  local _username="$1"
  local _home
  _home="$(users__resolve_home "$_username")"
  local _group
  _group="$(users__primary_group_of "$_username" 2> /dev/null || echo "$_username")"

  logging__info "Configuring Oh My Zsh for user '${_username}' (home: ${_home})..."

  # Resolve the zsh theme file for this user. shell__resolve_zsh_theme_file
  # detects ZDOTDIR (honouring the ZDOTDIR option when set), always targets
  # $ZDOTDIR/zshtheme, and injects a source line into .zshrc when the theme
  # file does not yet exist.
  local _zdotdir_arg=""
  [ -n "${ZDOTDIR:-}" ] && _zdotdir_arg="$(users__expand_path --user "$_username" "$ZDOTDIR")"
  local _rcfile
  if [ -n "${RCFILE:-}" ]; then
    _rcfile="$(users__expand_path --user "$_username" "$RCFILE")"
  else
    _rcfile="$(shell__resolve_zsh_theme_file "$_username" \
      ${_zdotdir_arg:+--zdotdir "$_zdotdir_arg"} \
      --source-marker "install-ohmyzsh-source")"
  fi
  local _rcdir
  _rcdir="$(dirname "$_rcfile")"

  local _custom_dir_raw="${CUSTOM_DIR:-}"
  [ -z "$_custom_dir_raw" ] && _custom_dir_raw="${_rcdir}/custom"
  local _effective_custom_dir
  _effective_custom_dir="$(users__expand_path --user "$_username" "$_custom_dir_raw")"

  local _is_per_user=false
  [[ "$_effective_custom_dir" == "${_home}"* ]] && _is_per_user=true

  local _is_p10k=false
  [[ "$THEME" == *powerlevel10k* ]] && _is_p10k=true

  local _theme_value=""
  if [ -n "$THEME" ]; then
    _theme_value="$(shell__resolve_omz_theme \
      --theme_slug "$THEME" \
      --custom_dir "$(_clone_custom_dir)")"
  fi

  local _plugin_names=""
  if ((${#PLUGINS[@]})); then
    _plugin_names="$(str__basename_each "${PLUGINS[@]}" | tr '\n' ' ')"
    _plugin_names="${_plugin_names% }"
  fi

  local _content
  _content="export ZSH=\"${_RESOLVED_PREFIX}\""$'\n'
  _content+="ZSH_CACHE_DIR=\"${ZSH_CACHE_DIR}\""$'\n'
  # shellcheck disable=SC2016
  _content+='[ -d "$ZSH_CACHE_DIR" ] || mkdir -p "$ZSH_CACHE_DIR"'$'\n'
  _content+="ZSH_COMPDUMP=\"${ZSH_COMPDUMP}\""$'\n'
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

  _content+="zstyle ':omz:update' mode ${UPDATE_MODE}"$'\n'

  if [[ "$_is_p10k" == true ]]; then
    _content+='POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true'$'\n'
  fi

  # shellcheck disable=SC2016
  _content+='[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"'$'\n'

  if [[ "$_is_p10k" == true ]]; then
    # shellcheck disable=SC2016
    _content+='[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"'$'\n'
  fi

  file__mkdir "$_rcdir"
  shell__write_block --file "$_rcfile" --marker "install-ohmyzsh" --content "$_content"

  # Derive symlink/copy mode from if_exists: update → augment; all others → overwrite.
  if [[ "$_is_per_user" == true ]]; then
    local _link_mode
    case "${IF_EXISTS:-}" in
      update) _link_mode="augment" ;;
      *) _link_mode="overwrite" ;;
    esac
    _link_custom_items \
      "${_RESOLVED_PREFIX}/custom" \
      "$_effective_custom_dir" \
      "$THEME" \
      "${_link_mode}" \
      "${PLUGINS[@]}"
  fi

  local _p10k_skel="${_FEAT_FILES_DIR}/skel/p10k.zsh"
  if [[ "$_is_p10k" == true ]] && [ -f "$_p10k_skel" ]; then
    case "${IF_EXISTS:-}" in
      update) [ ! -f "${_home}/.p10k.zsh" ] && file__cp "$_p10k_skel" "${_home}/.p10k.zsh" ;;
      *) file__cp -f "$_p10k_skel" "${_home}/.p10k.zsh" ;;
    esac
  fi

  file__chown -R "${_username}:${_group}" "$_home"
  logging__success "User '${_username}' Oh My Zsh configuration complete."
}
