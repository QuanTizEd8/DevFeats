# ── Helper functions ──────────────────────────────────────────────────────────

# _git__check_exists
# Checks whether git is already in PATH and applies the $IF_EXISTS policy.
# Exits 0 (skip) or 1 (fail) when appropriate; returns normally to continue.
# Contract: if the installed version exactly matches the resolved target, we
# always exit 0 regardless of if_exists.
_git__check_exists() {
  command -v git > /dev/null 2>&1 || return 0

  local _installed_ver
  _installed_ver="$(git --version 2> /dev/null | sed 's/^git version //')"

  # Same-version idempotency: always skip when installed == target, regardless
  # of if_exists.  For source, resolve best-effort (|| true) so an offline
  # container with git already present does not abort during skip/fail.
  local _resolved_ver=""
  if [ "${METHOD}" = "source" ]; then
    _resolved_ver="$(_git__source_resolve_version)" || true
  elif [ "${METHOD}" = "package" ] &&
    [ "${VERSION}" != "latest" ] && [ "${VERSION}" != "stable" ]; then
    _resolved_ver="${VERSION}"
  fi
  if [ -n "${_resolved_ver}" ] && [ "${_installed_ver}" = "${_resolved_ver}" ]; then
    logging__info "git ${_resolved_ver} is already installed — skipping."
    exit 0
  fi

  # Apply if_exists policy.
  case "${IF_EXISTS}" in
    skip)
      logging__info "git is already installed (${_installed_ver}) — skipping (if_exists=skip)."
      exit 0
      ;;
    fail)
      logging__error "git is already installed (${_installed_ver}) and if_exists=fail."
      exit 1
      ;;
    reinstall)
      local _existing_method _old_prefix
      _existing_method="$(_git__detect_install_method)"
      if [ "${_existing_method}" = "source" ]; then
        _old_prefix="$(dirname "$(dirname "$(command -v git)")")"
        _git__reinstall "source" "${_old_prefix}"
      else
        _git__reinstall "${_existing_method}"
      fi
      ;;
    update)
      local _existing_method
      _existing_method="$(_git__detect_install_method)"
      if [ "${_existing_method}" != "${METHOD}" ]; then
        _git__reinstall "${_existing_method}"
      elif [ "${METHOD}" = "source" ]; then
        local _old_prefix
        _old_prefix="$(dirname "$(dirname "$(command -v git)")")"
        if [ "${_old_prefix}" != "${PREFIX}" ]; then
          _git__reinstall "source" "${_old_prefix}"
        fi
        # Same prefix: make install overwrites in place — no teardown needed.
      fi
      # package→package: package manager handles upgrade natively.
      ;;
    *)
      logging__error "Unknown if_exists value: '${IF_EXISTS}'"
      exit 1
      ;;
  esac
  return 0
}

# _git__detect_install_method
# Detects whether the currently installed git was installed by the OS package
# manager or built from source. Prints "package" or "source" to stdout.
_git__detect_install_method() {
  local _git_bin
  _git_bin="$(command -v git)"
  case "$(os__platform)" in
    debian)
      dpkg -S "${_git_bin}" > /dev/null 2>&1 && echo "package" && return 0
      ;;
    alpine)
      apk info --who-owns "${_git_bin}" 2> /dev/null | grep -q 'owned by' &&
        echo "package" && return 0
      ;;
    rhel)
      rpm -qf "${_git_bin}" > /dev/null 2>&1 && echo "package" && return 0
      ;;
    suse)
      rpm -qf "${_git_bin}" > /dev/null 2>&1 && echo "package" && return 0
      ;;
    macos)
      brew list git > /dev/null 2>&1 && echo "package" && return 0
      ;;
  esac
  echo "source"
  return 0
}

