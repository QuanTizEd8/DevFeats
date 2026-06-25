# shellcheck shell=bash

_state_dir() {
  printf '%s/state\n' "${_FEAT_SHARE_DIR_ROOT}"
}

_state_env_file() {
  printf '%s/config.env\n' "$(_state_dir)"
}

_global_users_file() {
  printf '%s/global-users\n' "$(_state_dir)"
}

_emit_state_var() {
  local _name="$1" _value="${2-}"
  _value="${_value//\\/\\\\}"
  _value="${_value//\"/\\\"}"
  printf '%s="%s"\n' "${_name}" "${_value}"
}

_effective_method() {
  local _method="${METHOD:-}"
  if [[ -z "${_method}" || "${_method}" == "auto" ]]; then
    _method="${_FEAT_EXISTING_METHOD:-}"
  fi
  printf '%s\n' "${_method}"
}

_resolved_scope() {
  case "${CONFIG_SCOPE:-auto}" in
    auto)
      if users__is_privileged; then
        printf 'system\n'
      else
        printf 'global\n'
      fi
      ;;
    system | global | local | worktree | file | none)
      printf '%s\n' "${CONFIG_SCOPE}"
      ;;
    *)
      logging__error "Unsupported config_scope='${CONFIG_SCOPE:-}'."
      return 1
      ;;
  esac
}

_scope_is_repo() {
  case "$1" in
    local | worktree | file) return 0 ;;
    *) return 1 ;;
  esac
}

_scope_needs_repo() {
  local _scope="$1"
  [[ "${_scope}" == "none" ]] && return 1
  _scope_is_repo "${_scope}" && return 0
  [[ "${SKIP_REPO:-true}" == "false" ]]
}

_manual_hooks_value() {
  local _manual="${MANUAL_HOOKS:-false}"
  if [[ "${SKIP_REPO:-true}" == "true" && "${_manual}" == "true" ]]; then
    if [[ -z "${_GIT_LFS_MANUAL_HOOKS_IGNORED:-}" ]]; then
      logging__info "manual_hooks=true has no effect when skip_repo=true; ignoring."
      declare -g _GIT_LFS_MANUAL_HOOKS_IGNORED=1
    fi
    _manual=false
  fi
  printf '%s\n' "${_manual}"
}

_validate_requested_config() {
  local _scope
  _scope="$(_resolved_scope)" || return 1
  [[ "${_scope}" == "none" ]] && return 0

  if [[ "${_scope}" == "file" && -z "${CONFIG_FILE:-}" ]]; then
    logging__error "config_scope=file requires config_file to be set."
    return 1
  fi

  if _scope_is_repo "${_scope}"; then
    if [[ -n "${REPO_DIR:-}" ]] || os__is_devcontainer_build; then
      return 0
    fi
    logging__error "config_scope='${_scope}' requires repo_dir outside devcontainer lifecycle execution."
    return 1
  fi

  if [[ "${SKIP_REPO:-true}" == "false" && -z "${REPO_DIR:-}" ]]; then
    logging__error "skip_repo=false requires repo_dir when config_scope='${_scope}'."
    return 1
  fi
}

__install_init_post() {
  _validate_requested_config
}

__reinstall_init_post() {
  _validate_requested_config
}

__update_init_post() {
  _validate_requested_config
}

_git_lfs_bin_dir() {
  local _bin=""
  if [[ -n "${_RESOLVED_PREFIX:-}" && -x "${_RESOLVED_PREFIX}/bin/git-lfs" ]]; then
    printf '%s/bin\n' "${_RESOLVED_PREFIX}"
    return 0
  fi
  if [[ -n "${_FEAT_EXISTING_PATH:-}" && -x "${_FEAT_EXISTING_PATH}" ]]; then
    printf '%s\n' "${_FEAT_EXISTING_PATH%/*}"
    return 0
  fi
  _bin="$(command -v git-lfs 2> /dev/null || true)"
  [[ -n "${_bin}" ]] && printf '%s\n' "${_bin%/*}" || printf ''
}

