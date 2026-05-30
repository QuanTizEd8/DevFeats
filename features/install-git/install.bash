# shellcheck shell=bash

# ── Method / prefix resolution ─────────────────────────────────────────────

__resolve_method() {
  # On Ubuntu, prefer the git-core PPA (upstream-package) for a newer git.
  # Everywhere else, fall back to the OS package manager.
  if [[ "$(os__id)" == "ubuntu" ]]; then
    printf 'upstream-package\n'
  else
    printf 'package\n'
  fi
}

__resolve_input_prefixes_post() {
  # Resolve SYSCONFDIR after PREFIX is known.  __install_run_source_build passes
  # it to make as sysconfdir=; _git__write_system_gitconfig uses it to locate gitconfig.
  if [[ "${SYSCONFDIR}" == "auto" ]]; then
    if users__is_user_path "${PREFIX}"; then
      SYSCONFDIR="$(users__home_of_path_owner "${PREFIX}")/.config"
    else
      SYSCONFDIR="/etc"
    fi
  fi
}

# ── Package method overrides ───────────────────────────────────────────────

__install_run_package__() {
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
  file__mkdir "${PREFIX}" || {
    logging__error "PREFIX '${PREFIX}' could not be created (check privilege)."
    return 1
  }
  if users__is_user_path "${PREFIX}" && [[ ! -w "${PREFIX}" ]]; then
    logging__error "PREFIX '${PREFIX}' is not writable."
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
  if ! users__is_user_path "${PREFIX}"; then
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
  local _git_make_flags="prefix=${PREFIX} sysconfdir=${SYSCONFDIR} USE_LIBPCRE2=YesPlease"

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
    cd "${_src_dir}" || exit 1
    # shellcheck disable=SC2086
    make -s -j"${_ncpus}" ${_git_make_flags} "${_extra_make_flags[@]+"${_extra_make_flags[@]}"}" all
    # shellcheck disable=SC2086
    make -s ${_git_make_flags} "${_extra_make_flags[@]+"${_extra_make_flags[@]}"}" install
  ) || return 1

  # `make install` does not install contrib/completion scripts.  Copy them
  # from the source tree to the prefix now, before the build dir is cleaned.
  local _comp_src_dir="${_src_dir}/contrib/completion"
  local _comp_dst_dir="${PREFIX}/share/git-core/contrib/completion"
  if [[ -d "${_comp_src_dir}" ]]; then
    file__mkdir "${_comp_dst_dir}"
    file__cp "${_comp_src_dir}/"*.bash "${_comp_dst_dir}/" 2> /dev/null || true
    file__cp "${_comp_src_dir}/"*.zsh "${_comp_dst_dir}/" 2> /dev/null || true
  fi

  "${PREFIX}/bin/git" --version
  logging__success "git ${VERSION} installed to ${PREFIX}/bin/git."
}

# ── Uninstall ──────────────────────────────────────────────────────────────

__uninstall_run_prefix_post() {
  # __uninstall_run_prefix__ removes only the primary binary.  A source build
  # scatters additional files; clean them up here.
  # _FEAT_EXISTING_PATH is still set — it is cleared by __uninstall_finish__
  # which runs after __uninstall_run__ completes.
  local _prefix
  _prefix="${_FEAT_EXISTING_PATH%/bin/git}"
  [[ -n "${_prefix}" && "${_prefix}" != "/" ]] || return 0
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
  if ! users__is_user_path "${PREFIX}"; then
    _cfg="${SYSCONFDIR}/gitconfig"
  else
    _cfg="$(users__home_of_path_owner "${PREFIX}")/.config/git/config"
  fi
  file__mkdir "$(dirname "${_cfg}")"

  # Prefer the installed binary (handles source builds at non-standard prefixes
  # where ${PREFIX}/bin is not yet on PATH); fall back to the system git.
  local _git
  if command -v "${PREFIX}/bin/git" > /dev/null 2>&1; then
    _git="${PREFIX}/bin/git"
  else
    _git="git"
  fi

  if ! users__is_user_path "${PREFIX}"; then
    _run_cfg() { users__run_privileged "$@"; }
  else
    _run_cfg() { "$@"; }
  fi

  if [[ -n "${DEFAULT_BRANCH}" ]]; then
    _run_cfg "${_git}" config --file "${_cfg}" init.defaultBranch "${DEFAULT_BRANCH}"
  fi

  if [[ "${#SAFE_DIRECTORY[@]}" -gt 0 ]]; then
    local _entry
    for _entry in "${SAFE_DIRECTORY[@]}"; do
      _run_cfg "${_git}" config --file "${_cfg}" --add safe.directory "${_entry}"
    done
  fi

  if [[ -n "${SYSTEM_GITCONFIG}" ]]; then
    printf '%s\n' "${SYSTEM_GITCONFIG}" | file__tee --append "${_cfg}"
  fi
}

