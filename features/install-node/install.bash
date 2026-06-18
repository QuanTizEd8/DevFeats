__resolve_version() {
  logging__info "Resolving Node.js version from nodejs.org..."
  file__mkdir "$INSTALLER_DIR"
  logging__download "Fetching Node.js version index from 'https://nodejs.org/dist/index.json'."
  uri__fetch_asset \
    "https://nodejs.org/dist/index.json" \
    --file-dest "${INSTALLER_DIR}/index.json" > /dev/null
  npm__resolve_node_version "$VERSION" --index-file "${INSTALLER_DIR}/index.json"
}

__install_run_binary_pre() {
  if [ "$(os__platform)" = "alpine" ]; then
    logging__error "method=binary is not supported on Alpine Linux (glibc-only binaries)."
    logging__info "Use install-nvm instead — nvm will compile Node.js from source on Alpine."
    return 1
  fi

  if [ "${NODE_GYP_DEPS}" = "true" ] && [ "$(os__platform)" = "macos" ]; then
    bootstrap__xcode
  fi

  local _platform
  logging__info "Resolving Node.js binary platform triple."
  _platform="$(npm__node_platform)"
  declare -g _NODE_DIST_DIR="node-${VERSION}-${_platform}"
  logging__info "Installing Node.js ${VERSION} (${_NODE_DIST_DIR}) to ${_RESOLVED_PREFIX}..."
}

__install_run_binary_post() {
  logging__install "Extracting Node.js '${_NODE_DIST_DIR}' into '${_RESOLVED_PREFIX}'."
  file__mkdir "$_RESOLVED_PREFIX"
  file__cp -a "${INSTALLER_DIR}/asset/${_NODE_DIST_DIR}/." "${_RESOLVED_PREFIX}/"
  logging__success "Node.js ${VERSION} (${_NODE_DIST_DIR}) extracted to ${_RESOLVED_PREFIX}."
}