# _git__reinstall
# Removes the existing git installation to prepare for a clean reinstall.
# $1 = existing_method ("package" or "source")
# $2 = prefix_to_remove (optional; defaults to $PREFIX)
_git__reinstall() {
  local _existing_method="$1"
  local _remove_prefix="${2:-${PREFIX}}"

  if [ "${_existing_method}" = "package" ]; then
    logging__remove "Removing package-managed git..."
    case "$(os__platform)" in
      debian) users__run_privileged apt-get remove -y git ;;
      alpine) users__run_privileged apk del git ;;
      rhel) users__run_privileged dnf remove -y git 2> /dev/null || users__run_privileged yum remove -y git ;;
      suse) users__run_privileged zypper remove -y git ;;
      macos) brew remove git ;;
    esac
  else
    logging__remove "Removing source-installed git from ${_remove_prefix}..."
    rm -f "${_remove_prefix}/bin/git" "${_remove_prefix}/bin/git-"*
    rm -rf "${_remove_prefix}/lib/git-core/"
    rm -rf "${_remove_prefix}/share/git-core/"
    rm -f "${_remove_prefix}/share/man/man1/git"* \
      "${_remove_prefix}/share/man/man5/git"* \
      "${_remove_prefix}/share/man/man7/git"*
    # Remove equivs dummy package on Debian/Ubuntu if registered.
    case "$(os__platform)" in
      debian)
        if dpkg -s git 2> /dev/null | grep -q 'Status: install ok installed'; then
          users__run_privileged apt-get purge -y git || true
        fi
        ;;
    esac
  fi
  return 0
}

# _git__install_package
# Installs git via the OS package manager.
_git__install_package() {
  if [ "${VERSION}" = "latest" ] && [ "$(os__id)" = "ubuntu" ]; then
    # On Ubuntu + apt, install git from ppa:git-core/ppa (latest upstream git).
    # The ppa manifest group has when: {id: ubuntu, pm: apt}, so it is a no-op
    # on any other platform that might reach this branch.
    _dep_install_runtime_ppa
    return 0
  fi

  if [ "${VERSION}" != "latest" ] && [ "${VERSION}" != "stable" ]; then
    # Specific version: pass directly to ospkg.
    # shellcheck disable=SC2059
    ospkg__run --manifest "$(printf 'packages:\n  - name: git\n    version: "%s"\n' "${VERSION}")"
  else
    _dep_install_runtime_os_pkg
  fi
  return 0
}

# _git__source_resolve_version
# Resolves $VERSION to an exact version string (no "v" prefix, e.g. "2.47.2").
# Prints the resolved version to stdout.
_git__source_resolve_version() {
  local _tags _tag
  if [ "${VERSION}" = "latest" ]; then
    _tags="$(github__tags "${GH_REPO}")" || {
      logging__error "Failed to fetch git tags from GitHub."
      return 1
    }
    _tag="$(printf '%s\n' "${_tags}" |
      sed 's/^v//' |
      grep -E '^[0-9]+\.[0-9]+' |
      sort -t. -k1,1n -k2,2n -k3,3n |
      tail -1)"
  elif [ "${VERSION}" = "stable" ]; then
    _tags="$(github__tags "${GH_REPO}")" || {
      logging__error "Failed to fetch git tags from GitHub."
      return 1
    }
    _tag="$(printf '%s\n' "${_tags}" |
      sed 's/^v//' |
      grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
      sort -t. -k1,1n -k2,2n -k3,3n |
      tail -1)"
  else
    _tag="${VERSION}"
  fi

  if [ -z "${_tag}" ]; then
    logging__error "Could not resolve a git version from tags."
    return 1
  fi
  echo "${_tag}"
  return 0
}

# _git__source_fetch_verify
# Downloads the tarball and sha256sums.asc, verifies the checksum.
# $1 = resolved version string (e.g. "2.47.2")
_git__source_fetch_verify() {
  local _ver="$1"
  local _tar_url="https://www.kernel.org/pub/software/scm/git/git-${_ver}.tar.gz"
  local _sum_url="https://www.kernel.org/pub/software/scm/git/sha256sums.asc"

  mkdir -p "${INSTALLER_DIR}"
  uri__fetch_asset "${_tar_url}" \
    --sidecar "${_sum_url}" \
    --installer-dir "${INSTALLER_DIR}"
}

