_GITHUB_BASE_URL="https://github.com"
_ZSH_COMPLETIONS_REPO_URL="${_GITHUB_BASE_URL}/${ZSH_COMPLETIONS_GH_REPO}"
# Shallow-clone the repo here when not using Homebrew. Completion functions live
# under src/ (see upstream README). Debian/Ubuntu .deb builds exist via OBS,
# but default apt archives do not ship this package.
_ZSH_COMPLETIONS_PREFIX="/usr/local/share/zsh-completions"
_ZSH_COMPLETIONS_SRC="${_ZSH_COMPLETIONS_PREFIX}/src"
_OHMYZSH_REPO_URL="${_GITHUB_BASE_URL}/${OHMYZSH_GH_REPO}"
_OHMYBASH_REPO_URL="${_GITHUB_BASE_URL}/${OHMYBASH_GH_REPO}"
_STARSHIP_INSTALLER_URL="https://starship.rs/install.sh"

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

# ---------------------------------------------------------------------------
# install_fzf — Download fzf from GitHub Releases, verify checksum, install.
# Uses: FZF_PREFIX.
# ---------------------------------------------------------------------------
install_fzf() {
  local _bin_dir="${FZF_PREFIX}/bin"

  if [ -x "${_bin_dir}/fzf" ]; then
    logging__info "fzf already installed at '${_bin_dir}/fzf' — skipping."
    return 0
  fi

  local _out _version
  _out="$(github__resolve_version "${FZF_GH_REPO}" "")" || {
    logging__error "Failed to resolve fzf version from GitHub."
    return 1
  }
  _version="${_out#*$'\n'}"
  logging__info "Installing fzf ${_version} to '${_bin_dir}'..."

  local _os _fzf_arch
  _os="$(os__release_kernel)" || {
    logging__error "Unsupported kernel for fzf install: '$(os__kernel)'"
    return 1
  }
  _fzf_arch="$(os__release_arch)" || {
    logging__error "Unsupported arch for fzf install: '$(os__arch)'"
    return 1
  }
  case "$_fzf_arch" in
    amd64 | arm64) ;;
    *)
      logging__error "Unsupported arch for fzf install: '$(os__arch)'"
      return 1
      ;;
  esac

  local _filename="fzf-${_version}-${_os}_${_fzf_arch}.tar.gz"
  local _base_url="${_GITHUB_BASE_URL}/${FZF_GH_REPO}/releases/download/v${_version}"

  github__install_release \
    --repo "${FZF_GH_REPO}" --tag "v${_version}" \
    --asset "$_filename" --binary-src fzf --binary-dest "${_bin_dir}/" \
    --sidecar "${_base_url}/fzf_${_version}_checksums.txt" \
    --installer-dir "${INSTALLER_DIR}" ||
    return 1

  logging__success "fzf installed to '${_bin_dir}/fzf'."
  return 0
}

# ---------------------------------------------------------------------------
# install_zsh_completions — Extra Zsh completion definitions (zsh-users project).
# Uses Homebrew when that is the active package manager; otherwise shallow-clones
# into ${_ZSH_COMPLETIONS_PREFIX} (no apt/deb package exists for this tree).
# ---------------------------------------------------------------------------
install_zsh_completions() {
  if ospkg__os_release_match pm brew; then
    ospkg__install_user zsh-completions
    return 0
  fi

  logging__info "Installing zsh-completions (git) → '${_ZSH_COMPLETIONS_PREFIX}'..."
  local _prev_umask
  _prev_umask="$(umask)"
  umask g-w,o-w
  git__clone --url "$_ZSH_COMPLETIONS_REPO_URL" --dir "$_ZSH_COMPLETIONS_PREFIX"
  umask "$_prev_umask"
  logging__success "zsh-completions ready (fpath: '${_ZSH_COMPLETIONS_SRC}')."
  return 0
}

# ---------------------------------------------------------------------------
# install_starship — Download and run the official Starship installer.
# ---------------------------------------------------------------------------
install_starship() {
  local _bin_dir="${STARSHIP_PREFIX}/bin"

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
  return 0
}

# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# configure_user <username>
# Set up per-user shell configuration files.
# Reads OMZ, OMB, Starship, and other settings from outer-scope variables.
# ---------------------------------------------------------------------------
configure_user() {
  local _cu_username="$1"
  # STARSHIP_SHELLS: keep space-joined for *zsh* / *bash* substring checks below.
  local _cu_starship_shells="${STARSHIP_SHELLS[*]}"
  local _cu_bin_dir="${STARSHIP_PREFIX}/bin"

  # Resolve user's home directory and group.
  local _cu_home
  _cu_home="$(users__resolve_home "$_cu_username")"
  local _cu_group
  _cu_group="$(users__primary_group_of "$_cu_username" 2> /dev/null || echo "$_cu_username")"

  if [ ! -d "$_cu_home" ]; then
    logging__warn "Home directory '${_cu_home}' does not exist for user '${_cu_username}' — creating."
    file__mkdir "$_cu_home"
    file__chown "${_cu_username}:${_cu_group}" "$_cu_home"
  fi

  logging__info "Configuring user '${_cu_username}' (home: ${_cu_home}, mode: ${USER_CONFIG_MODE})..."

  # Resolve per-user XDG and Zsh config paths.
  local _cu_xdg_config_home="${_cu_home}/.config"
  # Expand ZDOTDIR option (may be ~-prefixed, $HOME-prefixed, or absolute).
  local _cu_zdotdir
  # shellcheck disable=SC2016
  if [ -z "${ZDOTDIR-}" ]; then
    _cu_zdotdir="${_cu_xdg_config_home}/zsh"
  elif [[ "$ZDOTDIR" == '~'* ]]; then
    _cu_zdotdir="${_cu_home}${ZDOTDIR#\~}"
  elif [[ "$ZDOTDIR" == '$HOME'* ]]; then
    _cu_zdotdir="${_cu_home}${ZDOTDIR#'$HOME'}"
  else
    _cu_zdotdir="$ZDOTDIR"
  fi

  # Apply defaults for custom dirs if not explicitly provided.
  local _cu_omz_custom_dir="${OHMYZSH_CUSTOM_DIR:-}"
  [ -z "$_cu_omz_custom_dir" ] && _cu_omz_custom_dir="${_cu_zdotdir}/custom"
  local _cu_omb_custom_dir="${OHMYBASH_CUSTOM_DIR:-}"
  [ -z "$_cu_omb_custom_dir" ] && _cu_omb_custom_dir="${_cu_xdg_config_home}/bash/custom"

  # Mode: skip — bail out if any dotfile already exists.
  if [[ "$USER_CONFIG_MODE" == "skip" ]]; then
    if [ -f "${_cu_zdotdir}/.zshrc" ] || [ -f "${_cu_home}/.bashrc" ]; then
      logging__info "User '${_cu_username}' already has dotfiles — skipping (mode=skip)."
      return 0
    fi
  fi

  # Copy skeleton files.
  if [ -n "$_SKEL_DIR" ] && [ -d "$_SKEL_DIR" ]; then
    local _cu_skel_file _cu_rel _cu_dest
    while IFS= read -r -d '' _cu_skel_file; do
      _cu_rel="${_cu_skel_file#"${_SKEL_DIR}"/}"
      [[ "$_cu_rel" == "p10k.zsh" ]] && continue
      # .zshenv always lives in HOME so zsh finds it before ZDOTDIR is set.
      # All other zsh config files go into ZDOTDIR.
      case "$_cu_rel" in
        .zshenv) _cu_dest="${_cu_home}/${_cu_rel}" ;;
        .zshrc | .zprofile | .zlogin) _cu_dest="${_cu_zdotdir}/${_cu_rel}" ;;
        *) _cu_dest="${_cu_home}/${_cu_rel}" ;;
      esac
      case "$USER_CONFIG_MODE" in
        overwrite)
          mkdir -p "$(dirname "$_cu_dest")"
          cp -f "$_cu_skel_file" "$_cu_dest"
          ;;
        augment)
          if [ ! -f "$_cu_dest" ]; then
            mkdir -p "$(dirname "$_cu_dest")"
            cp "$_cu_skel_file" "$_cu_dest"
          fi
          ;;
      esac
    done < <(find "$_SKEL_DIR" -maxdepth 1 -type f -print0)
  fi

  # Inject ZDOTDIR into ~/.zshenv.
  local _cu_zshenv="${_cu_home}/.zshenv"
  mkdir -p "$_cu_zdotdir"
  shell__write_block --file "$_cu_zshenv" --marker "install-shell-zdotdir" --content "ZDOTDIR=\"${_cu_zdotdir}\""

  # ---------------------------------------------------------------------------
  # Zsh theme file ($ZDOTDIR/zshtheme)
  # ---------------------------------------------------------------------------
  local _cu_zshtheme="${_cu_zdotdir}/zshtheme"
  local _cu_zshtheme_content=""

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

  # Append direnv hook for zsh.
  if [[ "$INSTALL_DIRENV" == true ]]; then
    # shellcheck disable=SC2016
    _cu_zshtheme_content+='command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"'$'\n'
  fi

  # Append fzf key-bindings and completion for zsh.
  if [[ "$INSTALL_FZF" == true ]]; then
    # shellcheck disable=SC2016
    _cu_zshtheme_content+='command -v fzf >/dev/null 2>&1 && eval "$(fzf --zsh)"'$'\n'
  fi

  # Append Starship integration for zsh.
  if [[ "$_cu_starship_shells" == *zsh* ]]; then
    if ! command -v starship > /dev/null 2>&1 && [ ! -x "${_cu_bin_dir}/starship" ]; then
      logging__warn "starship_shells includes 'zsh' but starship is not on PATH — integration injected anyway."
    fi
    # shellcheck disable=SC2016
    _cu_zshtheme_content+='command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"'$'\n'
  fi

  # Write zshtheme file.
  if [ -n "$_cu_zshtheme_content" ]; then
    mkdir -p "$_cu_zdotdir"
    case "$USER_CONFIG_MODE" in
      overwrite)
        printf '%s' "$_cu_zshtheme_content" > "$_cu_zshtheme"
        logging__info "Written zsh theme file '${_cu_zshtheme}'."
        ;;
      augment)
        if [ ! -f "$_cu_zshtheme" ]; then
          printf '%s' "$_cu_zshtheme_content" > "$_cu_zshtheme"
          logging__info "Written zsh theme file '${_cu_zshtheme}'."
        fi
        ;;
    esac
  fi

  # ---------------------------------------------------------------------------
  # Bash theme file (~/.config/bash/bashtheme)
  # ---------------------------------------------------------------------------
  local _cu_bashtheme="${_cu_xdg_config_home}/bash/bashtheme"
  local _cu_bashtheme_content=""

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

  # Append direnv hook for bash.
  if [[ "$INSTALL_DIRENV" == true ]]; then
    # shellcheck disable=SC2016
    _cu_bashtheme_content+='command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"'$'\n'
  fi

  # Append fzf key-bindings and completion for bash.
  if [[ "$INSTALL_FZF" == true ]]; then
    # shellcheck disable=SC2016
    _cu_bashtheme_content+='command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"'$'\n'
  fi

  # Append Starship integration for bash.
  if [[ "$_cu_starship_shells" == *bash* ]]; then
    if ! command -v starship > /dev/null 2>&1 && [ ! -x "${_cu_bin_dir}/starship" ]; then
      logging__warn "starship_shells includes 'bash' but starship is not on PATH — integration injected anyway."
    fi
    # shellcheck disable=SC2016
    _cu_bashtheme_content+='command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"'$'\n'
  fi

  # Write bashtheme file.
  if [ -n "$_cu_bashtheme_content" ]; then
    mkdir -p "${_cu_xdg_config_home}/bash"
    case "$USER_CONFIG_MODE" in
      overwrite)
        printf '%s' "$_cu_bashtheme_content" > "$_cu_bashtheme"
        logging__info "Written bash theme file '${_cu_bashtheme}'."
        ;;
      augment)
        if [ ! -f "$_cu_bashtheme" ]; then
          printf '%s' "$_cu_bashtheme_content" > "$_cu_bashtheme"
          logging__info "Written bash theme file '${_cu_bashtheme}'."
        fi
        ;;
    esac
  fi

  # Fix ownership — give the user full ownership of their entire home directory.
  file__chown -R "${_cu_username}:${_cu_group}" "$_cu_home"

  logging__success "User '${_cu_username}' configuration complete."
  return 0
}

