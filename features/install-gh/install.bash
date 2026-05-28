# _gh__resolve_version — prints the resolved semver (no "v" prefix) to stdout.
_gh__resolve_version() {
  logging__fn_entry "_gh__resolve_version"
  local _spec="$VERSION"
  local _out
  _out="$(github__resolve_version "${GH_REPO}" "$_spec")" || {
    logging__error "Failed to resolve gh version from GitHub."
    exit 1
  }
  local _ver="${_out#*$'\n'}"
  logging__info "Resolved version '${_ver}'"
  printf '%s\n' "$_ver"
  logging__fn_exit "_gh__resolve_version"
}

# _gh__check_existing — applies IF_EXISTS policy; exits or returns normally.
# $1 = resolved version string (e.g. "2.89.0")
_gh__check_existing() {
  logging__fn_entry "_gh__check_existing"
  command -v gh > /dev/null 2>&1 || {
    logging__fn_exit "_gh__check_existing (gh not found)"
    return 0
  }

  local _installed_ver
  _installed_ver="$(gh --version 2> /dev/null | head -1 | awk '{print $3}')" || _installed_ver=""

  # Same-version idempotency: always exit 0 regardless of if_exists.
  if [ -n "${_installed_ver}" ] && [ "${_installed_ver}" = "${1}" ]; then
    logging__info "gh ${1} is already installed — skipping (version match)."
    exit 0
  fi

  case "${IF_EXISTS}" in
    skip)
      logging__info "gh is already installed (${_installed_ver}) — skipping (if_exists=skip)."
      exit 0
      ;;
    fail)
      logging__error "gh is already installed (${_installed_ver}) and if_exists=fail."
      exit 1
      ;;
  esac
  logging__fn_exit "_gh__check_existing"
  return 0
}

# _gh__install_repos — dispatch to the correct platform-specific repos installer.
_gh__install_repos() {
  logging__fn_entry "_gh__install_repos"
  local _id _id_like _platform
  _id="$(os__id)"
  _id_like="$(os__id_like)"
  _platform="$(os__platform)"

  # Arch Linux has ID=arch (and Manjaro has ID_LIKE containing arch).
  case "${_id}" in
    arch | manjaro)
      # github-cli is available from the official Arch repos; no extra repo setup needed.
      if [[ "${VERSION}" != "latest" && "${VERSION}" != "stable" ]]; then
        logging__warn "Version pinning is not supported for method=upstream-package on Arch. Installing latest available github-cli."
      fi
      ospkg__install_user github-cli
      logging__fn_exit "_gh__install_repos"
      return 0
      ;;
  esac
  case "${_id_like}" in
    *arch*)
      if [[ "${VERSION}" != "latest" && "${VERSION}" != "stable" ]]; then
        logging__warn "Version pinning is not supported for method=upstream-package on Arch. Installing latest available github-cli."
      fi
      ospkg__install_user github-cli
      logging__fn_exit "_gh__install_repos"
      return 0
      ;;
  esac

  case "${_platform}" in
    alpine)
      _gh__repos_alpine
      ;;
    debian)
      # Set up GitHub CLI APT signing key and repo via the repos-debian manifest group,
      # which also triggers apt-get update. Then install gh (with optional version pin).
      __dep_install__ run repos-debian
      if [[ "${VERSION}" = "latest" || "${VERSION}" = "stable" ]]; then
        ospkg__install_user gh
      else
        ospkg__install_user "gh=${VERSION}"
      fi
      ;;
    rhel)
      _gh__repos_rhel
      ;;
    suse)
      _gh__repos_rhel
      ;;
    macos)
      _gh__repos_macos
      ;;
    *)
      logging__error "Unsupported platform '${_platform}' for method=upstream-package."
      exit 1
      ;;
  esac
  logging__fn_exit "_gh__install_repos"
  return 0
}