# _git__source_build
# Compiles and installs git from source.
# $1 = resolved version string
_git__source_build() {
  local _ver="$1"
  local _make_flags="prefix=${PREFIX} sysconfdir=${SYSCONFDIR} USE_LIBPCRE2=YesPlease"

  # Alpine requires these extra flags.
  if [ "$(os__platform)" = "alpine" ]; then
    _make_flags="${_make_flags} NO_GETTEXT=YesPlease NO_REGEX=YesPlease NO_SVN_TESTS=YesPlease NO_SYS_POLL_H=1"
  fi

  # Parse NO_FLAGS: space/comma-separated keywords → NO_<FLAG>=YesPlease.
  local _user_flags
  _user_flags="$(printf '%s' "${NO_FLAGS[*]}" | tr '[:lower:],' '[:upper:] ')"
  local _flag
  for _flag in ${_user_flags}; do
    case "${_flag}" in
      PERL | PYTHON | TCLTK | GETTEXT)
        case " ${_make_flags} " in
          *" NO_${_flag}="*) ;;
          *) _make_flags="${_make_flags} NO_${_flag}=YesPlease" ;;
        esac
        ;;
      '') ;;
      *)
        logging__warn "no_flags: unknown keyword '${_flag}' — ignored"
        ;;
    esac
  done

  local _ncpus
  _ncpus="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 1)"

  cd "${INSTALLER_DIR}/asset/git-${_ver}"
  # shellcheck disable=SC2086
  make -s -j"${_ncpus}" ${_make_flags} ${MAKE_FLAGS} all
  # shellcheck disable=SC2086
  make -s ${_make_flags} ${MAKE_FLAGS} install

  # `make install` does not install contrib/completion scripts. Copy them
  # from the source tree to the prefix now, before the build dir is cleaned.
  local _comp_src_dir="${INSTALLER_DIR}/asset/git-${_ver}/contrib/completion"
  local _comp_dst_dir="${PREFIX}/share/git-core/contrib/completion"
  if [ -d "${_comp_src_dir}" ]; then
    file__mkdir "${_comp_dst_dir}"
    file__cp "${_comp_src_dir}/"*.bash "${_comp_dst_dir}/" 2> /dev/null || true
    file__cp "${_comp_src_dir}/"*.zsh "${_comp_dst_dir}/" 2> /dev/null || true
  fi

  cd /
  return 0
}

# _git__source_register
# Registers the source-built git with apt on Debian/Ubuntu via an equivs dummy
# package so dependency resolution sees git as satisfied.  Non-fatal.
# $1 = resolved version string
_git__source_register() {
  local _ver="$1"
  # User-local installs cannot register packages via apt/dpkg.
  if users__is_user_path "${PREFIX}"; then
    logging__info "User-local mode: skipping package manager registration for source-built git."
    return 0
  fi
  case "$(os__platform)" in
    debian) ;;
    *) return 0 ;;
  esac

  local _tmpdir
  _tmpdir="$(mktemp -d)"

  cat > "${_tmpdir}/git.control" << EOF
Section: misc
Priority: optional
Standards-Version: 3.9.2

Package: git
Version: ${_ver}-equivs
Maintainer: install-git-feature
Description: Dummy package — git built from source
EOF

  (
    cd "${_tmpdir}"
    users__run_privileged equivs-build ./git.control
    users__run_privileged dpkg -i ./git_*.deb
  ) || {
    logging__warn "equivs dummy package installation failed — skipping registration."
    rm -rf "${_tmpdir}"
    return 0
  }

  rm -rf "${_tmpdir}"
  logging__success "Registered git ${_ver} with apt via equivs dummy package."
  return 0
}

# _git__install_source
# Main source-build orchestrator (10 steps).
_git__install_source() {
  # 1. Validate prefix writeability.
  file__mkdir "${PREFIX}" || {
    logging__error "PREFIX '${PREFIX}' could not be created (check privilege)."
    return 1
  }
  if users__is_user_path "${PREFIX}" && [ ! -w "${PREFIX}" ]; then
    logging__error "PREFIX '${PREFIX}' is not writable."
    return 1
  fi

  # 2. Resolve version.
  local _resolved_ver
  _resolved_ver="$(_git__source_resolve_version)"

  # 4. Check Xcode CLT on macOS.
  if [ "$(os__kernel)" = "Darwin" ]; then
    xcode-select --print-path > /dev/null 2>&1 || {
      logging__error "Xcode Command Line Tools are required for source builds on macOS."
      logging__info "Install with: xcode-select --install"
      return 1
    }
  fi

  # 5. Install build dependencies.
  # User-local installs cannot invoke the OS package manager; assume deps were
  # preinstalled by the caller (e.g. Linux non-root test setup).
  if ! users__is_user_path "${PREFIX}"; then
    _dep_install_buildtime_source_build
  else
    logging__info "User-local mode: skipping build dependency installation; expecting required packages to be preinstalled."
  fi

  # 6. Download, verify, and extract tarball.
  _git__source_fetch_verify "${_resolved_ver}"

  # 7. Build and install.
  logging__build "Building git ${_resolved_ver}..."
  _git__source_build "${_resolved_ver}"

  # 9. Register with package manager (Debian/Ubuntu only, non-fatal).
  _git__source_register "${_resolved_ver}"

  # 10. Verify.
  "${PREFIX}/bin/git" --version
  logging__success "git ${_resolved_ver} installed to ${PREFIX}/bin/git."
  return 0
}