_SKEL_DIR="${_FILES_DIR}/skel"

if [[ "$INSTALL_ZSH" == true ]]; then
  if command -v zsh > /dev/null 2>&1; then
    logging__info "Zsh already installed — skipping."
  else
    logging__install "Installing Zsh..."
    ospkg__install_user zsh
  fi
fi

# Verify prerequisites are available.
if ! command -v git > /dev/null 2>&1; then
  logging__error "Required command 'git' not found. Install it first."
  exit 1
fi

# ===================================================================
# Step 2.5: Install shell tool integrations
# ===================================================================
if [[ "$INSTALL_BASH_COMPLETION" == true ]]; then
  logging__install "Installing bash-completion..."
  ospkg__run --manifest $'packages:\n  - name: bash-completion\n    brew: bash-completion@2'
fi

if [[ "$INSTALL_ZSH_COMPLETIONS" == true ]] && command -v zsh > /dev/null 2>&1; then
  logging__install "Installing zsh-completions..."
  install_zsh_completions
fi

if [[ "$INSTALL_DIRENV" == true ]]; then
  logging__install "Installing direnv..."
  ospkg__install_user direnv
fi

if [[ "$INSTALL_FZF" == true ]]; then
  install_fzf
fi

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

# ===================================================================
# Step 3: Install Oh My Bash
# ===================================================================
_OMB_INSTALLED=false
if [[ "$INSTALL_OHMYBASH" == true ]]; then
  install_ohmybash
  _OMB_INSTALLED=true
