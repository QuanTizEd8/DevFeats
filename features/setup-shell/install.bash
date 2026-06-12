# shellcheck shell=bash

__setup_shell__should_deploy() {
  # Returns 0 when deployment for <shell> is enabled, 1 when skipped.
  local _shell="$1" _mode
  case "$_shell" in
    bash) _mode="${SETUP_BASH}" ;;
    zsh) _mode="${SETUP_ZSH}" ;;
  esac
  case "$_mode" in
    true) return 0 ;;
    false) return 1 ;;
    auto) command -v "$_shell" > /dev/null 2>&1 ;;
  esac
}

__configure_user() {
  # configure_user <username>
  # Set up per-user shell configuration files (skel copy, ZDOTDIR injection).
  local _cu_username="$1"
  local _SKEL_DIR="${_FEAT_FILES_DIR}/skel"
  local _deploy_bash=0 _deploy_zsh=0

  __setup_shell__should_deploy bash && _deploy_bash=1
  __setup_shell__should_deploy zsh && _deploy_zsh=1

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
  if [ -z "${ZDOTDIR-}" ]; then
    _cu_zdotdir="${_cu_xdg_config_home}/zsh"
  else
    _cu_zdotdir="$(users__expand_path --user "$_cu_username" "$ZDOTDIR")"
  fi

  # Mode: skip — bail out if any enabled dotfile already exists.
  if [[ "$USER_CONFIG_MODE" == "skip" ]]; then
    local _existing=false
    if ((_deploy_zsh)) && [ -f "${_cu_zdotdir}/.zshrc" ]; then
      _existing=true
    fi
    if ((_deploy_bash)) && [ -f "${_cu_home}/.bashrc" ]; then
      _existing=true
    fi
    if [[ "$_existing" == true ]]; then
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
        .bash_profile | .bashrc)
          ((_deploy_bash)) || continue
          _cu_dest="${_cu_home}/${_cu_rel}"
          ;;
        .zshenv)
          ((_deploy_zsh)) || continue
          _cu_dest="${_cu_home}/${_cu_rel}"
          ;;
        .zshrc | .zprofile | .zlogin)
          ((_deploy_zsh)) || continue
          _cu_dest="${_cu_zdotdir}/${_cu_rel}"
          ;;
        *) _cu_dest="${_cu_home}/${_cu_rel}" ;;
      esac
      case "$USER_CONFIG_MODE" in
        overwrite)
          file__mkdir "$(dirname "$_cu_dest")"
          file__cp -f "$_cu_skel_file" "$_cu_dest"
          ;;
        augment)
          if [ ! -f "$_cu_dest" ]; then
            file__mkdir "$(dirname "$_cu_dest")"
            file__cp "$_cu_skel_file" "$_cu_dest"
          fi
          ;;
      esac
    done < <(find "$_SKEL_DIR" -maxdepth 1 -type f -print0)
  fi

  # Create empty per-user theme files if not already present.
  # Downstream features (install-ohmyzsh, install-starship, etc.) append guarded
  # blocks to these via shell__write_block(). The skel .zshrc/.bashrc source them
  # conditionally, so they must exist before the first interactive session.
  if ((_deploy_zsh)); then
    # Inject ZDOTDIR into ~/.zshenv.
    local _cu_zshenv="${_cu_home}/.zshenv"
    file__mkdir "$_cu_zdotdir"
    shell__write_block --file "$_cu_zshenv" --marker "setup-shell-zdotdir" --content "ZDOTDIR=\"${_cu_zdotdir}\""

    local _cu_zshtheme="${_cu_zdotdir}/zshtheme"
    [ -f "${_cu_zshtheme}" ] || touch "${_cu_zshtheme}"
  fi

  if ((_deploy_bash)); then
    local _cu_bashdir="${_cu_xdg_config_home}/bash"
    file__mkdir "${_cu_bashdir}"
    local _cu_bashtheme="${_cu_bashdir}/bashtheme"
    [ -f "${_cu_bashtheme}" ] || touch "${_cu_bashtheme}"
  fi

  # Fix ownership — give the user full ownership of their entire home directory.
  file__chown -R "${_cu_username}:${_cu_group}" "$_cu_home"

  logging__success "User '${_cu_username}' configuration complete."
  return 0
}

__install_run__() {
  local _deploy_bash=0 _deploy_zsh=0

  __setup_shell__should_deploy bash && _deploy_bash=1
  __setup_shell__should_deploy zsh && _deploy_zsh=1

  # ===================================================================
  # Deploy system-wide shell configuration files
  # ===================================================================
  # setup-shell has no single PREFIX; step 5 always targets /etc/ paths.
  # file__ helpers escalate privileges automatically as needed.
  logging__info "Deploying system-wide shell configuration files..."

  # --- Shared (shell-agnostic) files ---
  local _name _src _dest
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

  if ((_deploy_bash)); then
    # --- Bash system-wide bashrc ---
    local _SYS_BASHRC
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
      local _bashenv_dest
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
  fi

  if ((_deploy_zsh)); then
    # --- Zsh system-wide files ---
    local _ZSH_ETC
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
}

__install_finish_post() {
  __feat_do_configure_users__

  # ===================================================================
  # Set default shells
  # ===================================================================
  if [[ "$SET_USER_SHELLS" != "none" ]] && [ ${#_FEAT_CONFIGURE_USERS[@]} -gt 0 ]; then
    local _TARGET_SHELL=""
    case "$SET_USER_SHELLS" in
      zsh)
        _TARGET_SHELL="$(command -v zsh 2> /dev/null || true)"
        if [ -z "$_TARGET_SHELL" ]; then
          logging__error "set_user_shells=zsh but zsh is not installed."
          return 1
        fi
        ;;
      bash)
        _TARGET_SHELL="$(command -v bash 2> /dev/null || true)"
        if [ -z "$_TARGET_SHELL" ]; then
          logging__error "set_user_shells=bash but bash is not installed."
          return 1
        fi
        ;;
    esac

    users__set_login_shell "$_TARGET_SHELL" "${_FEAT_CONFIGURE_USERS[@]}"
  fi
}
