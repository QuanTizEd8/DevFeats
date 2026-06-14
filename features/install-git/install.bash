# shellcheck shell=bash

__resolve_input_prefixes_post() {
  # Resolve SYSCONFDIR after PREFIX is known.  __install_run_source_build passes
  # it to make as sysconfdir=; _git__write_system_gitconfig uses it to locate gitconfig.
  if [[ "${SYSCONFDIR}" == "auto" ]]; then
    if users__is_user_path "${_RESOLVED_PREFIX}"; then
      SYSCONFDIR="$(users__home_of_path_owner "${_RESOLVED_PREFIX}")/.config"
    else
      SYSCONFDIR="/etc"
    fi
  fi
}

# ── Package method overrides ───────────────────────────────────────────────

__install_run_package__() {
  logging__install "Installing git via OS package manager."
  # Override the template default to support version-pinned installs.
  # VERSION=latest or stable → no version constraint (empty extra-var).
  # VERSION=x.y.z → pass to ospkg as a version constraint.
  local _pkg_version=""
  case "${VERSION:-latest}" in
    stable | latest) ;;
    *) _pkg_version="${VERSION}" ;;
  esac
  __dep_install__ run os-pkg --extra-var "VERSION=${_pkg_version}"
}

__update_run_package__() {
  logging__install "Updating git via OS package manager."
  local _pkg_version=""
  case "${VERSION:-latest}" in
    stable | latest) ;;
    *) _pkg_version="${VERSION}" ;;
  esac
  __dep_install__ run os-pkg --extra-var "VERSION=${_pkg_version}" --update
}

# ── Source build ───────────────────────────────────────────────────────────

__install_run_source_pre() {
  # Validates the build environment and installs build deps before download.
  file__mkdir "${_RESOLVED_PREFIX}"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "PREFIX '${_RESOLVED_PREFIX}' could not be created (check privilege)."
    return "$_rc"
  }
  if users__is_user_path "${_RESOLVED_PREFIX}" && [[ ! -w "${_RESOLVED_PREFIX}" ]]; then
    logging__error "PREFIX '${_RESOLVED_PREFIX}' is not writable."
    return 1
  fi

  if [[ "$(os__kernel)" == "Darwin" ]]; then
    xcode-select --print-path > /dev/null 2>&1 || {
      logging__error "Xcode Command Line Tools are required for source builds on macOS."
      logging__info "Install with: xcode-select --install"
      return 1
    }
  fi

  # User-local installs cannot invoke the OS package manager; assume build
  # deps were preinstalled by the caller.
  if ! users__is_user_path "${_RESOLVED_PREFIX}"; then
    __dep_install__ build source-build
  else
    logging__info "User-local mode: skipping build dependency installation; expecting required packages to be preinstalled."
  fi
}

# __install_run_source_build <src_dir>
# Compiles and installs git from source.
# $1 = path to the top-level extracted source directory.
__install_run_source_build() {
  local _src_dir="$1"
  local _git_make_flags="prefix=${_RESOLVED_PREFIX} sysconfdir=${SYSCONFDIR} USE_LIBPCRE2=YesPlease"

  # Alpine requires these extra flags.
  if [[ "$(os__platform)" == "alpine" ]]; then
    _git_make_flags="${_git_make_flags} NO_GETTEXT=YesPlease NO_REGEX=YesPlease NO_SVN_TESTS=YesPlease NO_SYS_POLL_H=1"
  fi

  # Parse NO_FLAGS: space/comma-separated keywords → NO_<FLAG>=YesPlease.
  local _user_flags
  _user_flags="$(printf '%s' "${NO_FLAGS[*]}" | tr '[:lower:],' '[:upper:] ')"
  local _flag
  for _flag in ${_user_flags}; do
    case "${_flag}" in
      PERL | PYTHON | TCLTK | GETTEXT)
        case " ${_git_make_flags} " in
          *" NO_${_flag}="*) ;;
          *) _git_make_flags="${_git_make_flags} NO_${_flag}=YesPlease" ;;
        esac
        ;;
      '') ;;
      *)
        logging__warn "no_flags: unknown keyword '${_flag}' — ignored"
        ;;
    esac
  done

  # SOURCE_MAKE_FLAGS: user-supplied extra make variables (array).
  local -a _extra_make_flags=()
  if [[ -v SOURCE_MAKE_FLAGS ]]; then
    _extra_make_flags+=("${SOURCE_MAKE_FLAGS[@]+"${SOURCE_MAKE_FLAGS[@]}"}")
  fi

  local _ncpus
  _ncpus="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 1)"

  logging__build "Building git ${VERSION}..."
  (
    cd "${_src_dir}" || {
      logging__error "git source build: cannot cd to '${_src_dir}'."
      exit 1
    }
    # shellcheck disable=SC2086
    make -s -j"${_ncpus}" ${_git_make_flags} "${_extra_make_flags[@]+"${_extra_make_flags[@]}"}" all
    # shellcheck disable=SC2086
    make -s ${_git_make_flags} "${_extra_make_flags[@]+"${_extra_make_flags[@]}"}" install
  ) || {
    logging__error "git source build failed in '${_src_dir}'."
    return 1
  }

  # `make install` does not install contrib/completion scripts.  Copy them
  # from the source tree to the prefix now, before the build dir is cleaned.
  local _comp_src_dir="${_src_dir}/contrib/completion"
  local _comp_dst_dir="${_RESOLVED_PREFIX}/share/git-core/contrib/completion"
  if [[ -d "${_comp_src_dir}" ]]; then
    logging__install "Installing git completion scripts to '${_comp_dst_dir}'."
    file__mkdir "${_comp_dst_dir}"
    file__cp "${_comp_src_dir}/"*.bash "${_comp_dst_dir}/" 2> /dev/null || true
    file__cp "${_comp_src_dir}/"*.zsh "${_comp_dst_dir}/" 2> /dev/null || true
  fi

  "${_RESOLVED_PREFIX}/bin/git" --version
  logging__success "git ${VERSION} installed to ${_RESOLVED_PREFIX}/bin/git."
}