_run_git() {
  local _user="$1" _repo_dir="$2"
  shift 2
  local _bin_dir _path_env
  _bin_dir="$(_git_lfs_bin_dir)"
  _path_env="${PATH}"
  [[ -n "${_bin_dir}" ]] && _path_env="${_bin_dir}:${_path_env}"

  local -a _cmd=(env "PATH=${_path_env}" git)
  [[ -n "${_repo_dir}" ]] && _cmd+=(-C "${_repo_dir}")
  _cmd+=("$@")

  if [[ -n "${_user}" && "${_user}" != "$(users__get_current --no-sudo)" ]]; then
    users__run_as "${_user}" -- "${_cmd[@]}"
  else
    "${_cmd[@]}"
  fi
}

_repo_config_is_deferred() {
  local _scope="$1"
  _scope_is_repo "${_scope}" &&
    [[ -z "${REPO_DIR:-}" ]] &&
    os__is_devcontainer_build
}

_resolved_repo_dir_now() {
  local _scope="$1"
  if ! _scope_needs_repo "${_scope}"; then
    printf '\n'
    return 0
  fi
  if _repo_config_is_deferred "${_scope}"; then
    printf '\n'
    return 0
  fi
  if [[ -z "${REPO_DIR:-}" ]]; then
    logging__error "repo_dir is required for config_scope='${_scope}' when skip_repo=false or repository-scoped configuration is requested."
    return 1
  fi
  printf '%s\n' "${REPO_DIR}"
}

_assert_repo() {
  local _repo_dir="$1"
  [[ -n "${_repo_dir}" ]] || return 0
  if ! git -C "${_repo_dir}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    logging__error "repo_dir '${_repo_dir}' is not a Git work tree."
    return 1
  fi
}

