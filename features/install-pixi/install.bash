# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# Override: use pixi's native self-update command for updates.
# Version and prefix checks are handled by __update_predispatch__; this hook
# only runs when a version update is actually needed.
# shellcheck disable=SC2329,SC2317
__update_run__() {
  logging__install "Updating pixi to version '${VERSION}' via self-update."
  "${_FEAT_EXISTING_PATH}" self-update --version "${VERSION}" || {
    logging__error "pixi self-update to version '${VERSION}' failed."
    return 1
  }
}

# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  if [[ -z "${GLOBAL_MANIFEST:-}" && ${#GLOBAL_INSTALLS[@]} -eq 0 ]]; then
    logging__skip "global_manifest and global_installs unset; skipping pixi global configuration."
    return 0
  fi

  # Resolve pixi binary — prefer the just-installed prefix path, fall back to PATH.
  local _pixi_bin=""
  if [[ -v _RESOLVED_PREFIX && -x "${_RESOLVED_PREFIX}/bin/pixi" ]]; then
    _pixi_bin="${_RESOLVED_PREFIX}/bin/pixi"
  else
    _pixi_bin="$(command -v pixi 2> /dev/null || true)"
  fi
  if [[ -z "${_pixi_bin}" ]]; then
    logging__error "pixi binary not found; cannot configure global packages."
    return 1
  fi

  # Determine the user pixi runs as: devcontainer-aware (SUDO_USER → _REMOTE_USER → id -un).
  # This is the same resolution that prefix activation and shell completions use, so PIXI_HOME
  # ends up in the home of whoever will actually source the activation snippet.
  local _user _user_home
  _user="$(users__get_current)"
  _user_home="$(users__resolve_home "$_user")"

  # Compute PIXI_HOME: honour HOME_DIR option (expanding ~ to the resolved user home,
  # not $HOME, which is the install-process owner and may differ from _user).
  local _pixi_home
  if [[ -n "${HOME_DIR:-}" ]]; then
    _pixi_home="${HOME_DIR}"
    # shellcheck disable=SC2088
    [[ "$_pixi_home" == '~/'* ]] && _pixi_home="${_user_home}/${_pixi_home#\~/}"
    [[ "$_pixi_home" == '~' ]] && _pixi_home="${_user_home}"
  else
    _pixi_home="${_user_home}/.pixi"
  fi

  if [[ -n "${GLOBAL_MANIFEST:-}" ]]; then
    # Normalize literal \n escapes (some environments serialize multi-line strings this way).
    if [[ "$GLOBAL_MANIFEST" != *$'\n'* && "$GLOBAL_MANIFEST" == *'\n'* ]]; then
      GLOBAL_MANIFEST="$(printf '%b' "$GLOBAL_MANIFEST")"
      logging__info "Expanded literal \\n escapes in GLOBAL_MANIFEST."
    fi

    local _manifest_dest="${_pixi_home}/manifests/pixi-global.toml"
    file__mkdir "${_pixi_home}/manifests"

    if [[ "$GLOBAL_MANIFEST" == *$'\n'* ]]; then
      logging__install "Writing inline global manifest to '${_manifest_dest}'."
      printf '%s\n' "$GLOBAL_MANIFEST" | file__tee "$_manifest_dest"
    else
      local _matdir _resolved
      _matdir="$(file__mktmpdir "${_FEAT_ID}-global-manifest")"
      local -a _fetch_args=()
      local _h
      if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
        for _h in "${FETCH_HEADERS[@]}"; do
          [[ -n "${_h}" ]] && _fetch_args+=(--header "${_h}")
        done
      fi
      [[ -n "${FETCH_NETRC:-}" ]] && _fetch_args+=(--netrc-file "${FETCH_NETRC}")
      logging__download "Resolving global manifest from '${GLOBAL_MANIFEST}'."
      _resolved="$(uri__resolve_line "$GLOBAL_MANIFEST" "$_matdir" "${_fetch_args[@]+"${_fetch_args[@]}"}")"
      logging__install "Writing fetched global manifest to '${_manifest_dest}'."
      file__cp "$_resolved" "$_manifest_dest"
    fi

    # If the install process is running as a different user (e.g. root in a devcontainer
    # build), the files written above are owned by root.  Fix ownership so the target
    # user can modify them when pixi runs at container runtime.
    if [[ "$(users__get_current --no-sudo)" != "$_user" ]]; then
      logging__install "Setting ownership of '${_pixi_home}/manifests' to '${_user}'."
      file__chown "${_user}:${_user}" "${_pixi_home}"
      file__chown -R "${_user}:${_user}" "${_pixi_home}/manifests"
    fi

    local -a _sync_args=()
    [[ -n "${GLOBAL_SYNC:-}" ]] && read -ra _sync_args <<< "$GLOBAL_SYNC"
    logging__install "Running 'pixi global sync${_sync_args[*]:+ ${_sync_args[*]}}'."
    users__run_as "$_user" -- env "PIXI_HOME=${_pixi_home}" "$_pixi_bin" global sync \
      "${_sync_args[@]+"${_sync_args[@]}"}"
  fi

  if [[ ${#GLOBAL_INSTALLS[@]} -gt 0 ]]; then
    local _item
    for _item in "${GLOBAL_INSTALLS[@]}"; do
      [[ -z "${_item}" ]] && continue
      local -a _install_args=()
      read -ra _install_args <<< "$_item"
      logging__install "Running 'pixi global install ${_install_args[*]}'."
      users__run_as "$_user" -- env "PIXI_HOME=${_pixi_home}" "$_pixi_bin" global install \
        "${_install_args[@]}"
    done
  fi
}

# Invoked by the generated prefix activation system for each configured shell.
# shellcheck disable=SC2329,SC2317
__prefix_activation_snippet() {
  if [ -n "${HOME_DIR}" ]; then
    # Normalize a leading ~ to ${HOME} so the expression expands correctly in
    # double-quoted shell strings at runtime (bare tilde is not expanded there).
    local _pixi_home="${HOME_DIR}"
    # shellcheck disable=SC2088,SC2016
    [[ "$_pixi_home" == '~/'* ]] && _pixi_home='${HOME}/'"${_pixi_home#\~/}"
    # shellcheck disable=SC2016
    [[ "$_pixi_home" == '~' ]] && _pixi_home='${HOME}'
    printf 'export PIXI_HOME="%s"\n' "$_pixi_home"
  else
    # shellcheck disable=SC2016
    printf 'export PIXI_HOME="${HOME}/.pixi"\n'
  fi
  return 0
}