# ── Uninstall ──────────────────────────────────────────────────────────────

__uninstall_run_prefix_post() {
  # __uninstall_run_prefix__ removes only the primary binary.  A source build
  # scatters additional files; clean them up here.
  # _FEAT_EXISTING_PATH is still set — it is cleared by __uninstall_finish__
  # which runs after __uninstall_run__ completes.
  local _prefix
  _prefix="${_FEAT_EXISTING_PATH%/bin/git}"
  [[ -n "${_prefix}" && "${_prefix}" != "/" ]] || {
    logging__skip "Cannot derive git prefix from '${_FEAT_EXISTING_PATH}'; skipping extra source cleanup."
    return 0
  }
  logging__remove "Removing git source-build artifacts under '${_prefix}'."
  file__rm -rf "${_prefix}/lib/git-core/"
  file__rm -rf "${_prefix}/share/git-core/"
  file__rm -f "${_prefix}/bin/git-"*
  file__rm -f \
    "${_prefix}/share/man/man1/git"* \
    "${_prefix}/share/man/man5/git"* \
    "${_prefix}/share/man/man7/git"*
}

# ── Post-install ───────────────────────────────────────────────────────────

_git__write_system_gitconfig() {
  local _cfg
  if ! users__is_user_path "${_RESOLVED_PREFIX}"; then
    _cfg="${SYSCONFDIR}/gitconfig"
  else
    _cfg="$(users__home_of_path_owner "${_RESOLVED_PREFIX}")/.config/git/config"
  fi

  local _content=""
  if [[ -n "${DEFAULT_BRANCH}" ]]; then
    _content+="[init]"$'\n\t'"defaultBranch = ${DEFAULT_BRANCH}"$'\n'
  fi
  if [[ "${#SAFE_DIRECTORY[@]}" -gt 0 ]]; then
    _content+="[safe]"$'\n'
    local _entry
    for _entry in "${SAFE_DIRECTORY[@]}"; do
      _content+=$'\t'"directory = ${_entry}"$'\n'
    done
  fi
  if [[ -n "${SYSTEM_GITCONFIG}" ]]; then
    _content+="${SYSTEM_GITCONFIG}"$'\n'
  fi
  if [[ -n "${_content}" ]]; then
    logging__install "Writing system gitconfig to '${_cfg}'."
    shell__sync_block --files "${_cfg}" --marker "system gitconfig (install-git)" --content "${_content}"
  else
    logging__skip "No system gitconfig content configured; skipping."
  fi
}

_export_git_manpath() {
  if [[ "${METHOD}" != "source" ]]; then
    logging__skip "METHOD='${METHOD}'; skipping git MANPATH export."
    return 0
  fi
  case "${PREFIX_DISCOVERY:-auto}" in
    none | symlink)
      logging__skip "PREFIX_DISCOVERY='${PREFIX_DISCOVERY}'; skipping git MANPATH export."
      return 0
      ;;
  esac
  if [[ "${_RESOLVED_PREFIX}" == "/usr/local" || "${_RESOLVED_PREFIX}" == "$(users__resolve_home)/.local" ]]; then
    logging__skip "Standard prefix '${_RESOLVED_PREFIX}'; skipping git MANPATH export."
    return 0
  fi
  logging__install "Writing git MANPATH export for '${_RESOLVED_PREFIX}/share/man'."
  local _scope _home _manpath_dir
  _scope="$(users__is_user_path "${_RESOLVED_PREFIX}" && printf user || printf system)"
  _home="$(users__home_of_path_owner "${_RESOLVED_PREFIX}")"
  _manpath_dir="${_RESOLVED_PREFIX}/share/man"
  local -a _shells=()
  if [[ "${#PREFIX_EXPORTS[@]}" -gt 0 ]]; then
    _shells=("${PREFIX_EXPORTS[@]}")
  else
    mapfile -t _shells < <(shell__detect_installed_shells)
  fi
  local -a _sc_args=()
  local _sh
  for _sh in "${_shells[@]}"; do
    case "$_sh" in
      bash | zsh) _sc_args+=("--${_sh}-content" "export MANPATH=\"${_manpath_dir}:\${MANPATH}\"" "--${_sh}-everywhere") ;;
      fish) _sc_args+=("--fish-content" "set -gx MANPATH \"${_manpath_dir}\" \$MANPATH" "--fish-everywhere") ;;
      tcsh) _sc_args+=("--tcsh-content" "setenv MANPATH \"${_manpath_dir}:\${MANPATH}\"" "--tcsh-everywhere") ;;
    esac
  done
  [[ "${#_sc_args[@]}" -gt 0 ]] && shell__sync_config \
    --marker "git MANPATH (install-git)" \
    --scope "${_scope}" \
    --home "${_home}" \
    --profile-d "${_FEAT_PROFILE_D_FILE}" \
    "${_sc_args[@]}"
}

