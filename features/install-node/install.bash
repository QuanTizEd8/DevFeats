_cleanup_hook() {
  logging__fn_entry "_cleanup_hook"
  # shellcheck disable=SC2015  # || true is intentional: cleanup must not abort on rm failure
  [ -n "${INSTALLER_DIR-}" ] && rm -rf "$INSTALLER_DIR" 2> /dev/null || true
  if [ "${_NVM_CLEANUP_ENABLED-}" = "true" ] && [ -n "${NVM_DIR-}" ] && [ -f "${NVM_DIR}/nvm.sh" ] && [ -n "${_NVM_USER-}" ]; then
    su "$_NVM_USER" -c ". '${NVM_DIR}/nvm.sh' && nvm clear-cache" 2> /dev/null || true
  fi
  logging__fn_exit "_cleanup_hook"
}

# _node_build_platform_string
# Outputs a nodejs.org platform string (e.g. linux-x64, darwin-arm64).
# Arguments: kernel arch
_node_build_platform_string() {
  logging__fn_entry "_node_build_platform_string"
  local _kernel="$1"
  local _arch="$2"

  # Normalise: Darwin aarch64 → arm64 (user-supplied override may use either form)
  if [ "$_kernel" = "Darwin" ] && [ "$_arch" = "aarch64" ]; then
    _arch="arm64"
  fi

  local _platform=""
  case "${_kernel}:${_arch}" in
    Linux:x86_64) _platform="linux-x64" ;;
    Linux:aarch64) _platform="linux-arm64" ;;
    Linux:arm64) _platform="linux-arm64" ;;
    Linux:armv7l) _platform="linux-armv7l" ;;
    Linux:ppc64le) _platform="linux-ppc64le" ;;
    Linux:s390x) _platform="linux-s390x" ;;
    Darwin:x86_64) _platform="darwin-x64" ;;
    Darwin:arm64) _platform="darwin-arm64" ;;
    *)
      logging__error "Unsupported kernel/arch combination for Node.js binary: ${_kernel}/${_arch}"
      logging__info "Use method=nvm for source-based installation on unsupported architectures."
      return 1
      ;;
  esac
  echo "$_platform"
  logging__fn_exit "_node_build_platform_string → ${_platform}"
  return 0
}

# _node_resolve_binary_version
# Resolves a version spec to an exact vX.Y.Z string using a downloaded index.json.
# Arguments: version_spec index_json_path
_node_resolve_binary_version() {
  logging__fn_entry "_node_resolve_binary_version"
  local _spec="$1"
  local _index="$2"

  # Normalise "lts" alias → "lts/*"
  [ "$_spec" = "lts" ] && _spec="lts/*"

  local _resolved=""
  case "$_spec" in
    "lts/*")
      _resolved="$(json__nodejs_index_version_stdin lts-first < "$_index")" || _resolved=""
      ;;
    "latest" | "node")
      _resolved="$(json__nodejs_index_version_stdin head < "$_index")" || _resolved=""
      ;;
    [0-9]*)
      _resolved="$(json__nodejs_index_version_stdin major "$_spec" < "$_index")" || _resolved=""
      ;;
    v[0-9]*\.*\.[0-9]*)
      # Exact semver with leading v
      _resolved="$_spec"
      if ! json__nodejs_index_version_stdin exact "$_spec" < "$_index" > /dev/null; then
        logging__error "Node.js version '${_spec}' was not found in nodejs.org/dist/index.json."
        return 1
      fi
      ;;
    [0-9]*\.*\.[0-9]*)
      # Exact semver without leading v
      _resolved="v${_spec}"
      if ! json__nodejs_index_version_stdin exact "v${_spec}" < "$_index" > /dev/null; then
        logging__error "Node.js version '${_spec}' was not found in nodejs.org/dist/index.json."
        return 1
      fi
      ;;
    *)
      logging__error "Version spec '${_spec}' is not supported by method=binary."
      logging__info "Supported formats: lts/*, latest, a major number (e.g. 22), or an exact semver."
      logging__info "nvm-style named LTS aliases (e.g. 'lts/iron') are not supported; use method=nvm instead."
      return 1
      ;;
  esac

  if [ -z "$_resolved" ]; then
    logging__error "Could not resolve Node.js version '${_spec}' from index.json."
    return 1
  fi

  echo "$_resolved"
  logging__fn_exit "_node_resolve_binary_version → ${_resolved}"
  return 0
}

