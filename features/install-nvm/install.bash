# shellcheck shell=bash

_NVM_CLEANUP_ENABLED="false"

_nvm_run() {
  if [ "${INSTALL_USER}" = "$(users__get_current --no-sudo)" ]; then
    bash -c "$1"
  else
    users__run_privileged su "$INSTALL_USER" -c "$1"
  fi
}

__exit_pre() {
  logging__fn_entry "__exit_pre"
  if [ "${_NVM_CLEANUP_ENABLED-}" = "true" ] && [ -n "${PREFIX-}" ] && [ -f "${PREFIX}/nvm.sh" ] && [ -n "${INSTALL_USER-}" ]; then
    _nvm_run ". '${PREFIX}/nvm.sh' && nvm clear-cache" 2> /dev/null || true
  fi
  logging__fn_exit "__exit_pre"
}

__init_args_post() {
  [ -n "${INSTALL_USER:-}" ] || INSTALL_USER="$(users__get_current)"
}

__detect_existing_path_post() {
  [ -f "${PREFIX}/nvm.sh" ] && _FEAT_EXISTING_PATH="${PREFIX}/nvm.sh"
}

__install_run_script_pre() {
  logging__info "Installing nvm runtime dependencies..."
  __dep_install__ run nvm-runtime

  if [ "${NODE_GYP_DEPS}" = "true" ]; then
    if [ "$(os__platform)" = "alpine" ]; then
      logging__info "Alpine detected — node-gyp build tools already provided by nvm build toolchain; skipping."
    else
      logging__info "Installing node-gyp build dependencies..."
      __dep_install__ run node-gyp
      if [ "$(os__platform)" = "macos" ]; then
        logging__info "node-gyp build dependencies on macOS require Xcode Command Line Tools."
        logging__info "Install them with: xcode-select --install"
      fi
    fi
  fi

  logging__info "Installing nvm build dependencies..."
  __dep_install__ build nvm

  file__mkdir "$PREFIX"

  if [ -n "${WRITE_GROUP:-}" ] && ! users__is_user_path "${PREFIX}"; then
    local -a _nvm_wargs=()
    if [ "${#WRITE_USERS[@]}" -gt 0 ]; then
      _nvm_wargs=(--current false --remote false --container false)
      for _u in "${WRITE_USERS[@]}"; do _nvm_wargs+=(--user "$_u"); done
    fi
    mapfile -t _write_users < <(users__resolve_list "${_nvm_wargs[@]}")
    users__set_write_permissions "$PREFIX" "$INSTALL_USER" "$WRITE_GROUP" "${_write_users[@]}"
  fi

  _NVM_CLEANUP_ENABLED="true"
}

# Run the downloaded nvm installer as the target user.
# Piped via stdin so INSTALL_USER never needs read access to the root-owned tmpdir.
__install_run_script_run() {
  local _installer="$1"
  logging__info "Running nvm ${VERSION} installer as user '${INSTALL_USER}'..."
  _nvm_run \
    "umask 0002 && PROFILE=/dev/null NVM_SYMLINK_CURRENT=true NVM_DIR='${PREFIX}' bash -s" \
    < "${_installer}"

  # Verify nvm loaded (in root shell)
  # shellcheck disable=SC1091
  . "${PREFIX}/nvm.sh"
  command -v nvm > /dev/null 2>&1 || {
    logging__error "nvm command not found after installation."
    return 1
  }
  logging__success "nvm ${VERSION} installed successfully."
}

__install_run_script_post() {
  _nvm_install_node_versions
  if [ "${#NODE_VERSIONS[@]}" -gt 0 ]; then
    _nvm_run "export NVM_SYMLINK_CURRENT=true && . '${PREFIX}/nvm.sh' && node --version && npm --version"
    logging__success "Node.js is ready."
  fi
}

# _nvm_install_node_versions
# Installs the primary Node.js version (first entry of NODE_VERSIONS) as the nvm
# default alias, then installs any additional entries without changing the default.
_nvm_install_node_versions() {
  logging__fn_entry "_nvm_install_node_versions"

  if [ "${#NODE_VERSIONS[@]}" -eq 0 ]; then
    logging__info "node_versions is empty — skipping Node.js installation."
    logging__fn_exit "_nvm_install_node_versions (empty)"
    return 0
  fi

  local _primary="${NODE_VERSIONS[0]}"
  [ "$_primary" = "lts" ] && _primary="lts/*"

  logging__info "Installing primary Node.js '${_primary}' via nvm..."
  if [ "$(os__platform)" = "alpine" ]; then
    logging__info "Alpine detected — compiling Node.js from source (nvm install -s)."
    _nvm_run "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${PREFIX}/nvm.sh' && nvm install -s '${_primary}'"
  else
    _nvm_run "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${PREFIX}/nvm.sh' && nvm install '${_primary}'"
  fi
  _nvm_run "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${PREFIX}/nvm.sh' && nvm alias default '${_primary}'"
  _nvm_run "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${PREFIX}/nvm.sh' && nvm use default"

  local _node_version
  _node_version="$(_nvm_run "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${PREFIX}/nvm.sh' && nvm version '${_primary}'")"
  logging__info "Primary Node.js version installed: ${_node_version}"

  if [ -d "${PREFIX}/versions" ]; then
    file__chmod -R g+rw "${PREFIX}/versions"
  fi

  _nvm_install_additional_versions 1

  if [ "${#NODE_VERSIONS[@]}" -gt 1 ]; then
    _nvm_run "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${PREFIX}/nvm.sh' && nvm use default"
  fi

  logging__success "Node.js ${_node_version} installed via nvm."
  logging__fn_exit "_nvm_install_node_versions"
}

# _nvm_install_additional_versions <start_index>
# Installs NODE_VERSIONS entries from <start_index> onward without changing the default.
_nvm_install_additional_versions() {
  local _start="${1:-1}"
  local _i=0
  local _ver
  for _ver in "${NODE_VERSIONS[@]}"; do
    if [ "${_i}" -lt "${_start}" ]; then
      ((_i++)) || true
      continue
    fi
    _ver="${_ver## }"
    _ver="${_ver%% }"
    if [ -z "$_ver" ]; then
      ((_i++)) || true
      continue
    fi
    logging__info "Installing additional Node.js version: ${_ver}"
    _nvm_run "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${PREFIX}/nvm.sh' && nvm install '${_ver}'"
    ((_i++)) || true
  done
}

create_nvm_symlinks() {
  logging__fn_entry "create_nvm_symlinks"
  if users__is_user_path "${PREFIX}"; then
    logging__info "User-local prefix: NVM bridge symlinks not applicable."
    logging__fn_exit "create_nvm_symlinks"
    return 0
  fi
  users__run_privileged ln -sf "${PREFIX}" "/usr/local/share/nvm"
  # Create stable executable entrypoints for non-interactive contexts
  # that may not source shell init files.
  for _bin in node npm npx corepack; do
    local _src="${PREFIX}/current/bin/${_bin}"
    [ -f "$_src" ] || continue
    logging__info "Symlinking ${_src} → /usr/local/bin/${_bin}"
    users__run_privileged ln -sf "$_src" "/usr/local/bin/${_bin}"
  done
  logging__fn_exit "create_nvm_symlinks"
  return
}

__install_finish_post() {
  create_nvm_symlinks
}

# shellcheck disable=SC2329,SC2317
prefix_activation_snippet() {
  cat << SNIPPET
export NVM_SYMLINK_CURRENT=true
export NVM_DIR="${PREFIX}"
# shellcheck disable=SC1090
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && . "\$NVM_DIR/bash_completion"
SNIPPET
  return 1
}
