# _configure_user — apply per-user gh/git configuration.
_configure_user() {
  local _users
  local -a _gh_uargs=()
  [ "${ADD_CURRENT_USER}" != "true" ] && _gh_uargs+=(--current false)
  [ "${ADD_REMOTE_USER}" != "true" ] && _gh_uargs+=(--remote false)
  [ "${ADD_CONTAINER_USER}" != "true" ] && _gh_uargs+=(--container false)
  for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do [ -n "$_u" ] && _gh_uargs+=(--user "$_u"); done
  _users="$(users__resolve_list "${_gh_uargs[@]}")"
  if [ -z "${_users}" ]; then
    logging__info "No users resolved; skipping per-user configuration."
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
  return 0
}

# _install_extensions — install gh CLI extensions for all resolved users.
_install_extensions() {
  local _users
  local -a _gh_uargs=()
  [ "${ADD_CURRENT_USER}" != "true" ] && _gh_uargs+=(--current false)
  [ "${ADD_REMOTE_USER}" != "true" ] && _gh_uargs+=(--remote false)
  [ "${ADD_CONTAINER_USER}" != "true" ] && _gh_uargs+=(--container false)
  for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do [ -n "$_u" ] && _gh_uargs+=(--user "$_u"); done
  _users="$(users__resolve_list "${_gh_uargs[@]}")"
  if [ -z "${_users}" ]; then
    logging__info "No users resolved; skipping extension install."
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
  return 0
}

# __install_finish_post — run per-user config and extensions after install.
__install_finish_post() {
  if [ -n "${GIT_PROTOCOL}" ] || [ "${SETUP_GIT}" = "true" ] || [ -n "${SIGN_COMMITS}" ]; then
    _configure_user
  fi
  if [ "${#EXTENSIONS[@]}" -gt 0 ]; then
    _install_extensions
  fi
}