# _node_check_if_exists
# Pre-install check: handles if_exists option for an existing node binary.
_node_check_if_exists() {
  logging__fn_entry "_node_check_if_exists"
  command -v node > /dev/null 2>&1 || {
    logging__fn_exit "_node_check_if_exists (not found)"
    return 0
  }

  local _installed_ver
  _installed_ver="$(node --version 2> /dev/null || true)"
  logging__info "Existing node found: ${_installed_ver}"

  # For binary method: compare against the pre-resolved target version.
  if [ "$METHOD" = "binary" ] && [ -n "${_NODE_VERSION:-}" ] && [ "$_installed_ver" = "$_NODE_VERSION" ]; then
    logging__info "Node.js ${_NODE_VERSION} is already installed — skipping (version matches)."
    exit 0
  fi

  # For nvm method with an exact semver spec: compare if possible.
  if [ "$METHOD" = "nvm" ]; then
    local _spec="$VERSION"
    [ "$_spec" = "lts" ] && _spec="lts/*"
    case "$_spec" in
      v[0-9]*\.*\.[0-9]* | [0-9]*\.*\.[0-9]*)
        local _target="v${_spec#v}"
        if [ "$_installed_ver" = "$_target" ]; then
          logging__info "Node.js ${_target} is already installed — skipping (version matches)."
          exit 0
        fi
        ;;
    esac
  fi

  case "$IF_EXISTS" in
    skip)
      logging__info "node is already installed (${_installed_ver}) and if_exists=skip — skipping."
      exit 0
      ;;
    fail)
      logging__error "node is already installed (${_installed_ver}) and if_exists=fail."
      exit 1
      ;;
    reinstall)
      logging__info "node is already installed (${_installed_ver}) — reinstalling (if_exists=reinstall)."
      if [ "$METHOD" = "binary" ]; then
        for _bin in node npm npx corepack; do
          local _p
          _p="$(command -v "$_bin" 2> /dev/null || true)"
          [ -n "$_p" ] && {
            logging__info "Removing ${_p}"
            rm -f "$_p"
          }
        done
      elif [ "$METHOD" = "nvm" ]; then
        if [ -f "${NVM_DIR}/nvm.sh" ]; then
          # shellcheck disable=SC1091
          . "${NVM_DIR}/nvm.sh"
          local _ver_to_remove="$VERSION"
          [ "$_ver_to_remove" = "lts" ] && _ver_to_remove="lts/*"
          nvm uninstall "$_ver_to_remove" 2> /dev/null || true
        else
          logging__info "NVM_DIR/nvm.sh not found — skipping nvm uninstall (will install fresh)."
        fi
      fi
      ;;
  esac

  logging__fn_exit "_node_check_if_exists"
  return 0
}

# _node_set_permissions
# Create nvm group, configure ownership/bits on NVM_DIR, add users to the group.
_node_set_permissions() {
  logging__fn_entry "_node_set_permissions"
  logging__info "Creating group '${GROUP}' and configuring permissions on '${NVM_DIR}'."
  mkdir -p "$NVM_DIR"
  users__set_write_permissions "$NVM_DIR" "$_NVM_USER" "$GROUP" "${_RESOLVED_USERS[@]}"
  logging__fn_exit "_node_set_permissions"
  return 0
}

