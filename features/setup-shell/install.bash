# shellcheck shell=bash

_should_deploy() {
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

_setup_bash_env() {
  case "${SETUP_BASH_ENV:-auto}" in
    false) return 1 ;;
    true) return 0 ;;
    auto) _should_deploy bash ;;
  esac
}

_deploy_system() {
  case "${SETUP_SYSTEM:-auto}" in
    true) return 0 ;;
    false) return 1 ;;
    auto) users__is_privileged ;;
  esac
}

_deploy_skel() {
  case "${SETUP_SKEL:-auto}" in
    true) return 0 ;;
    false) return 1 ;;
    # auto: only copy when privileged and /etc/skel already exists (not on macOS).
    auto) users__is_privileged && [ -d /etc/skel ] ;;
  esac
}

_write_shellenv_dynamic_blocks() {
  local _f="$1"
  if [ -n "${UMASK}" ]; then
    shell__sync_block --files "$_f" --marker "setup-shell-shellenv-umask" \
      --content "umask ${UMASK}"
  else
    shell__sync_block --files "$_f" --marker "setup-shell-shellenv-umask"
  fi
  if [ -n "${LOCALE}" ]; then
    shell__sync_block --files "$_f" --marker "setup-shell-shellenv-locale" \
      --content "export LANG=\"${LOCALE}\"
export LC_ALL=\"${LOCALE}\""
  else
    shell__sync_block --files "$_f" --marker "setup-shell-shellenv-locale"
  fi
  local _editor="${DEFAULT_EDITOR:-auto}"
  case "$_editor" in
    skip)
      shell__sync_block --files "$_f" --marker "setup-shell-shellenv-editor"
      ;;
    auto)
      # shellcheck disable=SC2016
      shell__sync_block --files "$_f" --marker "setup-shell-shellenv-editor" \
        --content 'if [ -z "${VISUAL}" ] && [ -z "${EDITOR}" ]; then
    if command -v nano >/dev/null 2>&1; then
        export VISUAL=nano EDITOR=nano
    else
        export VISUAL=vi EDITOR=vi
    fi
fi'
      ;;
    neovim)
      shell__sync_block --files "$_f" --marker "setup-shell-shellenv-editor" \
        --content 'export VISUAL=nvim EDITOR=nvim'
      ;;
    *)
      shell__sync_block --files "$_f" --marker "setup-shell-shellenv-editor" \
        --content "export VISUAL=${_editor} EDITOR=${_editor}"
      ;;
  esac
}

_inject_user_config_blocks() {
  local _username="$1" _home="$2" _zdotdir="$3" _bash="$4" _zsh="$5"
  local _shellenv_file="${USER_SHELLENV:-.shellenv}"
  local _shellrc_file="${USER_SHELLRC:-.shellrc}"

  if ((_bash)); then
    if [ -f "$_home/.bash_profile" ]; then
      shell__write_block --file "$_home/.bash_profile" \
        --marker "setup-shell-bash-profile-shellenv" \
        --content "[ -f \"\$HOME/${_shellenv_file}\" ] && . \"\$HOME/${_shellenv_file}\""
    fi
    if [ -f "$_home/.bashrc" ]; then
      if [ -z "${BASH_THEME}" ]; then
        shell__sync_block --files "$_home/.bashrc" --marker "setup-shell-bashrc-theme"
      else
        local _bash_theme_expr
        case "${BASH_THEME}" in
          '~'*) _bash_theme_expr="$(users__expand_path --user "$_username" "$BASH_THEME")" ;;
          *) _bash_theme_expr="${BASH_THEME}" ;;
        esac
        shell__write_block --file "$_home/.bashrc" \
          --marker "setup-shell-bashrc-theme" \
          --content "_BASH_THEME=\"${_bash_theme_expr}\"
