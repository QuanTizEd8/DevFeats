_shfmt__resolve_version() {
  local _spec="$1"
  local _out
  _out="$(github__resolve_version "${GH_REPO}" "$_spec")" || return 1
  printf '%s\n' "${_out#*$'\n'}"
}

_shfmt__install_release() {
  local _version="${1-}"
  local _os _arch _asset
  _os="$(os__release_kernel)" || {
    logging__error "install-shfmt: unsupported kernel '$(os__kernel)'."
    return 1
  }
  _arch="$(os__release_arch)" || {
    logging__error "install-shfmt: unsupported architecture '$(os__arch)'."
    return 1
  }
  case "$_arch" in
    amd64 | arm64) ;;
    *)
      logging__error "install-shfmt: unsupported architecture '${_arch}'."
      return 1
      ;;
  esac
  _asset="shfmt_v${_version}_${_os}_${_arch}"
  github__install_release \
    --repo "${GH_REPO}" --tag "v${_version}" \
    --asset "$_asset" --binary-dest "${PREFIX%/}/bin/shfmt" \
    --installer-dir "${INSTALLER_DIR}" ||
    return 1
}

_shfmt__install_repos() {
  local _repos_manifest="${1-}"
  ospkg__run --manifest "$_repos_manifest" --skip_installed || {
    logging__error "install-shfmt: package install failed."
    return 1
  }
  command -v shfmt 2> /dev/null || {
    logging__error "install-shfmt: shfmt not found on PATH after package install."
    return 1
  }
}

# Resolve an existing install: skip, fail, or continue to reinstall.
_shfmt__handle_existing() {
  local _shfmt_path="${1-}" _if_exists="${2-}"
  [[ -n "$_shfmt_path" ]] || return 0
  case "$_if_exists" in
    fail)
      logging__error "install-shfmt: shfmt already exists at $_shfmt_path."
      return 1
      ;;
    skip)
      logging__info "install-shfmt: shfmt already installed at $_shfmt_path — skipping."
      exit 0
      ;;
  esac
}
_shfmt_path="$(command -v shfmt 2> /dev/null || true)"
_shfmt__handle_existing "$_shfmt_path" "$IF_EXISTS"

case "$METHOD" in
  binary)
    _resolved="$(_shfmt__resolve_version "$VERSION")" || {
      logging__error "install-shfmt: could not resolve version '${VERSION}'."
      exit 1
    }
    _shfmt__install_release "$_resolved"
    ;;
  package)
    _shfmt__install_repos "${_FEAT_DIR}/dependencies/run/os-pkg.yaml"
    ;;
  auto)
    _resolved="$(_shfmt__resolve_version "$VERSION" 2> /dev/null || true)"
    if [[ -n "$_resolved" ]] && _shfmt__install_release "$_resolved" 2> /dev/null; then
      METHOD=binary
    else
      _shfmt__install_repos "${_FEAT_DIR}/dependencies/run/os-pkg.yaml"
      METHOD=package
    fi
    ;;
  *)
    logging__error "install-shfmt: invalid method '${METHOD}'."
    exit 1
    ;;
esac