# _node_install_via_nvm
# Full nvm-based installation flow.
_node_install_via_nvm() {
  logging__fn_entry "_node_install_via_nvm"
  local _nvm_tag

  # Resolve nvm tag
  if [ "$NVM_VERSION" = "latest" ]; then
    logging__info "Resolving latest nvm release tag..."
    _nvm_tag="$(github__latest_tag nvm-sh/nvm)"
    logging__info "Latest nvm tag: ${_nvm_tag}"
  else
    _nvm_tag="v${NVM_VERSION#v}"
  fi

  logging__info "Installing nvm ${_nvm_tag}..."

  # Download nvm install script
  mkdir -p "$INSTALLER_DIR"
  net__fetch_url_file \
    "https://raw.githubusercontent.com/nvm-sh/nvm/${_nvm_tag}/install.sh" \
    "${INSTALLER_DIR}/nvm-install.sh"

  # Create NVM_DIR before set_permissions (which chowns it)
  mkdir -p "$NVM_DIR"

  # Set permissions (creates group, configures ownership)
  if [ "$SET_PERMISSIONS" = "true" ] && [ "$(id -u)" = "0" ]; then
    _node_set_permissions
  fi

  # Mark nvm cleanup as active now that NVM_DIR is initialised
  _NVM_CLEANUP_ENABLED="true"

  # Run nvm installer as target user
  logging__info "Running nvm installer as user '${_NVM_USER}'..."
  su "$_NVM_USER" -c \
    "umask 0002 && PROFILE=/dev/null NVM_SYMLINK_CURRENT=true NVM_DIR='${NVM_DIR}' bash '${INSTALLER_DIR}/nvm-install.sh'"

  # Verify nvm loaded (in root shell)
  # shellcheck disable=SC1091
  . "${NVM_DIR}/nvm.sh"
  command -v nvm > /dev/null 2>&1 || {
    logging__error "nvm command not found after installation."
    return 1
  }
  logging__success "nvm installed successfully."

  # Normalise version; if none, skip Node.js install
  local _node_ver_spec="$VERSION"
  [ "$_node_ver_spec" = "lts" ] && _node_ver_spec="lts/*"

  if [ "$_node_ver_spec" = "none" ]; then
    logging__info "version=none — skipping Node.js installation."
    if [ "${#ADDITIONAL_VERSIONS[@]}" -gt 0 ]; then
      logging__warn "VERSION=none with additional_versions: no default alias is set — run 'nvm alias default <version>' manually inside the container."
      local _add_ver
      local _add_versions=("${ADDITIONAL_VERSIONS[@]}")
      for _add_ver in "${_add_versions[@]}"; do
        _add_ver="${_add_ver## }"
        _add_ver="${_add_ver%% }"
        [ -z "$_add_ver" ] && continue
        logging__info "Installing additional Node.js version: ${_add_ver}"
        su "$_NVM_USER" -c "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && nvm install '${_add_ver}'"
      done
    fi
    logging__fn_exit "_node_install_via_nvm (version=none)"
    return 0
  fi

  # Install primary version
  logging__info "Installing Node.js '${_node_ver_spec}' via nvm..."
  if [ "$(os__platform)" = "alpine" ]; then
    logging__info "Alpine detected — compiling Node.js from source (nvm install -s)."
    su "$_NVM_USER" -c "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && nvm install -s '${_node_ver_spec}'"
  else
    su "$_NVM_USER" -c "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && nvm install '${_node_ver_spec}'"
  fi

  # Set default alias
  su "$_NVM_USER" -c "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && nvm alias default '${_node_ver_spec}'"

  # Restore primary version as active
  su "$_NVM_USER" -c "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && nvm use default"

  # Capture exact version
  _NODE_VERSION="$(su "$_NVM_USER" -c "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && nvm version '${_node_ver_spec}'")"
  logging__info "Installed Node.js version: ${_NODE_VERSION}"

  # Fix version directory permissions (tarballs extracted by nvm may lack group-write)
  if [ -d "${NVM_DIR}/versions" ]; then
    chmod -R g+rw "${NVM_DIR}/versions"
  fi

  # Install additional versions
  if [ "${#ADDITIONAL_VERSIONS[@]}" -gt 0 ]; then
    local _add_ver
    local _add_versions=("${ADDITIONAL_VERSIONS[@]}")
    for _add_ver in "${_add_versions[@]}"; do
      _add_ver="${_add_ver## }"
      _add_ver="${_add_ver%% }"
      [ -z "$_add_ver" ] && continue
      logging__info "Installing additional Node.js version: ${_add_ver}"
      su "$_NVM_USER" -c "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && nvm install '${_add_ver}'"
    done
    # Restore default after additional installs
    su "$_NVM_USER" -c "umask 0002 && export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && nvm use default"
  fi

  logging__success "Node.js ${_NODE_VERSION} installed via nvm."
  logging__fn_exit "_node_install_via_nvm"
  return 0
}

