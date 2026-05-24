# Phase 1 skeleton — mechanically extracted from install-shell/install.bash
# Feature: install-ohmybash
# Not yet functional. Wired up in this feature's own semantic phase.
# shellcheck shell=bash

# --- _OHMYBASH_REPO_URL global var (original lines 9–9) ---
_OHMYBASH_REPO_URL="${_GITHUB_BASE_URL}/${OHMYBASH_GH_REPO}"

# --- install_ohmybash() + blank (original lines 71–127) ---
# ---------------------------------------------------------------------------
# install_ohmybash — Clone OMB, scaffold OSH_CUSTOM, clone custom theme/plugins.
# Uses: OHMYBASH_INSTALL_DIR, OHMYBASH_BRANCH, OHMYBASH_THEME, OHMYBASH_CUSTOM_DIR,
#       OHMYBASH_PLUGINS (array).
# ---------------------------------------------------------------------------
install_ohmybash() {
  local _install_dir="$OHMYBASH_INSTALL_DIR"
  local _branch="$OHMYBASH_BRANCH"
  local _theme="$OHMYBASH_THEME"
  local _custom_dir
  # shellcheck disable=SC2016
  if [ -n "$OHMYBASH_CUSTOM_DIR" ] &&
    [[ "$OHMYBASH_CUSTOM_DIR" != '~'* ]] &&
    [[ "$OHMYBASH_CUSTOM_DIR" != '$HOME'* ]]; then
    _custom_dir="$OHMYBASH_CUSTOM_DIR"
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
  for _slug in "${OHMYBASH_PLUGINS[@]}"; do
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
  return 0
}

# --- Step 3: Install Oh My Bash + blank (original lines 676–684) ---
# ===================================================================
# Step 3: Install Oh My Bash
# ===================================================================
_OMB_INSTALLED=false
if [[ "$INSTALL_OHMYBASH" == true ]]; then
  install_ohmybash
  _OMB_INSTALLED=true
fi

# --- configure_user: OMB bash block + trailing blank (original lines 519–578) ---
if [[ "$_OMB_INSTALLED" == true ]]; then
  local _cu_omb_effective_custom_dir
  _cu_omb_effective_custom_dir="$(_resolve_custom_dir "$_cu_omb_custom_dir" "$_cu_home")"
  local _cu_omb_is_per_user=false
  [[ "$_cu_omb_effective_custom_dir" == "$_cu_home"* ]] && _cu_omb_is_per_user=true

  local _cu_omb_theme_value=""
  if [ -n "$OHMYBASH_THEME" ]; then
    _cu_omb_theme_value="$(basename "$OHMYBASH_THEME")"
  fi

  local _cu_omb_plugin_names=""
  if ((${#OHMYBASH_PLUGINS[@]})); then
    _cu_omb_plugin_names="$(str__basename_each "${OHMYBASH_PLUGINS[@]}" | tr '\n' ' ')"
    _cu_omb_plugin_names="${_cu_omb_plugin_names% }"
  fi

  local _cu_bash_use_starship=false
  if [[ "$_cu_starship_shells" == *bash* ]]; then
    _cu_bash_use_starship=true
    if [ -n "$OHMYBASH_THEME" ]; then
      logging__warn "ohmybash_theme='${OHMYBASH_THEME}' is set but starship_shells includes 'bash' — theme ignored, Starship will own the prompt."
    fi
  fi

  _cu_bashtheme_content+="export OSH=\"${OHMYBASH_INSTALL_DIR}\""$'\n'
  # shellcheck disable=SC2016
  _cu_bashtheme_content+='OSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-bash"'$'\n'
  # shellcheck disable=SC2016
  _cu_bashtheme_content+='[ -d "$OSH_CACHE_DIR" ] || mkdir -p "$OSH_CACHE_DIR"'$'\n'
  _cu_bashtheme_content+="OSH_CUSTOM=\"${_cu_omb_effective_custom_dir}\""$'\n'

  if [[ "$_cu_bash_use_starship" == true ]]; then
    _cu_bashtheme_content+='OSH_THEME=""'$'\n'
  elif [ -n "$_cu_omb_theme_value" ]; then
    _cu_bashtheme_content+="OSH_THEME=\"${_cu_omb_theme_value}\""$'\n'
  else
    _cu_bashtheme_content+='OSH_THEME=""'$'\n'
  fi

  if [ -n "$_cu_omb_plugin_names" ]; then
    _cu_bashtheme_content+="plugins=(${_cu_omb_plugin_names})"$'\n'
  else
    _cu_bashtheme_content+='plugins=()'$'\n'
  fi

  # shellcheck disable=SC2016
  _cu_bashtheme_content+='[ -f "$OSH/oh-my-bash.sh" ] && source "$OSH/oh-my-bash.sh"'$'\n'

  mkdir -p "${_cu_omb_effective_custom_dir}/themes" "${_cu_omb_effective_custom_dir}/plugins"
  if [[ "$_cu_omb_is_per_user" == true ]]; then
    _link_custom_items \
      "${OHMYBASH_INSTALL_DIR}/custom" \
      "$_cu_omb_effective_custom_dir" \
      "$OHMYBASH_THEME" \
      "$USER_CONFIG_MODE" \
      "${OHMYBASH_PLUGINS[@]}"
  fi
fi
