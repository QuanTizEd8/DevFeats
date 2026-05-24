# ---------------------------------------------------------------------------
# configure_user <username>
# Set up per-user shell configuration files (skel copy, ZDOTDIR injection).
# ---------------------------------------------------------------------------
configure_user() {
  local _cu_username="$1"

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

  # Create empty per-user theme files if not already present.
  # Downstream features (install-ohmyzsh, install-starship, etc.) append guarded
  # blocks to these via shell__write_block(). The skel .zshrc/.bashrc source them
  # conditionally, so they must exist before the first interactive session.
  local _cu_zshtheme="${_cu_zdotdir}/zshtheme"
  [ -f "${_cu_zshtheme}" ] || touch "${_cu_zshtheme}"

  local _cu_bashdir="${_cu_xdg_config_home}/bash"
  mkdir -p "${_cu_bashdir}"
  local _cu_bashtheme="${_cu_bashdir}/bashtheme"
  [ -f "${_cu_bashtheme}" ] || touch "${_cu_bashtheme}"

  # Fix ownership — give the user full ownership of their entire home directory.
  file__chown -R "${_cu_username}:${_cu_group}" "$_cu_home"

  logging__success "User '${_cu_username}' configuration complete."
  return 0
}

_SKEL_DIR="${_FEAT_FILES_DIR}/skel"

if [[ "$INSTALL_ZSH" == true ]]; then
  if command -v zsh > /dev/null 2>&1; then
    logging__info "Zsh already installed — skipping."
  else
    logging__install "Installing Zsh..."
    ospkg__install_user zsh
  fi
fi

# ===================================================================
# Deploy system-wide shell configuration files
# ===================================================================
# install-shell has no single PREFIX; step 5 always targets /etc/ paths.
# file__ helpers escalate privileges automatically as needed.
logging__info "Deploying system-wide shell configuration files..."

# --- Shared (shell-agnostic) files ---
for _name in shellenv shellrc shellaliases; do
  _src="${_FEAT_FILES_DIR}/shell/${_name}"
  _dest="/etc/${_name}"
  if [ -f "$_src" ]; then
    file__cp -f "$_src" "$_dest"
    file__chmod 644 "$_dest"
    logging__success "  ${_dest}"
  fi
done

# --- /etc/profile ---
_src="${_FEAT_FILES_DIR}/profile"
if [ -f "$_src" ]; then
  file__cp -f "$_src" "/etc/profile"
  file__chmod 644 "/etc/profile"
  logging__success "  /etc/profile"
fi

# --- Bash system-wide bashrc ---
_SYS_BASHRC="$(shell__detect_bashrc)"
_src="${_FEAT_FILES_DIR}/bash/bashrc"
if [ -f "$_src" ]; then
  file__mkdir "$(dirname "$_SYS_BASHRC")"
  file__cp -f "$_src" "$_SYS_BASHRC"
  file__chmod 644 "$_SYS_BASHRC"
  logging__success "  ${_SYS_BASHRC}"
fi

# --- Bash bashenv (if present in files/) ---
_src="${_FEAT_FILES_DIR}/bash/bashenv"
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
    _src="${_FEAT_FILES_DIR}/zsh/${_name}"
    _dest="${_ZSH_ETC}/${_name}"
    if [ -f "$_src" ]; then
      file__cp -f "$_src" "$_dest"
      file__chmod 644 "$_dest"
      logging__success "  ${_dest}"
    fi
  done

fi

# ===================================================================
# Resolve user list
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
# Per-user configuration
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
# Set default shells
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