# _node_install_via_binary
# Full binary-tarball installation flow.
_node_install_via_binary() {
  logging__fn_entry "_node_install_via_binary"

  if [ "$(os__platform)" = "alpine" ]; then
    logging__error "method=binary is not supported on Alpine Linux (glibc-only binaries)."
    logging__info "Use method=nvm instead — nvm will compile Node.js from source on Alpine."
    return 1
  fi

  # Build platform string
  local _arch_str="$ARCH"
  if [ -z "$_arch_str" ]; then
    _arch_str="$(os__arch)"
  fi
  local _kernel_str
  _kernel_str="$(os__kernel)"
  local _platform
  _platform="$(_node_build_platform_string "$_kernel_str" "$_arch_str")"

  # Resolve install prefix
  local _install_prefix="$PREFIX"
  if [ -z "$_install_prefix" ]; then
    _install_prefix="/usr/local"
  fi

  # Resolve exact version (may already be set from pre-install check step)
  mkdir -p "$INSTALLER_DIR"
  if [ -z "${_NODE_VERSION:-}" ]; then
    logging__info "Downloading Node.js release index..."
    net__fetch_url_file \
      "https://nodejs.org/dist/index.json" \
      "${INSTALLER_DIR}/index.json"
    _NODE_VERSION="$(_node_resolve_binary_version "$VERSION" "${INSTALLER_DIR}/index.json")"
  fi

  logging__info "Installing Node.js ${_NODE_VERSION} (${_platform}) to ${_install_prefix}..."

  local _tarball="node-${_NODE_VERSION}-${_platform}.tar.xz"

  # Download tarball
  net__fetch_url_file \
    "https://nodejs.org/dist/${_NODE_VERSION}/${_tarball}" \
    "${INSTALLER_DIR}/${_tarball}"

  # Download checksums
  net__fetch_url_file \
    "https://nodejs.org/dist/${_NODE_VERSION}/SHASUMS256.txt" \
    "${INSTALLER_DIR}/SHASUMS256.txt"

  # Extract expected hash (two-space separator between hash and filename)
  local _hash
  _hash="$(grep "  ${_tarball}$" "${INSTALLER_DIR}/SHASUMS256.txt" | awk '{print $1}')"
  if [ -z "$_hash" ]; then
    logging__error "Could not find checksum for '${_tarball}' in SHASUMS256.txt."
    return 1
  fi

  # Verify checksum
  verify__sha "${INSTALLER_DIR}/${_tarball}" "$_hash"

  # Extract to install prefix
  mkdir -p "$_install_prefix"
  file__extract_archive "${INSTALLER_DIR}/${_tarball}" "$_install_prefix" "" --strip 1

  # Update PREFIX with resolved value for use by caller
  PREFIX="$_install_prefix"

  logging__success "Node.js ${_NODE_VERSION} extracted to ${_install_prefix}."
  logging__fn_exit "_node_install_via_binary"
  return 0
}

# _node_resolve_nvm_dir
# Resolves NVM_DIR to an identity-appropriate path when empty.
_node_resolve_nvm_dir() {
  logging__fn_entry "_node_resolve_nvm_dir"
  case "${NVM_DIR}" in
    "")
      if [ "$(id -u)" = "0" ]; then
        NVM_DIR="/usr/local/share/nvm"
      else
        NVM_DIR="${HOME}/.nvm"
      fi
      ;;
    *) ;; # explicit value: use as-is
  esac
  logging__info "Resolved nvm_dir to '${NVM_DIR}'"
  logging__fn_exit "_node_resolve_nvm_dir"
  return 0
}

