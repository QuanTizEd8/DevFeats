# Phase 1 skeleton — mechanically extracted from install-shell/install.bash
# Feature: install-ohmyzsh
# Not yet functional. Wired up in this feature's own semantic phase.
# shellcheck shell=bash

# --- _OHMYZSH_REPO_URL global var (original lines 8–8) ---
_OHMYZSH_REPO_URL="${_GITHUB_BASE_URL}/${OHMYZSH_GH_REPO}"

# --- install_ohmyzsh() + blank (original lines 12–70) ---
# ---------------------------------------------------------------------------
# install_ohmyzsh — Clone OMZ, scaffold ZSH_CUSTOM, clone custom theme/plugins.
# Uses: OHMYZSH_INSTALL_DIR, OHMYZSH_BRANCH, OHMYZSH_THEME, OHMYZSH_CUSTOM_DIR,
#       OHMYZSH_PLUGINS (array).
# ---------------------------------------------------------------------------
install_ohmyzsh() {
  local _install_dir="$OHMYZSH_INSTALL_DIR"
  local _branch="$OHMYZSH_BRANCH"
  local _theme="$OHMYZSH_THEME"
  # Use an explicit system-path custom dir if given; per-user paths (~/$HOME-prefixed)
  # and the empty default are handled at configure-user time via symlinks.
  local _custom_dir
  # shellcheck disable=SC2016
  if [ -n "$OHMYZSH_CUSTOM_DIR" ] &&
    [[ "$OHMYZSH_CUSTOM_DIR" != '~'* ]] &&
    [[ "$OHMYZSH_CUSTOM_DIR" != '$HOME'* ]]; then
    _custom_dir="$OHMYZSH_CUSTOM_DIR"
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
  for _slug in "${OHMYZSH_PLUGINS[@]}"; do
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
  return 0
}

# --- _resolve_custom_dir() and _link_custom_items() helpers + blanks (original lines 226–277) ---
# _resolve_custom_dir <raw_value> <user_home>
# Expands ~- and $HOME-prefixed paths to absolute paths for the given user.
# Absolute paths and other values are passed through unchanged.
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

# --- Step 2: Install Oh My Zsh + blank (original lines 663–675) ---
# ===================================================================
# Step 2: Install Oh My Zsh
# ===================================================================
_OMZ_INSTALLED=false
if [[ "$INSTALL_OHMYZSH" == true ]]; then
  if ! command -v zsh > /dev/null 2>&1; then
    logging__warn "Zsh not available — skipping Oh My Zsh installation."
  else
    install_ohmyzsh
    _OMZ_INSTALLED=true
  fi
fi

# --- configure_user preamble: vars used by the OMZ block (from configure_user()) ---
# STARSHIP_SHELLS: keep space-joined for *zsh* substring check below.
local _cu_starship_shells="${STARSHIP_SHELLS[*]}"
local _cu_omz_custom_dir="${OHMYZSH_CUSTOM_DIR:-}"
[ -z "$_cu_omz_custom_dir" ] && _cu_omz_custom_dir="${_cu_zdotdir}/custom"
local _cu_zshtheme_content=""