# _git__write_system_gitconfig
# Writes system-level gitconfig settings (init.defaultBranch, safe.directory,
# and any raw ini lines from $SYSTEM_GITCONFIG).
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

  if [ -n "${DEFAULT_BRANCH}" ]; then
    _run_cfg "${_git}" config --file "${_cfg}" init.defaultBranch "${DEFAULT_BRANCH}"
  fi

  if [ "${#SAFE_DIRECTORY[@]}" -gt 0 ]; then
    local _entry
    for _entry in "${SAFE_DIRECTORY[@]}"; do
      _run_cfg "${_git}" config --file "${_cfg}" --add safe.directory "${_entry}"
    done
  fi

  if [ -n "${SYSTEM_GITCONFIG}" ]; then
    printf '%s\n' "${SYSTEM_GITCONFIG}" | file__tee --append "${_cfg}"
  fi
  return 0
}

# _git__write_user_gitconfig
# Writes per-user gitconfig settings (user.name, user.email, raw ini lines)
# for each resolved user.
_git__write_user_gitconfig() {
  local _current_user
  _current_user="$(users__get_current --no-sudo)"
  local _user _home _cfg

  local -a _gu_args=()
  [ "${ADD_CURRENT_USER:-true}" != "true" ] && _gu_args+=(--current false)
  [ "${ADD_REMOTE_USER:-true}" != "true" ] && _gu_args+=(--remote false)
  [ "${ADD_CONTAINER_USER:-true}" != "true" ] && _gu_args+=(--container false)
  for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do [ -n "$_u" ] && _gu_args+=(--user "$_u"); done

  while IFS= read -r _user; do
    [ -z "${_user}" ] && continue
    # User-local scope: only write to the invoking user's config.
    if users__is_user_path "${PREFIX}" && [ "${_user}" != "${_current_user}" ]; then
      logging__warn "User-local mode: skipping gitconfig for '${_user}' (can only write for '${_current_user}')."
      continue
    fi

    _home="$(users__resolve_home "${_user}")" || {
      logging__warn "Could not resolve home directory for '${_user}' — skipping."
      continue
    }
    _cfg="${_home}/.gitconfig"

    # Prefer the installed binary (handles source builds at non-standard prefixes).
    local _git
    if command -v "${PREFIX}/bin/git" > /dev/null 2>&1; then
      _git="${PREFIX}/bin/git"
    else
      _git="git"
    fi

    if [ "${_user}" = "$(users__get_current --no-sudo)" ]; then
      [ -n "${USER_NAME}" ] && "${_git}" config --file "${_cfg}" user.name "${USER_NAME}"
      [ -n "${USER_EMAIL}" ] && "${_git}" config --file "${_cfg}" user.email "${USER_EMAIL}"
    else
      [ -n "${USER_NAME}" ] && users__run_privileged "${_git}" config --file "${_cfg}" user.name "${USER_NAME}"
      [ -n "${USER_EMAIL}" ] && users__run_privileged "${_git}" config --file "${_cfg}" user.email "${USER_EMAIL}"
    fi
    [ -n "${USER_GITCONFIG}" ] && printf '%s\n' "${USER_GITCONFIG}" | file__tee --append "${_cfg}"

    # Fix ownership when writing to another user's file.
    file__chown "${_user}:${_user}" "${_cfg}" 2> /dev/null || true
    logging__success "Wrote gitconfig for user '${_user}'."
  done < <(users__resolve_list "${_gu_args[@]}")
  return 0
}