# _node_create_symlinks
# Creates containerEnv-bridge symlinks and per-binary symlinks.
_node_create_symlinks() {
  logging__fn_entry "_node_create_symlinks"
  if [ "$SYMLINK" != "true" ]; then
    logging__info "Skipping symlink creation (symlink=false)."
    logging__fn_exit "_node_create_symlinks (skipped)"
    return 0
  fi

  if [ "$(id -u)" = "0" ]; then
    if [ "$METHOD" = "nvm" ]; then
      # Bridge symlink: /usr/local/share/nvm → NVM_DIR (when they differ).
      # The containerEnv.NVM_DIR is always /usr/local/share/nvm; keep it valid
      # for any non-default nvm_dir value (root only — non-root can't write there).
      local _nvm_canonical_root="/usr/local/share/nvm"
      if [ "$NVM_DIR" != "${_nvm_canonical_root}" ]; then
        logging__info "Creating NVM_DIR bridge symlink: ${_nvm_canonical_root} → ${NVM_DIR}"
        mkdir -p "$(dirname "${_nvm_canonical_root}")"
        ln -sf "$NVM_DIR" "${_nvm_canonical_root}"
      fi
      # Create stable executable entrypoints for non-interactive contexts
      # that may not source shell init files.
      for _bin in node npm npx corepack; do
        local _src="${NVM_DIR}/current/bin/${_bin}"
        if [ -f "$_src" ]; then
          logging__info "Symlinking ${_src} → /usr/local/bin/${_bin}"
          ln -sf "$_src" "/usr/local/bin/${_bin}"
        fi
      done
    elif [ "$METHOD" = "binary" ]; then
      # Binaries already in /usr/local/bin when prefix is /usr/local
      if [ "$PREFIX" = "/usr/local" ]; then
        logging__info "prefix=/usr/local — binary symlinks not needed."
      else
        for _bin in node npm npx corepack; do
          local _src="${PREFIX}/bin/${_bin}"
          if [ -f "$_src" ]; then
            logging__info "Symlinking ${_src} → /usr/local/bin/${_bin}"
            ln -sf "$_src" "/usr/local/bin/${_bin}"
          fi
        done
      fi
    fi
  else
    # Non-root: only method=binary with a non-default prefix.
    if [ "$METHOD" = "binary" ] && [ "$PREFIX" != "${HOME}/.local" ]; then
      mkdir -p "${HOME}/.local/bin"
      for _bin in node npm npx corepack; do
        local _src="${PREFIX}/bin/${_bin}"
        if [ -f "$_src" ]; then
          logging__info "Symlinking ${_src} → ${HOME}/.local/bin/${_bin}"
          ln -sf "$_src" "${HOME}/.local/bin/${_bin}"
        fi
      done
    else
      logging__info "Skipping symlink creation (non-root: method=nvm or prefix is ${HOME}/.local)."
    fi
  fi

  logging__fn_exit "_node_create_symlinks"
  return 0
}

# _node_write_nvm_rc
# Writes the nvm shell-initialisation snippet to startup files.
# Arguments: [--home <dir>]  (omit for system-wide write)
_node_write_nvm_rc() {
  logging__fn_entry "_node_write_nvm_rc"
  local _home=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  local _content
  _content="$(
    cat << NVMRC
export NVM_SYMLINK_CURRENT=true
export NVM_DIR="${NVM_DIR}"
# shellcheck disable=SC1090
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && . "\$NVM_DIR/bash_completion"
NVMRC
  )"
  local _marker="nvm init (install-node)"

  if [ -z "$_home" ]; then
    # System-wide
    local _files
    _files="$(shell__system_path_files --profile_d 'nvm_init.sh')"
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
  else
    # Per-user
    local _files
    _files="$(shell__user_init_files --home "$_home")"
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
  fi

  logging__fn_exit "_node_write_nvm_rc"
  return 0
}