# _gh__repos_rhel — add GitHub CLI rpm repo and install gh.
_gh__repos_rhel() {
  logging__fn_entry "_gh__repos_rhel"
  local _tmp_repo
  if [[ "${VERSION}" != "latest" && "${VERSION}" != "stable" ]]; then
    logging__warn "Version pinning is not supported for method=upstream-package on RHEL-based systems. Installing latest available gh."
  fi
  if command -v zypper > /dev/null 2>&1; then
    # Drop the .repo file directly so zypper parses baseurl from it.
    # 'zypper addrepo <URL>' treats the URL as the baseurl directly; when the
    # URL ends in .repo the fetched metadata path becomes wrong (.repo/repodata/).
    file__mkdir /etc/zypp/repos.d
    _tmp_repo="$(mktemp)"
    net__fetch_url_file \
      "https://cli.github.com/packages/rpm/gh-cli.repo" \
      "${_tmp_repo}"
    file__cp "${_tmp_repo}" "/etc/zypp/repos.d/gh-cli.repo"
    rm -f "${_tmp_repo}"
    users__run_privileged zypper --gpg-auto-import-keys ref gh-cli
    # zypper exits 6 ("INFO_REPOS_SKIPPED") when system update repos have stale
    # metadata in containers. Treat exit 6 as success — gh is still installed.
    users__run_privileged zypper install -y gh || {
      _rc=$?
      [ "${_rc}" -eq 6 ] || exit "${_rc}"
    }
  elif command -v dnf > /dev/null 2>&1; then
    file__mkdir /etc/yum.repos.d
    _tmp_repo="$(mktemp)"
    net__fetch_url_file \
      "https://cli.github.com/packages/rpm/gh-cli.repo" \
      "${_tmp_repo}"
    file__cp "${_tmp_repo}" "/etc/yum.repos.d/gh-cli.repo"
    rm -f "${_tmp_repo}"
    users__run_privileged dnf install -y gh
  elif command -v yum > /dev/null 2>&1; then
    file__mkdir /etc/yum.repos.d
    _tmp_repo="$(mktemp)"
    net__fetch_url_file \
      "https://cli.github.com/packages/rpm/gh-cli.repo" \
      "${_tmp_repo}"
    file__cp "${_tmp_repo}" "/etc/yum.repos.d/gh-cli.repo"
    rm -f "${_tmp_repo}"
    users__run_privileged yum install -y gh
  else
    logging__error "No supported package manager found for RHEL-based system."
    exit 1
  fi
  logging__fn_exit "_gh__repos_rhel"
  return 0
}

# _gh__repos_alpine — install github-cli via apk community package.
_gh__repos_alpine() {
  logging__fn_entry "_gh__repos_alpine"
  if [[ "${VERSION}" != "latest" && "${VERSION}" != "stable" ]]; then
    logging__warn "Version pinning is not supported for method=upstream-package on Alpine. Installing latest available github-cli."
  fi
  ospkg__install_user github-cli
  logging__fn_exit "_gh__repos_alpine"
  return 0
}

# _gh__repos_macos — install gh via Homebrew.
_gh__repos_macos() {
  logging__fn_entry "_gh__repos_macos"
  if [[ "${VERSION}" != "latest" && "${VERSION}" != "stable" ]]; then
    logging__warn "Homebrew has no versioned formula for gh. Installing latest gh. Use method=binary for version pinning."
  fi
  ospkg__install_user gh
  logging__fn_exit "_gh__repos_macos"
  return 0
}

