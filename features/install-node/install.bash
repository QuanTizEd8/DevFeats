_cleanup_hook() {
  logging__fn_entry "_cleanup_hook"
  if [ "${_NVM_CLEANUP_ENABLED-}" = "true" ] && [ -n "${NVM_DIR-}" ] && [ -f "${NVM_DIR}/nvm.sh" ] && [ -n "${_NVM_USER-}" ]; then
    su "$_NVM_USER" -c ". '${NVM_DIR}/nvm.sh' && nvm clear-cache" 2> /dev/null || true
  fi
  logging__fn_exit "_cleanup_hook"
}

# _node_build_platform_string <arch>
# Outputs a nodejs.org platform string (e.g. linux-x64, darwin-arm64).
# Argument: raw arch string (uname -m output or user-supplied $ARCH override).
_node_build_platform_string() {
  logging__fn_entry "_node_build_platform_string"
  local _arch="$1"
  local _os _arch_token
  _os="$(os__release_kernel)" || {
    logging__error "Unsupported kernel for Node.js binary install: '$(os__kernel)'."
    return 1
  }
  _arch_token="$(os__release_arch "$_arch" --flavor node)" || {
    logging__error "Unsupported architecture for Node.js binary install: '${_arch}'."
    logging__info "Use method=nvm for source-based installation on unsupported architectures."
    return 1
  }
  local _platform="${_os}-${_arch_token}"
  printf '%s\n' "$_platform"
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

# _resolve_nvm_install_user
# Resolves the user under whom nvm operations are run (method=nvm only).
# Explicit INSTALL_USER → SUDO_USER (non-root) → _REMOTE_USER (non-root) → id -nu.
_resolve_nvm_install_user() {
  if [ -n "${INSTALL_USER:-}" ]; then
    printf '%s\n' "${INSTALL_USER}"
    return 0
  fi
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    printf '%s\n' "${SUDO_USER}"
    return 0
  fi
  if [ -n "${_REMOTE_USER:-}" ] && [ "${_REMOTE_USER}" != "root" ]; then
    printf '%s\n' "${_REMOTE_USER}"
    return 0
  fi
  printf '%s\n' "$(id -nu)"
}

# _node_install_via_nvm
# Full nvm-based installation flow.
_node_install_via_nvm() {
  logging__fn_entry "_node_install_via_nvm"
  local _nvm_tag

  # Resolve nvm tag
  case "$NVM_VERSION" in
    stable | latest)
      logging__info "Resolving nvm release tag for spec '${NVM_VERSION}'..."
      local _nvm_out
      _nvm_out="$(github__resolve_version "nvm-sh/nvm" "$NVM_VERSION")" || {
        logging__error "Failed to resolve nvm release from GitHub."
        return 1
      }
      _nvm_tag="${_nvm_out%%$'\n'*}"
      logging__info "Resolved nvm tag: ${_nvm_tag}"
      ;;
    *)
      _nvm_tag="v${NVM_VERSION#v}"
      ;;
  esac

  logging__info "Installing nvm ${_nvm_tag}..."

  # Download nvm install script
  mkdir -p "$INSTALLER_DIR"
  uri__fetch_asset \
    "https://raw.githubusercontent.com/nvm-sh/nvm/${_nvm_tag}/install.sh" \
    --file-dest "${INSTALLER_DIR}/nvm-install.sh" > /dev/null

  # Create NVM_DIR before write_group permissions (which chowns it)
  mkdir -p "$NVM_DIR"

  # Set permissions so _NVM_USER can write NVM_DIR (before installer runs)
  if [ -n "${NVM_WRITE_GROUP:-}" ] && users__is_root; then
    _nvm_wargs=()
    if [ "${#NVM_WRITE_USERS[@]}" -gt 0 ]; then
      _nvm_wargs=(--current false --remote false --container false)
      for _u in "${NVM_WRITE_USERS[@]}"; do _nvm_wargs+=(--user "$_u"); done
    fi
    mapfile -t _write_users < <(users__resolve_list "${_nvm_wargs[@]}")
    users__set_write_permissions "$NVM_DIR" "$_NVM_USER" "$NVM_WRITE_GROUP" "${_write_users[@]}"
  fi

  # Mark nvm cleanup as active now that NVM_DIR is initialised
  _NVM_CLEANUP_ENABLED="true"

  # Run nvm installer as target user; pipe via stdin so _NVM_USER never needs
  # filesystem access to the tmpdir (which is root-owned 0700).
  logging__info "Running nvm installer as user '${_NVM_USER}'..."
  su "$_NVM_USER" -c \
    "umask 0002 && PROFILE=/dev/null NVM_SYMLINK_CURRENT=true NVM_DIR='${NVM_DIR}' bash -s" \
    < "${INSTALLER_DIR}/nvm-install.sh"

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
  local _arch_str="${ARCH:-$(os__arch)}"
  local _platform
  _platform="$(_node_build_platform_string "$_arch_str")" || {
    logging__error "install-node: could not determine platform string for arch '${_arch_str}'."
    return 1
  }

  # Resolve install prefix
  local _install_prefix="$PREFIX"
  if [ -z "$_install_prefix" ]; then
    _install_prefix="/usr/local"
  fi

  # Resolve exact version (may already be set from pre-install check step)
  mkdir -p "$INSTALLER_DIR"
  if [ -z "${_NODE_VERSION:-}" ]; then
    logging__info "Downloading Node.js release index..."
    uri__fetch_asset \
      "https://nodejs.org/dist/index.json" \
      --file-dest "${INSTALLER_DIR}/index.json" > /dev/null
    _NODE_VERSION="$(_node_resolve_binary_version "$VERSION" "${INSTALLER_DIR}/index.json")"
  fi

  logging__info "Installing Node.js ${_NODE_VERSION} (${_platform}) to ${_install_prefix}..."

  local _tarball="node-${_NODE_VERSION}-${_platform}.tar.xz"
  local _node_dist_dir="node-${_NODE_VERSION}-${_platform}"

  uri__fetch_asset \
    "https://nodejs.org/dist/${_NODE_VERSION}/${_tarball}" \
    --sidecar "https://nodejs.org/dist/${_NODE_VERSION}/SHASUMS256.txt" \
    --installer-dir "${INSTALLER_DIR}" > /dev/null

  # Strip top-level directory (equivalent to --strip 1) by copying contents.
  mkdir -p "$_install_prefix"
  cp -a "${INSTALLER_DIR}/asset/${_node_dist_dir}/." "$_install_prefix/"

  # Update PREFIX with resolved value for use by caller
  PREFIX="$_install_prefix"

  logging__success "Node.js ${_NODE_VERSION} extracted to ${_install_prefix}."
  logging__fn_exit "_node_install_via_binary"
  return 0
}