# _node_configure_path
# Writes PATH and shell-init exports to startup files.
_node_configure_path() {
  logging__fn_entry "_node_configure_path"
  if [ "${#EXPORT_PATH[@]}" -eq 0 ]; then
    logging__info "export_path='' — skipping all PATH writes."
    logging__fn_exit "_node_configure_path (skipped)"
    return 0
  fi

  if [ "$METHOD" = "nvm" ]; then
    # System-wide nvm init snippet
    _node_write_nvm_rc

    # Per-user nvm init snippets
    for _u in "${_RESOLVED_USERS[@]}"; do
      [[ -z "$_u" ]] && continue
      local _home
      _home="$(shell__resolve_home "$_u")"
      [ -z "$_home" ] && continue
      _node_write_nvm_rc --home "$_home"
    done

  elif [ "$METHOD" = "binary" ]; then
    # Binaries already on PATH when prefix is /usr/local
    if [ "$PREFIX" = "/usr/local" ]; then
      logging__info "prefix=/usr/local — PATH write not needed (already on PATH)."
    else
      local _content="export PATH=\"${PREFIX}/bin:\${PATH}\""
      local _marker="node PATH (install-node)"

      # System-wide
      local _sys_files
      if [ "${EXPORT_PATH[*]}" != "auto" ]; then
        _sys_files="$(printf '%s\n' "${EXPORT_PATH[@]}")"
      else
        _sys_files="$(shell__system_path_files --profile_d 'node_path.sh')"
      fi
      shell__sync_block --files "$_sys_files" --marker "$_marker" --content "$_content"

      # Per-user
      for _u in "${_RESOLVED_USERS[@]}"; do
        [[ -z "$_u" ]] && continue
        local _home
        _home="$(shell__resolve_home "$_u")"
        [ -z "$_home" ] && continue
        local _user_files
        _user_files="$(shell__user_path_files --home "$_home")"
        shell__sync_block --files "$_user_files" --marker "$_marker" --content "$_content"
      done
    fi
  fi

  logging__fn_exit "_node_configure_path"
  return 0
}

# _node_install_pnpm
# Installs pnpm globally after Node.js is installed.
_node_install_pnpm() {
  logging__fn_entry "_node_install_pnpm"
  if [ "$PNPM_VERSION" = "none" ]; then
    logging__fn_exit "_node_install_pnpm (skipped: pnpm_version=none)"
    return 0
  fi
  if [ "$VERSION" = "none" ]; then
    logging__warn "Skipping pnpm install: no Node.js version was installed (version=none)."
    logging__fn_exit "_node_install_pnpm (skipped: version=none)"
    return 0
  fi

  logging__info "Installing pnpm@${PNPM_VERSION}..."
  if [ "$METHOD" = "nvm" ]; then
    su "$_NVM_USER" -c "export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && npm install -g 'pnpm@${PNPM_VERSION}'"
  else
    npm install -g "pnpm@${PNPM_VERSION}"
  fi

  pnpm --version
  logging__success "pnpm installed."
  logging__fn_exit "_node_install_pnpm"
  return 0
}

# _node_install_yarn
# Installs Yarn globally after Node.js is installed.
_node_install_yarn() {
  logging__fn_entry "_node_install_yarn"
  if [ "$YARN_VERSION" = "none" ]; then
    logging__fn_exit "_node_install_yarn (skipped: yarn_version=none)"
    return 0
  fi
  if [ "$VERSION" = "none" ]; then
    logging__warn "Skipping yarn install: no Node.js version was installed (version=none)."
    logging__fn_exit "_node_install_yarn (skipped: version=none)"
    return 0
  fi

  logging__info "Installing yarn@${YARN_VERSION}..."

  local _install_cmd
  if [ "$YARN_VERSION" = "latest" ]; then
    if command -v corepack > /dev/null 2>&1; then
      _install_cmd="corepack enable"
    else
      _install_cmd="npm install -g yarn"
    fi
  else
    _install_cmd="npm install -g 'yarn@${YARN_VERSION}'"
  fi

  if [ "$METHOD" = "nvm" ]; then
    su "$_NVM_USER" -c "export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && ${_install_cmd}"
  else
    eval "$_install_cmd"
  fi

  yarn --version
  logging__success "yarn installed."
  logging__fn_exit "_node_install_yarn"
  return 0
}

# shellcheck source=lib/github.sh
. "${_SELF_DIR}/_lib/github.sh"
# shellcheck source=lib/verify.sh
. "${_SELF_DIR}/_lib/verify.sh"
# shellcheck source=lib/shell.sh
. "${_SELF_DIR}/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "${_SELF_DIR}/_lib/users.sh"
# shellcheck source=lib/file.sh
. "${_SELF_DIR}/_lib/file.sh"