# _gh__install_binary — download, verify, extract and install the gh binary.
# $1 = resolved version string (e.g. "2.89.0")
_gh__install_binary() {
  logging__fn_entry "_gh__install_binary"
  local _version="${1}"

  local _asset_os _asset_arch _ext _archive_name
  _asset_os="$(os__release_kernel gh)" || {
    logging__error "Unsupported kernel '$(os__kernel)' for method=binary."
    exit 1
  }
  _asset_arch="$(os__release_arch --flavor gh)" || {
    logging__error "Unsupported architecture '$(os__arch)' for method=binary."
    exit 1
  }
  case "$_asset_os" in
    linux) _ext="tar.gz" ;;
    macOS) _ext="zip" ;;
  esac
  _archive_name="gh_${_version}_${_asset_os}_${_asset_arch}.${_ext}"
  github__install_release \
    --repo "${GH_REPO}" --tag "v${_version}" \
    --asset "$_archive_name" --binary-src gh --binary-dest "${PREFIX}/bin/" \
    --sidecar "gh_${_version}_checksums.txt" \
    --installer-dir "${INSTALLER_DIR}" ||
    exit 1

  if [ "${#SHELL_COMPLETIONS[@]}" -gt 0 ]; then
    _gh__install_completions
  fi

  "${PREFIX}/bin/gh" --version > /dev/null
  logging__fn_exit "_gh__install_binary"
  return 0
}

# _gh__install_completions — install completions for shells listed in SHELL_COMPLETIONS.
_gh__install_completions() {
  logging__fn_entry "_gh__install_completions"
  if [ "${#SHELL_COMPLETIONS[@]}" -eq 0 ]; then
    logging__info "shell_completions is empty; skipping completion install."
    logging__fn_exit "_gh__install_completions"
    return 0
  fi
  local _shell
  for _shell in "${SHELL_COMPLETIONS[@]}"; do
    case "${_shell}" in
      bash)
        local _bash_content
        _bash_content="$(gh completion -s bash 2> /dev/null)" || {
          logging__warn "gh completion -s bash failed; skipping bash completion."
          _bash_content=""
        }
        if [ -n "${_bash_content}" ]; then
          if ! users__is_user_path "${PREFIX}"; then
            file__mkdir /etc/bash_completion.d
            printf '%s\n' "${_bash_content}" | file__tee /etc/bash_completion.d/gh
            logging__success "Bash completion written to /etc/bash_completion.d/gh"
          else
            local _uhome
            _uhome="$(users__home_of_path_owner "${PREFIX}")"
            file__mkdir "${_uhome}/.local/share/bash-completion/completions"
            printf '%s\n' "${_bash_content}" | file__tee "${_uhome}/.local/share/bash-completion/completions/gh"
            logging__success "Bash completion written to ${_uhome}/.local/share/bash-completion/completions/gh"
          fi
        fi
        ;;
      zsh)
        local _zsh_content
        _zsh_content="$(gh completion -s zsh 2> /dev/null)" || {
          logging__warn "gh completion -s zsh failed; skipping zsh completion."
          _zsh_content=""
        }
        if [ -n "${_zsh_content}" ]; then
          if ! users__is_user_path "${PREFIX}"; then
            local _zshdir
            _zshdir="$(shell__detect_zshdir)"
            file__mkdir "${_zshdir}/completions"
            printf '%s\n' "${_zsh_content}" | file__tee "${_zshdir}/completions/_gh"
            logging__success "Zsh completion written to ${_zshdir}/completions/_gh"
          else
            local _uhome
            _uhome="$(users__home_of_path_owner "${PREFIX}")"
            file__mkdir "${_uhome}/.zfunc"
            printf '%s\n' "${_zsh_content}" | file__tee "${_uhome}/.zfunc/_gh"
            logging__success "Zsh completion written to ${_uhome}/.zfunc/_gh"
          fi
        fi
        ;;
      *)
        logging__error "Unsupported shell: '${_shell}' (expected: bash, zsh)"
        exit 1
        ;;
    esac
  done
  logging__fn_exit "_gh__install_completions"
  return 0
}