_export_git_manpath() {
  logging__fn_entry "_export_git_manpath"
  if [ "${METHOD}" != "source" ]; then
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
  if [ "${#PREFIX_EXPORTS[@]}" -eq 0 ]; then
    _manpath_export_opt="auto"
  else
    _manpath_export_opt="$(printf '%s\n' "${PREFIX_EXPORTS[@]}")"
  fi
  if [ "${PREFIX}" = "/usr/local" ] || [ "${PREFIX}" = "${HOME}/.local" ]; then
    logging__fn_exit "_export_git_manpath"
    return 0
  fi
  shell__write_env_block \
    --scope "$(users__is_user_path "${PREFIX}" && printf user || printf system)" \
    --home "$(users__home_of_path_owner "${PREFIX}")" \
    --opt "${_manpath_export_opt}" \
    --profile-d "${_SHELL_PROFILE_D_FILENAME}" \
    --marker "git MANPATH (install-git)" \
    --content "export MANPATH=\"${PREFIX}/share/man:\${MANPATH}\""
  logging__fn_exit "_export_git_manpath"
  return
}

_prefix_post_install() {
  _prefix_post_install__generated
  _export_git_manpath
}

# ── Top-level dispatch ────────────────────────────────────────────────────────

# 1. Resolve prefix/sysconfdir.
if [ "${SYSCONFDIR}" = "auto" ]; then
  users__is_user_path "${PREFIX}" && SYSCONFDIR="$(users__home_of_path_owner "${PREFIX}")/.config" || SYSCONFDIR="/etc"
fi

# 2. if_exists gate.
_git__check_exists

# 4. Install.
case "${METHOD}" in
  package) _git__install_package ;;
  source) _git__install_source ;;
  *)
    logging__error "Unknown method: '${METHOD}'"
    exit 1
    ;;
esac

# 5. Shell completions (source build only).
if [ "${METHOD}" = "source" ] && [ "${#SHELL_COMPLETIONS[@]}" -gt 0 ]; then
  _comp_src="${PREFIX}/share/git-core/contrib/completion"
  if [ ! -d "${_comp_src}" ]; then
    logging__info "Completion scripts not found at '${_comp_src}' — skipping."
  else
    for _shell in "${SHELL_COMPLETIONS[@]}"; do
      case "${_shell}" in
        bash)
          if ! users__is_user_path "${PREFIX}"; then
            file__mkdir /etc/bash_completion.d
            file__cp "${_comp_src}/git-completion.bash" /etc/bash_completion.d/git
            logging__success "Bash completion written to /etc/bash_completion.d/git"
          else
            _uhome="$(users__home_of_path_owner "${PREFIX}")"
            file__mkdir "${_uhome}/.local/share/bash-completion/completions"
            cp "${_comp_src}/git-completion.bash" \
              "${_uhome}/.local/share/bash-completion/completions/git"
            logging__success "Bash completion written to ${_uhome}/.local/share/bash-completion/completions/git"
          fi
          ;;
        zsh)
          if ! users__is_user_path "${PREFIX}"; then
            _zshdir="$(shell__detect_zshdir)"
            file__mkdir "${_zshdir}/completions"
            file__cp "${_comp_src}/git-completion.zsh" "${_zshdir}/completions/_git"
            logging__success "Zsh completion written to ${_zshdir}/completions/_git"
          else
            _uhome="$(users__home_of_path_owner "${PREFIX}")"
            file__mkdir "${_uhome}/.zfunc"
            cp "${_comp_src}/git-completion.zsh" "${_uhome}/.zfunc/_git"
            logging__success "Zsh completion written to ${_uhome}/.zfunc/_git"
          fi
          ;;
        *)
          logging__error "Unsupported shell: '${_shell}' (expected: bash, zsh)"
          exit 1
          ;;
      esac
    done
  fi
fi

# 7. Git configuration.
if [ -n "${DEFAULT_BRANCH}${SYSTEM_GITCONFIG}" ] || [ "${#SAFE_DIRECTORY[@]}" -gt 0 ]; then
  _git__write_system_gitconfig
fi
if { [ "${ADD_CURRENT_USER}" = "true" ] || [ "${ADD_REMOTE_USER}" = "true" ] || [ "${ADD_CONTAINER_USER}" = "true" ] || [ "${#ADD_USERS[@]}" -gt 0 ]; } && [ -n "${USER_NAME}${USER_EMAIL}${USER_GITCONFIG}" ]; then
  _git__write_user_gitconfig
fi