create_nvm_symlinks() {
  logging__fn_entry "create_nvm_symlinks"
  if [ "${METHOD}" != "nvm" ]; then
    logging__fn_exit "create_nvm_symlinks"
    return 0
  fi
  if ! users__is_root; then
    logging__info "Non-root: NVM bridge symlink not applicable."
    logging__fn_exit "create_nvm_symlinks"
    return 0
  fi
  shell__create_symlink \
    --src "${NVM_DIR}" \
    --system-target "/usr/local/share/nvm" \
    --user-target "${HOME}/.nvm"
  # Create stable executable entrypoints for non-interactive contexts
  # that may not source shell init files.
  for _bin in node npm npx corepack; do
    local _src="${NVM_DIR}/current/bin/${_bin}"
    [ -f "$_src" ] || continue
    logging__info "Symlinking ${_src} → /usr/local/bin/${_bin}"
    ln -sf "$_src" "/usr/local/bin/${_bin}"
  done
  logging__fn_exit "create_nvm_symlinks"
  return
}

_prefix_post_install() {
  _prefix_post_install__generated
  create_nvm_symlinks
}

# shellcheck disable=SC2329,SC2317
nvm_dir_activation_snippet() {
  cat << SNIPPET
export NVM_SYMLINK_CURRENT=true
export NVM_DIR="${NVM_DIR}"
# shellcheck disable=SC1090
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && . "\$NVM_DIR/bash_completion"
SNIPPET
  return 1
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

os__require_root

# =============================================================================
# Resolve nvm install user
# =============================================================================

_NVM_USER="$(_resolve_nvm_install_user)"

# =============================================================================
# Resolve auto values
# =============================================================================

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