# _gh__configure_user — apply per-user gh/git configuration.
_gh__configure_user() {
  logging__fn_entry "_gh__configure_user"
  local _users
  local -a _gh_uargs=()
  [ "${ADD_CURRENT_USER:-true}" != "true" ] && _gh_uargs+=(--current false)
  [ "${ADD_REMOTE_USER:-true}" != "true" ] && _gh_uargs+=(--remote false)
  [ "${ADD_CONTAINER_USER:-true}" != "true" ] && _gh_uargs+=(--container false)
  for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do [ -n "$_u" ] && _gh_uargs+=(--user "$_u"); done
  _users="$(users__resolve_list "${_gh_uargs[@]}")" || {
    logging__warn "users__resolve_list failed; skipping per-user configuration."
    logging__fn_exit "_gh__configure_user"
    return 0
  }
  if [ -z "${_users}" ]; then
    logging__info "No users resolved; skipping per-user configuration."
    logging__fn_exit "_gh__configure_user"
    return 0
  fi

  local _user _home
  while IFS= read -r _user; do
    [ -z "${_user}" ] && continue
    _home="$(users__resolve_home "${_user}")"

    logging__info "Configuring gh/git for user '${_user}' (home: ${_home})..."

    # git_protocol: run gh config set as the target user.
    if [ -n "${GIT_PROTOCOL}" ]; then
      logging__info "Setting git_protocol=${GIT_PROTOCOL} for '${_user}'..."
      if [ "${_user}" != "$(users__get_current --no-sudo)" ]; then
        users__run_as "${_user}" -- bash -c "gh config set git_protocol '${GIT_PROTOCOL}'"
      else
        GH_CONFIG_DIR="${_home}/.config/gh" gh config set git_protocol "${GIT_PROTOCOL}"
      fi
    fi

    # setup_git: register gh as credential helper.
    if [ "${SETUP_GIT}" = "true" ]; then
      logging__info "Running gh auth setup-git for '${_user}' (hostname: ${GIT_HOSTNAME})..."
      if [ "${_user}" != "$(users__get_current --no-sudo)" ]; then
        users__run_as "${_user}" -- bash -c "gh auth setup-git --force --hostname '${GIT_HOSTNAME}'"
      else
        GH_CONFIG_DIR="${_home}/.config/gh" HOME="${_home}" \
          gh auth setup-git --force --hostname "${GIT_HOSTNAME}"
      fi
      # Ensure .gitconfig is owned by the user.
      if [ -f "${_home}/.gitconfig" ]; then
        file__chown "${_user}:${_user}" "${_home}/.gitconfig" 2> /dev/null || true
      fi
    fi

    # sign_commits: set commit signing config via git config.
    if [ -n "${SIGN_COMMITS}" ]; then
      case "${SIGN_COMMITS}" in
        ssh)
          logging__info "Configuring SSH commit signing for '${_user}'..."
          if [ "${_user}" != "$(users__get_current --no-sudo)" ]; then
            users__run_as "${_user}" -- bash -c "git config --global gpg.format ssh"
            users__run_as "${_user}" -- bash -c "git config --global commit.gpgsign true"
          else
            GIT_CONFIG_GLOBAL="${_home}/.gitconfig" git config --global gpg.format ssh
            GIT_CONFIG_GLOBAL="${_home}/.gitconfig" git config --global commit.gpgsign true
          fi
          ;;
        gpg)
          logging__info "Configuring GPG commit signing for '${_user}'..."
          if [ "${_user}" != "$(users__get_current --no-sudo)" ]; then
            # Exit code 5 when key is absent — suppress with || true under set -e.
            users__run_as "${_user}" -- bash -c "git config --global --unset-all gpg.format || true"
            users__run_as "${_user}" -- bash -c "git config --global commit.gpgsign true"
          else
            GIT_CONFIG_GLOBAL="${_home}/.gitconfig" git config --global --unset-all gpg.format || true
            GIT_CONFIG_GLOBAL="${_home}/.gitconfig" git config --global commit.gpgsign true
          fi
          ;;
      esac
      if [ -f "${_home}/.gitconfig" ]; then
        file__chown "${_user}:${_user}" "${_home}/.gitconfig" 2> /dev/null || true
      fi
    fi
  done << EOF
${_users}
EOF
  logging__fn_exit "_gh__configure_user"
  return 0
}