# --- configure_user: OMZ zsh block + trailing blank (original lines 371–461) ---
if [[ "$_OMZ_INSTALLED" == true ]]; then
  local _cu_omz_effective_custom_dir
  _cu_omz_effective_custom_dir="$(_resolve_custom_dir "$_cu_omz_custom_dir" "$_cu_home")"
  local _cu_omz_is_per_user=false
  [[ "$_cu_omz_effective_custom_dir" == "$_cu_home"* ]] && _cu_omz_is_per_user=true

  local _cu_omz_theme_value=""
  if [ -n "$OHMYZSH_THEME" ]; then
    _cu_omz_theme_value="$(shell__resolve_omz_theme \
      --theme_slug "$OHMYZSH_THEME" \
      --custom_dir "${OHMYZSH_INSTALL_DIR}/custom")"
  fi

  local _cu_omz_plugin_names=""
  if ((${#OHMYZSH_PLUGINS[@]})); then
    _cu_omz_plugin_names="$(str__basename_each "${OHMYZSH_PLUGINS[@]}" | tr '\n' ' ')"
    _cu_omz_plugin_names="${_cu_omz_plugin_names% }"
  fi

  local _cu_is_p10k=false
  [[ "$OHMYZSH_THEME" == *powerlevel10k* ]] && _cu_is_p10k=true

  local _cu_zsh_use_starship=false
  if [[ "$_cu_starship_shells" == *zsh* ]]; then
    _cu_zsh_use_starship=true
    if [ -n "$OHMYZSH_THEME" ]; then
      logging__warn "ohmyzsh_theme='${OHMYZSH_THEME}' is set but starship_shells includes 'zsh' — theme ignored, Starship will own the prompt."
    fi
  fi

  # shellcheck disable=SC2016
  _cu_zshtheme_content+="export ZSH=\"${OHMYZSH_INSTALL_DIR}\""$'\n'
  # shellcheck disable=SC2016
  _cu_zshtheme_content+='ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"'$'\n'
  # shellcheck disable=SC2016
  _cu_zshtheme_content+='[ -d "$ZSH_CACHE_DIR" ] || mkdir -p "$ZSH_CACHE_DIR"'$'\n'
  # shellcheck disable=SC2016
  _cu_zshtheme_content+='ZSH_COMPDUMP="${ZSH_CACHE_DIR}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"'$'\n'
  _cu_zshtheme_content+="ZSH_CUSTOM=\"${_cu_omz_effective_custom_dir}\""$'\n'

  if [[ "$_cu_zsh_use_starship" == true ]]; then
    _cu_zshtheme_content+='ZSH_THEME=""'$'\n'
  elif [ -n "$_cu_omz_theme_value" ]; then
    _cu_zshtheme_content+="ZSH_THEME=\"${_cu_omz_theme_value}\""$'\n'
  else
    _cu_zshtheme_content+='ZSH_THEME=""'$'\n'
  fi

  if [ -n "$_cu_omz_plugin_names" ]; then
    _cu_zshtheme_content+="plugins=(${_cu_omz_plugin_names})"$'\n'
  else
    _cu_zshtheme_content+='plugins=()'$'\n'
  fi

  _cu_zshtheme_content+="zstyle ':omz:update' mode disabled"$'\n'

  if [[ "$_cu_is_p10k" == true ]] && [[ "$_cu_zsh_use_starship" != true ]]; then
    _cu_zshtheme_content+='POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true'$'\n'
  fi

  # shellcheck disable=SC2016
  _cu_zshtheme_content+='[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"'$'\n'

  if [[ "$_cu_is_p10k" == true ]] && [[ "$_cu_zsh_use_starship" != true ]]; then
    # shellcheck disable=SC2016
    _cu_zshtheme_content+='[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"'$'\n'
  fi

  mkdir -p "${_cu_omz_effective_custom_dir}/themes" "${_cu_omz_effective_custom_dir}/plugins"
  if [[ "$_cu_omz_is_per_user" == true ]]; then
    _link_custom_items \
      "${OHMYZSH_INSTALL_DIR}/custom" \
      "$_cu_omz_effective_custom_dir" \
      "$OHMYZSH_THEME" \
      "$USER_CONFIG_MODE" \
      "${OHMYZSH_PLUGINS[@]}"
  fi

  if [[ "$_cu_is_p10k" == true ]] && [[ "$_cu_zsh_use_starship" != true ]] &&
    [ -n "$_SKEL_DIR" ] && [ -f "${_SKEL_DIR}/p10k.zsh" ]; then
    case "$USER_CONFIG_MODE" in
      overwrite)
        cp -f "${_SKEL_DIR}/p10k.zsh" "${_cu_home}/.p10k.zsh"
        ;;
      augment)
        [ ! -f "${_cu_home}/.p10k.zsh" ] && cp "${_SKEL_DIR}/p10k.zsh" "${_cu_home}/.p10k.zsh"
        ;;
    esac
  fi
fi