# ── Per-user configuration ─────────────────────────────────────────────────

__configure_user() {
  local _user="$1"
  local _current_user
  _current_user="$(users__get_current --no-sudo)"

  if users__is_user_path "${_RESOLVED_PREFIX}" && [[ "${_user}" != "${_current_user}" ]]; then
    logging__warn "User-local mode: skipping gitconfig for '${_user}' (can only write for current user)."
    return 0
  fi

  local _home _cfg
  _home="$(users__resolve_home "${_user}")" || {
    logging__warn "Could not resolve home directory for '${_user}' — skipping."
    return 0
  }
  _cfg="${_home}/.gitconfig"

  local _content=""
  if [[ -n "${USER_NAME}" || -n "${USER_EMAIL}" ]]; then
    _content+="[user]"$'\n'
    [[ -n "${USER_NAME}" ]] && _content+=$'\t'"name = ${USER_NAME}"$'\n'
    [[ -n "${USER_EMAIL}" ]] && _content+=$'\t'"email = ${USER_EMAIL}"$'\n'
  fi
  if [[ -n "${USER_GITCONFIG}" ]]; then
    _content+="${USER_GITCONFIG}"$'\n'
  fi
  if [[ -n "${_content}" ]]; then
    shell__sync_block --files "${_cfg}" --marker "user gitconfig (install-git)" --content "${_content}"
    file__chown "${_user}:${_user}" "${_cfg}" 2> /dev/null || true
    logging__success "Wrote gitconfig for user '${_user}'."
  fi
}

__install_finish_post() {
  if [[ -n "${DEFAULT_BRANCH:-}${SYSTEM_GITCONFIG:-}" ]] || [[ "${#SAFE_DIRECTORY[@]}" -gt 0 ]]; then
    _git__write_system_gitconfig
  fi
  _export_git_manpath
  if [[ -n "${USER_NAME:-}${USER_EMAIL:-}${USER_GITCONFIG:-}" ]]; then
    __feat_do_configure_users__
  fi
}

# shellcheck disable=SC2329,SC2317
__uninstall_finish_post() {
  # 1. Remove MANPATH export block written by _export_git_manpath.
  local _scope
  _scope="$(users__is_user_path "${_RESOLVED_PREFIX}" && printf user || printf system)"
  shell__sync_config \
    --scope "${_scope}" \
    --home "$(users__home_of_path_owner "${_RESOLVED_PREFIX}")" \
    --marker "git MANPATH (install-git)" \
    --profile-d "${_FEAT_PROFILE_D_FILE}" \
    bash zsh fish tcsh elvish

  # 2. Remove system gitconfig block written by _git__write_system_gitconfig.
  local _cfg
  if ! users__is_user_path "${_RESOLVED_PREFIX}"; then
    _cfg="${SYSCONFDIR}/gitconfig"
  else
    _cfg="$(users__home_of_path_owner "${_RESOLVED_PREFIX}")/.config/git/config"
  fi
  shell__sync_block --files "${_cfg}" --marker "system gitconfig (install-git)"

  # 3. Remove per-user gitconfig blocks written by __configure_user.
  local -a _ul_args=()
  [[ -v ADD_CURRENT_USER ]] && _ul_args+=(--current "${ADD_CURRENT_USER}")
  [[ -v ADD_REMOTE_USER ]] && _ul_args+=(--remote "${ADD_REMOTE_USER}")
  [[ -v ADD_CONTAINER_USER ]] && _ul_args+=(--container "${ADD_CONTAINER_USER}")
  if [[ -v ADD_USERS ]]; then
    for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do _ul_args+=(--user "${_u}"); done
  fi
  local -a _users=()
  mapfile -t _users < <(users__resolve_list "${_ul_args[@]}")
  local _user _uhome
  for _user in "${_users[@]+"${_users[@]}"}"; do
    _uhome="$(users__resolve_home "${_user}")" || continue
    shell__sync_block --files "${_uhome}/.gitconfig" --marker "user gitconfig (install-git)"
  done
}