fi

# ===================================================================
# Step 4: Install Starship
# ===================================================================
if [[ "$INSTALL_STARSHIP" == true ]]; then
  install_starship
fi

# ===================================================================
# Step 5: Deploy system-wide shell configuration files
# ===================================================================
# install-shell has no single PREFIX; step 5 always targets /etc/ paths.
# file__ helpers escalate privileges automatically as needed.
logging__info "Deploying system-wide shell configuration files..."

# --- Shared (shell-agnostic) files ---
for _name in shellenv shellrc shellaliases; do
  _src="${_FILES_DIR}/shell/${_name}"
  _dest="/etc/${_name}"
  if [ -f "$_src" ]; then
    file__cp -f "$_src" "$_dest"
    file__chmod 644 "$_dest"
    logging__success "  ${_dest}"
  fi
done

# --- /etc/profile ---
_src="${_FILES_DIR}/profile"
if [ -f "$_src" ]; then
  file__cp -f "$_src" "/etc/profile"
  file__chmod 644 "/etc/profile"
  logging__success "  /etc/profile"
fi

# --- Bash system-wide bashrc ---
_SYS_BASHRC="$(shell__detect_bashrc)"
_src="${_FILES_DIR}/bash/bashrc"
if [ -f "$_src" ]; then
  file__mkdir "$(dirname "$_SYS_BASHRC")"
  file__cp -f "$_src" "$_SYS_BASHRC"
  file__chmod 644 "$_SYS_BASHRC"
  logging__success "  ${_SYS_BASHRC}"
fi

# --- Bash bashenv (if present in files/) ---
_src="${_FILES_DIR}/bash/bashenv"
if [ -f "$_src" ]; then
  # Place bashenv next to bashrc: /etc/bash/bashenv, /etc/bashenv, etc.
  _bashenv_dest="$(dirname "$_SYS_BASHRC")/bashenv"
  # If bashrc is at /etc/bashrc or /etc/bash.bashrc, put bashenv at /etc/bashenv.
  [[ "$_SYS_BASHRC" == "/etc/bash.bashrc" ]] && _bashenv_dest="/etc/bashenv"
  [[ "$_SYS_BASHRC" == "/etc/bashrc" ]] && _bashenv_dest="/etc/bashenv"
  file__cp -f "$_src" "$_bashenv_dest"
  file__chmod 644 "$_bashenv_dest"
  logging__success "  ${_bashenv_dest}"

  # Ensure BASH_ENV is set system-wide so non-interactive non-login bash
  # sessions (VS Code tasks, devcontainer exec, CI runners) source it.
  if ! grep -qxF "BASH_ENV=${_bashenv_dest}" /etc/environment 2> /dev/null; then
    # Remove any stale BASH_ENV line first, then append the correct one.
    users__run_privileged sed -i '/^BASH_ENV=/d' /etc/environment 2> /dev/null || true
    printf 'BASH_ENV=%s\n' "${_bashenv_dest}" | file__tee --append /etc/environment
    logging__success "  BASH_ENV=${_bashenv_dest} → /etc/environment"
  fi