[ -f \"\$_BASH_THEME\" ] && . \"\$_BASH_THEME\"
unset _BASH_THEME"
      fi
      shell__write_block --file "$_home/.bashrc" \
        --marker "setup-shell-bashrc-shellrc" \
        --content "[ -f \"\$HOME/${_shellrc_file}\" ] && . \"\$HOME/${_shellrc_file}\""
    fi
  fi

  if ((_zsh)); then
    if [ -f "$_home/.zshenv" ]; then
      shell__write_block --file "$_home/.zshenv" \
        --marker "setup-shell-zshenv-shellenv" \
        --content "[ -f \"\$HOME/${_shellenv_file}\" ] && emulate sh -c \". \\\"\$HOME/${_shellenv_file}\\\"\""
    fi
    local _zshrc="${_zdotdir}/.zshrc"
    if [ -f "$_zshrc" ]; then
      if [ -z "${ZSH_THEME}" ]; then
        shell__sync_block --files "$_zshrc" --marker "setup-shell-zshrc-theme"
      else
        local _zsh_theme_expr
        case "${ZSH_THEME}" in
          '~'*) _zsh_theme_expr="$(users__expand_path --user "$_username" "$ZSH_THEME")" ;;
          *) _zsh_theme_expr="${ZSH_THEME}" ;;
        esac
        shell__write_block --file "$_zshrc" \
          --marker "setup-shell-zshrc-theme" \
          --content "[ -f \"${_zsh_theme_expr}\" ] && source \"${_zsh_theme_expr}\""
      fi
      shell__write_block --file "$_zshrc" \
        --marker "setup-shell-zshrc-shellrc" \
        --content "[ -f \"\$HOME/${_shellrc_file}\" ] && . \"\$HOME/${_shellrc_file}\""
    fi
  fi
}

_deploy_file() {
  # Deploy a skel file to a user's home with explicit mode control.
  # Usage: _deploy_file <src> <dest> <marker> <mode>
  local _src="$1" _dest="$2" _marker="$3" _mode="${4:-skip}"
  [ -f "$_src" ] || return 0

  case "$_mode" in
    uninstall)
      [ -f "$_dest" ] || return 0
      shell__sync_block --files "$_dest" --marker "$_marker"
      if [ -f "$_dest" ] && ! grep -qv '^[[:space:]]*$' "$_dest" 2> /dev/null; then
        file__rm "$_dest"
      fi
      ;;
    reinstall)
      [ -f "$_dest" ] && file__rm -f "$_dest"
      file__mkdir "$(dirname "$_dest")"
      shell__write_block --file "$_dest" --marker "$_marker" \
        --content "$(cat "$_src")"
      ;;
    update)
      file__mkdir "$(dirname "$_dest")"
      shell__write_block --file "$_dest" --marker "$_marker" \
        --content "$(cat "$_src")"
      ;;
    skip | *)
      [ -f "$_dest" ] && return 0
      file__mkdir "$(dirname "$_dest")"
      shell__write_block --file "$_dest" --marker "$_marker" \
        --content "$(cat "$_src")"
      ;;
  esac
}

_deploy_zdotdir() {
  # Inject or remove the ZDOTDIR block in ~/.zshenv with explicit mode control.
  # Usage: _deploy_zdotdir <zshenv-path> <zdotdir-path> <mode>
  local _cu_zshenv="$1" _cu_zdotdir="$2" _mode="${3:-skip}"
  case "$_mode" in
    uninstall)
      [ -f "$_cu_zshenv" ] || return 0
      shell__sync_block --files "$_cu_zshenv" --marker "setup-shell-zdotdir"
      if [ -f "$_cu_zshenv" ] && ! grep -qv '^[[:space:]]*$' "$_cu_zshenv" 2> /dev/null; then
        file__rm "$_cu_zshenv"
      fi
      ;;
    skip)
      # In skip mode, only inject ZDOTDIR if neither our managed block nor any
      # existing ZDOTDIR assignment is present. A user who already configured
      # ZDOTDIR in their .zshenv should not have a second line appended.
      grep -qF "# >>> setup-shell-zdotdir >>>" "$_cu_zshenv" 2> /dev/null && return 0
      grep -qE '^[[:space:]]*ZDOTDIR=' "$_cu_zshenv" 2> /dev/null && return 0
      shell__write_block --file "$_cu_zshenv" --marker "setup-shell-zdotdir" \
        --content "ZDOTDIR=\"${_cu_zdotdir}\""
      ;;
    *)
      shell__write_block --file "$_cu_zshenv" --marker "setup-shell-zdotdir" \
        --content "ZDOTDIR=\"${_cu_zdotdir}\""
      ;;
  esac
}