_export_git_manpath() {
  logging__fn_entry "_export_git_manpath"
  if [[ "${METHOD}" != "source" ]]; then
    logging__fn_exit "_export_git_manpath"
    return 0
  fi
  case "${PREFIX_DISCOVERY:-auto}" in
    none | symlink)
      logging__fn_exit "_export_git_manpath"
      return 0
      ;;
  esac
  local _manpath_export_opt
  if [[ "${#PREFIX_EXPORTS[@]}" -eq 0 ]]; then
    _manpath_export_opt="auto"
  else
    _manpath_export_opt="$(printf '%s\n' "${PREFIX_EXPORTS[@]}")"
  fi
  if [[ "${PREFIX}" == "/usr/local" || "${PREFIX}" == "${HOME}/.local" ]]; then
    logging__fn_exit "_export_git_manpath"
    return 0
  fi
  shell__write_env_block \
    --scope "$(users__is_user_path "${PREFIX}" && printf user || printf system)" \
    --home "$(users__home_of_path_owner "${PREFIX}")" \
    --opt "${_manpath_export_opt}" \
    --profile-d "${_FEAT_PROFILE_D_FILE}" \
    --marker "git MANPATH (install-git)" \
    --content "export MANPATH=\"${PREFIX}/share/man:\${MANPATH}\""
  logging__fn_exit "_export_git_manpath"
}

# ── Per-user configuration ─────────────────────────────────────────────────

__configure_user() {
  local _user="$1"
  local _current_user
  _current_user="$(users__get_current --no-sudo)"

  if users__is_user_path "${PREFIX}" && [[ "${_user}" != "${_current_user}" ]]; then
    logging__warn "User-local mode: skipping gitconfig for '${_user}' (can only write for current user)."
    return 0
  fi

  local _home _cfg
  _home="$(users__resolve_home "${_user}")" || {
    logging__warn "Could not resolve home directory for '${_user}' — skipping."
    return 0
  }
  _cfg="${_home}/.gitconfig"

  local _git
  if command -v "${PREFIX}/bin/git" > /dev/null 2>&1; then
    _git="${PREFIX}/bin/git"
  else
    _git="git"
  fi

  if [[ "${_user}" == "${_current_user}" ]]; then
    [[ -n "${USER_NAME}" ]] && "${_git}" config --file "${_cfg}" user.name "${USER_NAME}"
    [[ -n "${USER_EMAIL}" ]] && "${_git}" config --file "${_cfg}" user.email "${USER_EMAIL}"
  else
    [[ -n "${USER_NAME}" ]] && users__run_privileged "${_git}" config --file "${_cfg}" user.name "${USER_NAME}"
    [[ -n "${USER_EMAIL}" ]] && users__run_privileged "${_git}" config --file "${_cfg}" user.email "${USER_EMAIL}"
  fi
  [[ -n "${USER_GITCONFIG}" ]] && printf '%s\n' "${USER_GITCONFIG}" | file__tee --append "${_cfg}"
  file__chown "${_user}:${_user}" "${_cfg}" 2> /dev/null || true
  logging__success "Wrote gitconfig for user '${_user}'."
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