os__require_root

# =============================================================================
# Resolve user list
# =============================================================================

mapfile -t _RESOLVED_USERS < <(users__resolve_list)

# _NVM_USER: the user under whom nvm operations are run.
# When set_permissions=true and running as root, use the first resolved user.
# Otherwise fall back to the current user.
_NVM_USER=""
if [ "$SET_PERMISSIONS" = "true" ] && [ "${#_RESOLVED_USERS[@]}" -gt 0 ] && [ -n "${_RESOLVED_USERS[0]}" ]; then
  _NVM_USER="${_RESOLVED_USERS[0]}"
else
  _NVM_USER="$(id -nu)"
fi

# =============================================================================
# Resolve auto values
# =============================================================================

_node_resolve_nvm_dir

# =============================================================================
# Pre-install check
# =============================================================================

# For binary method: resolve exact version now (before if_exists check)
# so the version comparison can be made.
_NODE_VERSION=""
if [ "$METHOD" = "binary" ] && [ "$VERSION" != "none" ]; then
  logging__info "Resolving Node.js version for binary install..."
  mkdir -p "$INSTALLER_DIR"
  net__fetch_url_file \
    "https://nodejs.org/dist/index.json" \
    "${INSTALLER_DIR}/index.json"
  _NODE_VERSION="$(_node_resolve_binary_version "$VERSION" "${INSTALLER_DIR}/index.json")"
  logging__info "Resolved Node.js version: ${_NODE_VERSION}"
fi

_node_check_if_exists

# =============================================================================
# Method-specific OS dependencies
# =============================================================================

if [ "$METHOD" = "nvm" ]; then
  logging__info "Installing nvm runtime dependencies..."
  _run_deps__install_nvm_runtime
  logging__info "Installing nvm build dependencies..."
  _build_deps__install_nvm
fi

if [ "$NODE_GYP_DEPS" = "true" ]; then
  # Skip node-gyp deps on Alpine+nvm (already covered by nvm.yaml build toolchain)
  if [ "$METHOD" = "nvm" ] && [ "$(os__platform)" = "alpine" ]; then
    logging__info "Alpine+nvm detected — node-gyp build tools already provided by nvm.yaml; skipping node-gyp.yaml."
  else
    logging__info "Installing node-gyp build dependencies..."
    _run_deps__install_node_gyp
    if [ "$(os__platform)" = "macos" ]; then
      logging__info "node-gyp build dependencies on macOS require Xcode Command Line Tools."
      logging__info "Install them with: xcode-select --install"
    fi
  fi
fi

if [ "$METHOD" = "binary" ]; then
  if [ "$(os__platform)" = "alpine" ]; then
    logging__error "method=binary is not supported on Alpine Linux (glibc-only binaries)."
    logging__info "Use method=nvm instead — nvm will compile Node.js from source on Alpine."
    exit 1
  fi
fi

# =============================================================================
# Main installation logic
# =============================================================================

if [ "$METHOD" = "nvm" ]; then
  _node_install_via_nvm
elif [ "$METHOD" = "binary" ]; then
  _node_install_via_binary
fi

_node_create_symlinks
_node_configure_path

# Additional package managers
if [ "$PNPM_VERSION" != "none" ] && [ "$VERSION" != "none" ]; then
  _node_install_pnpm
fi

if [ "$YARN_VERSION" != "none" ] && [ "$VERSION" != "none" ]; then
  _node_install_yarn
fi

# =============================================================================
# Verification
# =============================================================================

if [ "$VERSION" != "none" ] && [ -n "${_NODE_VERSION:-}" ]; then
  logging__info "Verifying Node.js installation..."
  if [ "$METHOD" = "nvm" ]; then
    su "$_NVM_USER" -c "export NVM_SYMLINK_CURRENT=true && . '${NVM_DIR}/nvm.sh' && node --version && npm --version"
  else
    node --version
    npm --version
  fi
  logging__success "Node.js ${_NODE_VERSION} is ready."
fi