_deploy_to_skel() {
  # Copy skel files to /etc/skel for new-user seeding. Always uses plain cp —
  # /etc/skel is a system template dir, not user-managed, so marker logic doesn't apply.
  #
  # .zshrc/.zprofile/.zlogin belong in ZDOTDIR (not HOME), so they must go into a
  # matching subdirectory of /etc/skel so that useradd -m copies them to the right place.
  local _deploy_bash="$1" _deploy_zsh="$2"
  local _SKEL_DIR="${_FEAT_FILES_DIR}/skel"
  [ -d "$_SKEL_DIR" ] || return 0

  file__mkdir /etc/skel

  # Compute the ZDOTDIR location relative to /etc/skel (for file placement) and as a
  # shell value (for injection into /etc/skel/.zshenv).
  local _skel_zdotdir_rel=""   # relative subdir inside /etc/skel (empty = absolute path, skip)
  local _skel_zdotdir_value="" # value written into ZDOTDIR= in .zshenv
  if ((_deploy_zsh)); then
    case "${ZDOTDIR-}" in
      '')
        _skel_zdotdir_rel='.config/zsh'
        # shellcheck disable=SC2016
        _skel_zdotdir_value='${HOME}/.config/zsh'
        ;;
      ~/*)
        _skel_zdotdir_rel="${ZDOTDIR#\~/}"
        # shellcheck disable=SC2016
        _skel_zdotdir_value='${HOME}/'"${_skel_zdotdir_rel}"
        ;;
      /*)
        # Absolute ZDOTDIR cannot be mirrored under /etc/skel.
        # Skip skel placement for zsh config files; only .zshenv and bash files are copied.
        _skel_zdotdir_rel=""
        _skel_zdotdir_value="$ZDOTDIR"
        ;;
      *)
        _skel_zdotdir_rel='.config/zsh'
        # shellcheck disable=SC2016
        _skel_zdotdir_value='${HOME}/.config/zsh'
        ;;
    esac
  fi

  local _skel_file _rel _dest
  while IFS= read -r -d '' _skel_file; do
    _rel="${_skel_file#"${_SKEL_DIR}"/}"
    case "$_rel" in
      .bash_profile | .bashrc)
        ((_deploy_bash)) || continue
        _dest="/etc/skel/${_rel}"
        ;;
      .shellenv | .shellrc | .shellaliases)
        ((_deploy_bash)) || ((_deploy_zsh)) || continue
        _dest="/etc/skel/${_rel}"
        ;;
      .zshenv)
        ((_deploy_zsh)) || continue
        _dest="/etc/skel/${_rel}"
        ;;
      .zshrc | .zprofile | .zlogin)
        ((_deploy_zsh)) || continue
        if [[ -z "$_skel_zdotdir_rel" ]]; then
          logging__skip "  Skipping /etc/skel/${_rel}: ZDOTDIR is absolute (${ZDOTDIR})."
          continue
        fi
        _dest="/etc/skel/${_skel_zdotdir_rel}/${_rel}"
        ;;
      *) _dest="/etc/skel/${_rel}" ;;
    esac
    file__mkdir "$(dirname "$_dest")"
    file__cp -f "$_skel_file" "$_dest"
    file__chmod 644 "$_dest"
    logging__success "  /etc/skel/${_dest#/etc/skel/}"
  done < <(find "$_SKEL_DIR" -maxdepth 1 -type f -print0)

  if ((_deploy_zsh)) && [ -f /etc/skel/.zshenv ]; then
    shell__write_block --file /etc/skel/.zshenv --marker "setup-shell-zdotdir" \
      --content "ZDOTDIR=\"${_skel_zdotdir_value}\""
    logging__success "  /etc/skel/.zshenv (ZDOTDIR)"
  fi

  # Inject configurable inner blocks. Skel values are written literally (not per-user expanded);
  # shell expressions like ${XDG_CONFIG_HOME:-...} evaluate at runtime for each new user.
  local _shellenv_file="${USER_SHELLENV:-.shellenv}"
  local _shellrc_file="${USER_SHELLRC:-.shellrc}"

  if ((_deploy_bash)); then
    if [ -f /etc/skel/.bash_profile ]; then
      shell__write_block --file /etc/skel/.bash_profile \
        --marker "setup-shell-bash-profile-shellenv" \
        --content "[ -f \"\$HOME/${_shellenv_file}\" ] && . \"\$HOME/${_shellenv_file}\""
    fi
    if [ -f /etc/skel/.bashrc ]; then
      if [ -z "${BASH_THEME}" ]; then
        shell__sync_block --files /etc/skel/.bashrc --marker "setup-shell-bashrc-theme"
      else
        # Skel files are templates for future users: ~ cannot expand at install time.
        # Replace leading ~ with ${HOME} so each new user's shell resolves it correctly.
        local _skel_bash_theme_expr="${BASH_THEME}"
        [[ "${BASH_THEME}" == '~'* ]] && _skel_bash_theme_expr="\${HOME}${BASH_THEME#\~}"
        shell__write_block --file /etc/skel/.bashrc \
          --marker "setup-shell-bashrc-theme" \
          --content "_BASH_THEME=\"${_skel_bash_theme_expr}\"
[ -f \"\$_BASH_THEME\" ] && . \"\$_BASH_THEME\"
unset _BASH_THEME"
      fi
      shell__write_block --file /etc/skel/.bashrc \
        --marker "setup-shell-bashrc-shellrc" \
        --content "[ -f \"\$HOME/${_shellrc_file}\" ] && . \"\$HOME/${_shellrc_file}\""
    fi
  fi

  if ((_deploy_zsh)); then
    if [ -f /etc/skel/.zshenv ]; then
      shell__write_block --file /etc/skel/.zshenv \
        --marker "setup-shell-zshenv-shellenv" \
        --content "[ -f \"\$HOME/${_shellenv_file}\" ] && emulate sh -c \". \\\"\$HOME/${_shellenv_file}\\\"\""
    fi
    local _skel_zshrc
    if [[ -n "$_skel_zdotdir_rel" ]]; then
      _skel_zshrc="/etc/skel/${_skel_zdotdir_rel}/.zshrc"
    else
      _skel_zshrc=""
    fi
    if [ -n "$_skel_zshrc" ] && [ -f "$_skel_zshrc" ]; then
      if [ -z "${ZSH_THEME}" ]; then
        shell__sync_block --files "$_skel_zshrc" --marker "setup-shell-zshrc-theme"
      else
        # Skel files are templates for future users: ~ cannot expand at install time.
        # Replace leading ~ with ${HOME} so each new user's shell resolves it correctly.
        local _skel_zsh_theme_expr="${ZSH_THEME}"
        [[ "${ZSH_THEME}" == '~'* ]] && _skel_zsh_theme_expr="\${HOME}${ZSH_THEME#\~}"
        shell__write_block --file "$_skel_zshrc" \
          --marker "setup-shell-zshrc-theme" \
          --content "[ -f \"${_skel_zsh_theme_expr}\" ] && source \"${_skel_zsh_theme_expr}\""
      fi
      shell__write_block --file "$_skel_zshrc" \
        --marker "setup-shell-zshrc-shellrc" \
        --content "[ -f \"\$HOME/${_shellrc_file}\" ] && . \"\$HOME/${_shellrc_file}\""
    fi
  fi
}

__detect_existing_path_post() {
  # setup-shell has no installed binary; signal prior installation via managed-file markers.
  if [ -f /etc/shellenv ] ||
    grep -qF '# >>> setup-shell-zdotdir >>>' "${HOME:-/root}/.zshenv" 2> /dev/null ||
    grep -qF '# >>> setup-shell-bashrc >>>' "${HOME:-/root}/.bashrc" 2> /dev/null ||
    grep -qF '# >>> setup-shell-zshrc >>>' "${HOME:-/root}/.config/zsh/.zshrc" 2> /dev/null; then
    _FEAT_EXISTING=true
    logging__detect "Found existing setup-shell configuration (managed files present)."
  fi
}

__configure_user() {
  local _cu_username="$1"
  # _CU_MODE (set by callers like __uninstall_run__) takes precedence over IF_EXISTS.
  # IF_EXISTS is the template routing variable; _mode is the application-level parameter.
  # This is the single point where routing state is translated into explicit behavior.
  local _mode="${_CU_MODE:-${IF_EXISTS:-skip}}"
  local _SKEL_DIR="${_FEAT_FILES_DIR}/skel"
  local _deploy_bash=0 _deploy_zsh=0

  _should_deploy bash && _deploy_bash=1
  _should_deploy zsh && _deploy_zsh=1

  local _cu_home
  _cu_home="$(users__resolve_home "$_cu_username")"
  local _cu_group
  _cu_group="$(users__primary_group_of "$_cu_username" 2> /dev/null || echo "$_cu_username")"

  if [ ! -d "$_cu_home" ]; then
    logging__warn "Home directory '${_cu_home}' does not exist for user '${_cu_username}' — creating."
    file__mkdir "$_cu_home"
    file__chown "${_cu_username}:${_cu_group}" "$_cu_home"
  fi

  logging__info "Configuring user '${_cu_username}' (home: ${_cu_home})..."

  local _cu_xdg_config_home="${_cu_home}/.config"
  local _cu_zdotdir
  if [ -z "${ZDOTDIR-}" ]; then
    _cu_zdotdir="${_cu_xdg_config_home}/zsh"
  else
    _cu_zdotdir="$(users__expand_path --user "$_cu_username" "$ZDOTDIR")"
  fi

  if [ -n "$_SKEL_DIR" ] && [ -d "$_SKEL_DIR" ]; then
    local _cu_skel_file _cu_rel _cu_dest _base _marker
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
        .shellenv | .shellrc | .shellaliases)
          ((_deploy_bash)) || ((_deploy_zsh)) || continue
          _cu_dest="${_cu_home}/${_cu_rel}"
          ;;
        *) _cu_dest="${_cu_home}/${_cu_rel}" ;;
      esac
      _base="${_cu_rel#.}"
      _marker="setup-shell-${_base//_/-}"
      _deploy_file "$_cu_skel_file" "$_cu_dest" "$_marker" "$_mode"
    done < <(find "$_SKEL_DIR" -maxdepth 1 -type f -print0)
  fi

  if ((_deploy_zsh)); then
    if [[ "$_mode" != "uninstall" ]]; then file__mkdir "$_cu_zdotdir"; fi
    # ORDER MATTERS: skel loop above runs first so that in uninstall mode,
    # _deploy_file may already have stripped the skel block and deleted ~/.zshenv
    # if it was empty. _deploy_zdotdir below then checks for file existence and
    # returns early — correct. Swapping the order would leave the ZDOTDIR block
    # orphaned in a file that _deploy_file would subsequently be unable to find.
    _deploy_zdotdir "${_cu_home}/.zshenv" "$_cu_zdotdir" "$_mode"

    local _cu_zshtheme=""
    if [ -n "${ZSH_THEME}" ]; then
      _cu_zshtheme="$(users__expand_path --user "$_cu_username" \
        --env "ZDOTDIR=$_cu_zdotdir" --env "XDG_CONFIG_HOME=$_cu_xdg_config_home" \
        "$ZSH_THEME")"
    fi
    if [ -n "$_cu_zshtheme" ]; then
      if [[ "$_mode" == "uninstall" ]]; then
        [ -f "$_cu_zshtheme" ] && file__rm "$_cu_zshtheme"
      else
        # Downstream features (install-ohmyzsh, install-starship, etc.) append guarded
        # blocks to zshtheme via shell__write_block(). Must exist before first session.
        [ -f "$_cu_zshtheme" ] || printf '' | file__tee "$_cu_zshtheme"
      fi
    fi
  fi

  if ((_deploy_bash)); then
    local _cu_bashtheme=""
    if [ -n "${BASH_THEME}" ]; then
      _cu_bashtheme="$(users__expand_path --user "$_cu_username" \
        --env "XDG_CONFIG_HOME=$_cu_xdg_config_home" \
        "$BASH_THEME")"
    fi
    if [ -n "$_cu_bashtheme" ]; then
      if [[ "$_mode" != "uninstall" ]]; then file__mkdir "$(dirname "$_cu_bashtheme")"; fi
      if [[ "$_mode" == "uninstall" ]]; then
        [ -f "$_cu_bashtheme" ] && file__rm "$_cu_bashtheme"
      else
        [ -f "$_cu_bashtheme" ] || printf '' | file__tee "$_cu_bashtheme"
      fi
    fi
  fi

  if [[ "$_mode" != "uninstall" ]]; then
    _inject_user_config_blocks "$_cu_username" "$_cu_home" "$_cu_zdotdir" \
      "$_deploy_bash" "$_deploy_zsh"
  fi

  file__chown -R "${_cu_username}:${_cu_group}" "$_cu_home"

  logging__success "User '${_cu_username}' configuration complete."
  return 0
}

__install_run__() {
  local _deploy_bash=0 _deploy_zsh=0

  _should_deploy bash && _deploy_bash=1
  _should_deploy zsh && _deploy_zsh=1

  if _deploy_system; then
    logging__info "Deploying system-wide shell configuration files..."

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
    _write_shellenv_dynamic_blocks "/etc/shellenv"

    _src="${_FEAT_FILES_DIR}/profile"
    if [ -f "$_src" ]; then
      file__cp -f "$_src" "/etc/profile"
      file__chmod 644 "/etc/profile"
      logging__success "  /etc/profile"
    fi

    if ((_deploy_bash)); then
      local _SYS_BASHRC
      _SYS_BASHRC="$(shell__detect_bashrc)"
      _src="${_FEAT_FILES_DIR}/bash/bashrc"
      if [ -f "$_src" ]; then
        file__mkdir "$(dirname "$_SYS_BASHRC")"
        file__cp -f "$_src" "$_SYS_BASHRC"
        file__chmod 644 "$_SYS_BASHRC"
        logging__success "  ${_SYS_BASHRC}"
      fi

      _src="${_FEAT_FILES_DIR}/bash/bashenv"
      if [ -f "$_src" ]; then
        local _bashenv_dest
        if [ -n "${BASH_ENV_PATH:-}" ]; then
          _bashenv_dest="$BASH_ENV_PATH"
        else
          _bashenv_dest="$(dirname "$_SYS_BASHRC")/bashenv"
          [[ "$_SYS_BASHRC" == "/etc/bash.bashrc" || "$_SYS_BASHRC" == "/etc/bashrc" ]] &&
            _bashenv_dest="/etc/bashenv"
        fi
        file__mkdir "$(dirname "$_bashenv_dest")"
        file__cp -f "$_src" "$_bashenv_dest"
        file__chmod 644 "$_bashenv_dest"
        logging__success "  ${_bashenv_dest}"

        if _setup_bash_env; then
          if ! grep -qxF "BASH_ENV=${_bashenv_dest}" /etc/environment 2> /dev/null; then
            grep -v '^BASH_ENV=' /etc/environment 2> /dev/null | file__tee /etc/environment || true
            printf 'BASH_ENV=%s\n' "${_bashenv_dest}" | file__tee --append /etc/environment
            logging__success "  BASH_ENV=${_bashenv_dest} → /etc/environment"
          fi
        else
          logging__info "  Skipping BASH_ENV in /etc/environment (setup_bash_env=false)."
        fi
      fi
    fi

    if ((_deploy_zsh)); then
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
  else
    logging__info "Skipping system-wide files (setup_system=${SETUP_SYSTEM:-auto}; not privileged or disabled)."
  fi

  if _deploy_skel; then
    logging__info "Deploying skel files to /etc/skel..."
    _deploy_to_skel "$_deploy_bash" "$_deploy_zsh"
  fi
}

__install_finish_post() {
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

__uninstall_run__() {
  __run_feature_hook__ __uninstall_run_pre

  logging__info "Removing setup-shell managed content..."

  # Attempt system-file cleanup unconditionally; file__rm escalates via sudo as needed.
  # /etc/profile is intentionally excluded: it pre-exists on all Linux systems and was
  # deployed without markers, so there is no safe way to restore the original.
  file__rm -f /etc/shellenv /etc/shellrc /etc/shellaliases 2> /dev/null || true

  local _deploy_bash=0 _deploy_zsh=0
  _should_deploy bash && _deploy_bash=1
  _should_deploy zsh && _deploy_zsh=1

  if ((_deploy_bash)); then
    local _SYS_BASHRC
    _SYS_BASHRC="$(shell__detect_bashrc)"
    local _bashenv_dest
    if [ -n "${BASH_ENV_PATH:-}" ]; then
      _bashenv_dest="$BASH_ENV_PATH"
    else
      _bashenv_dest="$(dirname "$_SYS_BASHRC")/bashenv"
      [[ "$_SYS_BASHRC" == "/etc/bash.bashrc" || "$_SYS_BASHRC" == "/etc/bashrc" ]] &&
        _bashenv_dest="/etc/bashenv"
    fi
    file__rm -f "$_SYS_BASHRC" "$_bashenv_dest" 2> /dev/null || true
    if _setup_bash_env; then
      # Use grep+file__tee instead of sed -i: BSD sed requires an extension argument.
      grep -v '^BASH_ENV=' /etc/environment 2> /dev/null | file__tee /etc/environment || true
    fi
  fi

  if ((_deploy_zsh)); then
    local _ZSH_ETC
    _ZSH_ETC="$(shell__detect_zshdir)"
    local _name
    for _name in zshenv zprofile zshrc; do
      file__rm -f "${_ZSH_ETC}/${_name}" 2> /dev/null || true
    done
  fi

  local _CU_MODE=uninstall
  __feat_do_configure_users__

  __run_feature_hook__ __uninstall_run_post
}