fi

# --- Zsh system-wide files ---
if command -v zsh > /dev/null 2>&1; then
  _ZSH_ETC="$(shell__detect_zshdir)"
  file__mkdir "$_ZSH_ETC"

  for _name in zshenv zprofile zshrc; do
    _src="${_FILES_DIR}/zsh/${_name}"
    _dest="${_ZSH_ETC}/${_name}"
    if [ -f "$_src" ]; then
      file__cp -f "$_src" "$_dest"
      file__chmod 644 "$_dest"
      logging__success "  ${_dest}"
    fi
  done

  # ===================================================================
  # Step 5.5: Wire zsh-completions fpath
  # ===================================================================
  # Homebrew uses share/zsh-completions. Git installs use the repo's src/
  # directory (same layout as upstream manual install and OBS packages).
  if [[ "$INSTALL_ZSH_COMPLETIONS" == true ]]; then
    _zshrc_dest="${_ZSH_ETC}/zshrc"
    if [ -f "$_zshrc_dest" ]; then
      _zsh_comp_fpath=""
      _brew_zc="$(brew --prefix zsh-completions 2> /dev/null)" || true
      if [ -n "$_brew_zc" ] && [ -d "${_brew_zc}/share/zsh-completions" ]; then
        _zsh_comp_fpath="${_brew_zc}/share/zsh-completions"
      elif [ -d "$_ZSH_COMPLETIONS_SRC" ]; then
        _zsh_comp_fpath="$_ZSH_COMPLETIONS_SRC"
      fi
      if [ -n "$_zsh_comp_fpath" ]; then
        shell__write_block \
          --file "$_zshrc_dest" \
          --marker "install-shell-pre-compinit" \
          --content "fpath=( '${_zsh_comp_fpath}' \${fpath[@]} )"
        logging__success "  zsh-completions fpath → ${_zshrc_dest}"
      fi
    fi
  fi
fi

# ===================================================================
# Step 6: Resolve user list
# ===================================================================
mapfile -t _RESOLVED_USERS < <(
  _uargs=()
  [ "${ADD_CURRENT_USER:-true}" != "true" ] && _uargs+=(--current false)
  [ "${ADD_REMOTE_USER:-true}" != "true" ] && _uargs+=(--remote false)
  [ "${ADD_CONTAINER_USER:-true}" != "true" ] && _uargs+=(--container false)
  for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do [ -n "$_u" ] && _uargs+=(--user "$_u"); done
  users__resolve_list "${_uargs[@]}"
)

if [ ${#_RESOLVED_USERS[@]} -eq 0 ]; then
  logging__info "No users to configure."
else
  logging__info "Users to configure: ${_RESOLVED_USERS[*]}"
fi

# ===================================================================
# Step 7: Per-user configuration
# ===================================================================
for _username in "${_RESOLVED_USERS[@]}"; do
  # Verify the user exists.
  if ! id "$_username" > /dev/null 2>&1; then
    logging__warn "User '${_username}' does not exist — skipping."
    continue
  fi

  configure_user "$_username"
done

# ===================================================================
# Step 8: Set default shells
# ===================================================================
if [[ "$SET_USER_SHELLS" != "none" ]] && [ ${#_RESOLVED_USERS[@]} -gt 0 ]; then
  _TARGET_SHELL=""
  case "$SET_USER_SHELLS" in
    zsh)
      _TARGET_SHELL="$(command -v zsh 2> /dev/null || true)"
      if [ -z "$_TARGET_SHELL" ]; then
        logging__error "set_user_shells=zsh but zsh is not installed."
        exit 1
      fi
      ;;
    bash)
      _TARGET_SHELL="$(command -v bash 2> /dev/null || true)"
      if [ -z "$_TARGET_SHELL" ]; then
        logging__error "set_user_shells=bash but bash is not installed."
        exit 1
      fi
      ;;
    *)
      logging__error "Invalid set_user_shells value: '${SET_USER_SHELLS}' (expected: zsh, bash, none)."
      exit 1
      ;;
  esac

  users__set_login_shell "$_TARGET_SHELL" "${_RESOLVED_USERS[@]}"
fi