_resolve_config_file_path() {
  local _scope="$1" _repo_dir="$2"
  [[ "${_scope}" == "file" ]] || {
    printf '\n'
    return 0
  }
  if [[ -z "${CONFIG_FILE:-}" ]]; then
    logging__error "config_scope=file requires config_file."
    return 1
  fi
  if [[ "${CONFIG_FILE}" = /* ]]; then
    printf '%s\n' "${CONFIG_FILE}"
  elif [[ -n "${_repo_dir}" ]]; then
    printf '%s/%s\n' "${_repo_dir%/}" "${CONFIG_FILE}"
  else
    logging__error "Relative config_file='${CONFIG_FILE}' requires a resolved repo_dir."
    return 1
  fi
}

_enable_worktree_config() {
  local _repo_dir="$1" _user="${2:-}"
  logging__install "Enabling extensions.worktreeConfig in '${_repo_dir}'."
  _run_git "${_user}" "${_repo_dir}" config extensions.worktreeConfig true
}

_build_install_argv() {
  local -n _out="$1"
  local _scope="$2" _config_file="$3"
  local _manual
  _manual="$(_manual_hooks_value)"

  _out=(install)
  case "${_scope}" in
    system) _out+=(--system) ;;
    global) _out+=(--global) ;;
    local) _out+=(--local) ;;
    worktree) _out+=(--worktree) ;;
    file) _out+=("--file=${_config_file}") ;;
    *)
      logging__error "Cannot build install argv for config_scope='${_scope}'."
      return 1
      ;;
  esac
  [[ "${SKIP_REPO:-true}" == "true" ]] && _out+=(--skip-repo)
  [[ "${SKIP_SMUDGE:-false}" == "true" ]] && _out+=(--skip-smudge)
  [[ "${FORCE_CONFIG:-false}" == "true" ]] && _out+=(--force)
  [[ "${_manual}" == "true" ]] && _out+=(--manual)
  return 0
}

_build_uninstall_argv_from_values() {
  local -n _out="$1"
  local _scope="$2" _config_file="$3" _skip_repo="$4"

  _out=(uninstall)
  case "${_scope}" in
    system) _out+=(--system) ;;
    global) _out+=(--global) ;;
    local) _out+=(--local) ;;
    worktree) _out+=(--worktree) ;;
    file) _out+=("--file=${_config_file}") ;;
    *)
      logging__error "Cannot build uninstall argv for config_scope='${_scope}'."
      return 1
      ;;
  esac
  [[ "${_skip_repo}" == "true" ]] && _out+=(--skip-repo)
  return 0
}

_method_auto_configures_pkg_default() {
  local _method="$1" _pm
  _pm="$(ctx__get plat.pm)"
  case "${_method}:${_pm}" in
    package:apt | package:apk | package:dnf | package:yum | upstream-package:apt | upstream-package:dnf | upstream-package:yum)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_pkg_default_matches_values() {
  local _scope="$1" _skip_repo="$2" _skip_smudge="$3" _force="$4" _manual="$5"
  [[ "${_scope}" == "system" ]] &&
    [[ "${_skip_repo}" == "true" ]] &&
    [[ "${_skip_smudge}" != "true" ]] &&
    [[ "${_force}" != "true" ]] &&
    [[ "${_manual}" != "true" ]]
}

_pkg_default_matches_requested() {
  local _scope="$1" _manual
  _manual="$(_manual_hooks_value)"
  _pkg_default_matches_values \
    "${_scope}" \
    "${SKIP_REPO:-true}" \
    "${SKIP_SMUDGE:-false}" \
    "${FORCE_CONFIG:-false}" \
    "${_manual}"
}

_reconcile_pkg_default() {
  local _method="$1" _scope="$2"
  [[ -n "${_GIT_LFS_PKG_DEFAULT_RECONCILED:-}" ]] && return 0
  _method_auto_configures_pkg_default "${_method}" || return 0
  _pkg_default_matches_requested "${_scope}" && return 0

  logging__install "Removing package-installed default Git LFS system configuration before applying the requested configuration."
  local -a _argv=()
  _build_uninstall_argv_from_values _argv system "" true || return 1
  _run_git "" "" lfs "${_argv[@]}"
  declare -g _GIT_LFS_PKG_DEFAULT_RECONCILED=1
}

_apply_current_non_global_config() {
  local _scope="$1" _method="$2"
  if _repo_config_is_deferred "${_scope}"; then
    logging__info "Deferring repo-scoped Git LFS configuration to postCreateCommand because repo_dir is empty during the devcontainer build."
    return 0
  fi

  local _repo_dir _config_file
  _repo_dir="$(_resolved_repo_dir_now "${_scope}")" || return 1
  _assert_repo "${_repo_dir}" || return 1
  _config_file="$(_resolve_config_file_path "${_scope}" "${_repo_dir}")" || return 1

  if [[ "${_scope}" == "worktree" ]]; then
    _enable_worktree_config "${_repo_dir}"
  fi

  if _method_auto_configures_pkg_default "${_method}" &&
    _pkg_default_matches_requested "${_scope}"; then
    logging__info "Package installation already provides the requested Git LFS system defaults; skipping explicit git lfs install."
    return 0
  fi

  _reconcile_pkg_default "${_method}" "${_scope}" || return 1

  local -a _argv=()
  _build_install_argv _argv "${_scope}" "${_config_file}" || return 1
  logging__install "Applying Git LFS configuration at scope='${_scope}'."
  _run_git "" "${_repo_dir}" lfs "${_argv[@]}"
}

_write_state() {
  local _scope="$1" _method="$2"
  local _state_dir _state_file _users_file
  _state_dir="$(_state_dir)"
  _state_file="$(_state_env_file)"
  _users_file="$(_global_users_file)"

  file__mkdir "${_state_dir}"
  {
    _emit_state_var GIT_LFS_STATE_ACTIVE_METHOD "${_method}"
    _emit_state_var GIT_LFS_STATE_CONFIG_SCOPE "${_scope}"
    _emit_state_var GIT_LFS_STATE_CONFIG_FILE "${CONFIG_FILE:-}"
    _emit_state_var GIT_LFS_STATE_REPO_DIR "${REPO_DIR:-}"
    _emit_state_var GIT_LFS_STATE_SKIP_REPO "${SKIP_REPO:-true}"
    _emit_state_var GIT_LFS_STATE_SKIP_SMUDGE "${SKIP_SMUDGE:-false}"
    _emit_state_var GIT_LFS_STATE_FORCE_CONFIG "${FORCE_CONFIG:-false}"
    _emit_state_var GIT_LFS_STATE_MANUAL_HOOKS "$(_manual_hooks_value)"
    _emit_state_var GIT_LFS_STATE_AUTO_PULL "${AUTO_PULL:-true}"
  } | file__tee "${_state_file}"

  if [[ "${_scope}" == "global" && -v _FEAT_CONFIGURE_USERS ]]; then
    if ((${#_FEAT_CONFIGURE_USERS[@]} > 0)); then
      printf '%s\n' "${_FEAT_CONFIGURE_USERS[@]}" | file__tee "${_users_file}"
    else
      printf '' | file__tee "${_users_file}"
    fi
  else
    file__rm -f "${_users_file}" 2> /dev/null || true
  fi
}

_finalize_config_state() {
  local _scope _method
  _scope="$(_resolved_scope)" || return 1
  _method="$(_effective_method)"

  if [[ "${_scope}" == "none" ]]; then
    logging__info "config_scope=none; skipping feature-managed Git LFS configuration."
  elif [[ "${_scope}" == "global" ]]; then
    if [[ -n "${_GIT_LFS_CONFIGURE_USER_FAILED:-}" ]]; then
      logging__error "One or more global Git LFS user-configuration steps failed."
      return 1
    fi
    if [[ ! -v _FEAT_CONFIGURE_USERS || ${#_FEAT_CONFIGURE_USERS[@]} -eq 0 ]]; then
      _reconcile_pkg_default "${_method}" "${_scope}" || return 1
      logging__skip "No users resolved for global Git LFS configuration."
    fi
  else
    _apply_current_non_global_config "${_scope}" "${_method}" || return 1
  fi

  _write_state "${_scope}" "${_method}"
}

__configure_user() {
  local _user="$1"
  local _scope _method _repo_dir _config_file
  _scope="$(_resolved_scope)" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
  [[ "${_scope}" == "global" ]] || return 0

  _method="$(_effective_method)"
  _repo_dir="$(_resolved_repo_dir_now "${_scope}")" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
  _assert_repo "${_repo_dir}" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
  _config_file="$(_resolve_config_file_path "${_scope}" "${_repo_dir}")" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }

  _reconcile_pkg_default "${_method}" "${_scope}" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }

  local -a _argv=()
  _build_install_argv _argv "${_scope}" "${_config_file}" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }

  logging__install "Applying Git LFS global configuration for user '${_user}'."
  _run_git "${_user}" "${_repo_dir}" lfs "${_argv[@]}" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
}

__install_finish_post() {
  _finalize_config_state
}

__skip_post() {
  _validate_requested_config || return 1
  _finalize_config_state || return 1
  __deploy_lifecycle_scripts__
}

_uninstall_state_for_user() {
  local _user="$1" _scope="$2" _config_file="$3" _repo_dir="$4" _skip_repo="$5"
  local -a _argv=()
  if [[ "${_scope}" == "worktree" && -n "${_repo_dir}" ]]; then
    _enable_worktree_config "${_repo_dir}" "${_user}" || return 1
  fi
  _build_uninstall_argv_from_values _argv "${_scope}" "${_config_file}" "${_skip_repo}" || return 1
  logging__remove "Removing Git LFS configuration at scope='${_scope}'${_user:+ for user '${_user}'}."
  _run_git "${_user}" "${_repo_dir}" lfs "${_argv[@]}"
}

_uninstall_managed_config() {
  local _state_file _users_file
  _state_file="$(_state_env_file)"
  _users_file="$(_global_users_file)"
  [[ -f "${_state_file}" ]] || return 0

  # shellcheck disable=SC1090
  . "${_state_file}"

  local _scope="${GIT_LFS_STATE_CONFIG_SCOPE:-none}"
  local _method="${GIT_LFS_STATE_ACTIVE_METHOD:-}"
  local _repo_dir="${GIT_LFS_STATE_REPO_DIR:-}"
  local _config_file="${GIT_LFS_STATE_CONFIG_FILE:-}"
  local _skip_repo="${GIT_LFS_STATE_SKIP_REPO:-true}"
  local _skip_smudge="${GIT_LFS_STATE_SKIP_SMUDGE:-false}"
  local _force="${GIT_LFS_STATE_FORCE_CONFIG:-false}"
  local _manual="${GIT_LFS_STATE_MANUAL_HOOKS:-false}"

  [[ -n "${_scope}" && "${_scope}" != "none" ]] || return 0

  if _method_auto_configures_pkg_default "${_method}" &&
    _pkg_default_matches_values "${_scope}" "${_skip_repo}" "${_skip_smudge}" "${_force}" "${_manual}"; then
    logging__skip "Package uninstall will remove the default Git LFS system configuration; skipping explicit feature-managed uninstall."
    return 0
  fi

  if [[ "${_scope}" == "global" ]]; then
    [[ -f "${_users_file}" ]] || {
      logging__skip "No stored global-users file found; skipping Git LFS global uninstall."
      return 0
    }
    local _user
    while IFS= read -r _user; do
      [[ -n "${_user}" ]] || continue
      if ! id "${_user}" > /dev/null 2>&1; then
        logging__warn "Stored user '${_user}' no longer exists; skipping Git LFS global uninstall for that user."
        continue
      fi
      _uninstall_state_for_user "${_user}" "${_scope}" "" "${_repo_dir}" "${_skip_repo}" || return 1
    done < "${_users_file}"
    return 0
  fi

  if { _scope_is_repo "${_scope}" || [[ "${_skip_repo}" == "false" ]]; } && [[ -z "${_repo_dir}" ]]; then
    logging__warn "Stored repo_dir is empty; skipping repo-scoped Git LFS uninstall."
    return 0
  fi
  if [[ -n "${_repo_dir}" ]] && ! git -C "${_repo_dir}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    logging__warn "Stored repo_dir '${_repo_dir}' is no longer a Git work tree; skipping repo-scoped Git LFS uninstall."
    return 0
  fi

  if [[ "${_scope}" == "file" && "${_config_file}" != /* ]]; then
    if [[ -z "${_repo_dir}" ]]; then
      logging__warn "Stored relative config_file='${_config_file}' has no repo_dir context; skipping file-scoped Git LFS uninstall."
      return 0
    fi
    _config_file="${_repo_dir%/}/${_config_file}"
  fi

  _uninstall_state_for_user "" "${_scope}" "${_config_file}" "${_repo_dir}" "${_skip_repo}"
}

__uninstall_run_pre() {
  _uninstall_managed_config
}

__uninstall_finish_post() {
  local _state_dir _state_file _users_file _installed_method
  _state_dir="$(_state_dir)"
  _state_file="$(_state_env_file)"
  _users_file="$(_global_users_file)"
  _installed_method="${_state_dir}/installed-method"

  file__rm -f "${_state_file}" 2> /dev/null || true
  file__rm -f "${_users_file}" 2> /dev/null || true
  file__rm -f "${_installed_method}" 2> /dev/null || true
  file__rm -d "${_state_dir}" 2> /dev/null || true
  file__rm -d "${_FEAT_SHARE_DIR_ROOT}" 2> /dev/null || true
  file__rm -d "${_FEAT_SHARE_DIR_NONROOT}" 2> /dev/null || true
}