# _gh__install_extensions — install gh CLI extensions for all resolved users.
_gh__install_extensions() {
  logging__fn_entry "_gh__install_extensions"
  local _users
  local -a _gh_uargs=()
  [ "${ADD_CURRENT_USER:-true}" != "true" ] && _gh_uargs+=(--current false)
  [ "${ADD_REMOTE_USER:-true}" != "true" ] && _gh_uargs+=(--remote false)
  [ "${ADD_CONTAINER_USER:-true}" != "true" ] && _gh_uargs+=(--container false)
  for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do [ -n "$_u" ] && _gh_uargs+=(--user "$_u"); done
  _users="$(users__resolve_list "${_gh_uargs[@]}")" || {
    logging__warn "users__resolve_list failed; skipping extension install."
    logging__fn_exit "_gh__install_extensions"
    return 0
  }
  if [ -z "${_users}" ]; then
    logging__info "No users resolved; skipping extension install."
    logging__fn_exit "_gh__install_extensions"
    return 0
  fi

  local _user _home _ext
  while IFS= read -r _user; do
    [ -z "${_user}" ] && continue
    _home="$(users__resolve_home "${_user}")"
    for _ext in "${EXTENSIONS[@]}"; do
      _ext="$(printf '%s' "${_ext}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
      [ -z "${_ext}" ] && continue
      logging__install "Installing gh extension '${_ext}' for user '${_user}'..."
      if [ "${_user}" != "$(users__get_current --no-sudo)" ]; then
        users__run_as "${_user}" -- bash -c "gh extension install '${_ext}'" || {
          logging__warn "Failed to install extension '${_ext}' for '${_user}' (non-fatal)."
        }
      else
        GH_CONFIG_DIR="${_home}/.config/gh" \
          HOME="${_home}" \
          gh extension install "${_ext}" || {
          logging__warn "Failed to install extension '${_ext}' (non-fatal)."
        }
      fi
    done
  done << EOF
${_users}
EOF
  logging__fn_exit "_gh__install_extensions"
  return 0
}

# ── Main orchestration ────────────────────────────────────────────────────────

# Early-exit if gh is already installed and version is 'latest' with
# if_exists=skip or if_exists=fail. Avoids requiring root, installing base deps,
# and hitting the GitHub API when no installation work is needed.
# This must run before base deps and the GitHub API call to skip early when possible.
if [[ "${VERSION}" = "latest" || "${VERSION}" = "stable" ]] && command -v gh > /dev/null 2>&1; then
  if [ "${IF_EXISTS}" = "skip" ]; then
    _installed_ver="$(gh --version 2> /dev/null | head -1 | awk '{print $3}')" || _installed_ver=""
    logging__info "gh ${_installed_ver} is already installed — skipping (if_exists=skip, version=${VERSION})."
    exit 0
  elif [ "${IF_EXISTS}" = "fail" ]; then
    _installed_ver="$(gh --version 2> /dev/null | head -1 | awk '{print $3}')" || _installed_ver=""
    logging__error "gh is already installed (${_installed_ver}) and if_exists=fail."
    exit 1
  fi
fi

# Resolve version (may call GitHub API).
_resolved_version="$(_gh__resolve_version)"

# Check existing installation; may exit 0 or 1.
_gh__check_existing "${_resolved_version}"

# Install gh.
if [ "${METHOD}" = "upstream-package" ]; then
  _gh__install_repos
else
  _gh__install_binary "${_resolved_version}"
fi

# Install completions for upstream-package method (binary method handles them internally).
if [ "${#SHELL_COMPLETIONS[@]}" -gt 0 ] && [ "${METHOD}" = "upstream-package" ]; then
  _gh__install_completions
fi

# Per-user configuration (git_protocol, setup_git, sign_commits).
if [ -n "${GIT_PROTOCOL}" ] || [ "${SETUP_GIT}" = "true" ] || [ -n "${SIGN_COMMITS}" ]; then
  _gh__configure_user
fi

# Install gh extensions (if any).
if [ "${#EXTENSIONS[@]}" -gt 0 ]; then
  _gh__install_extensions
fi
