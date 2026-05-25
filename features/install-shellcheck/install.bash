resolve_input_version() {
  local _spec="$1"
  local _out
  _out="$(github__resolve_version "${GH_REPO}" "$_spec")" || return 1
  printf '%s\n' "${_out#*$'\n'}"
}

install_binary() {
  local _version="${1-}"
  local _os _arch _asset
  _os="$(os__release_kernel)" || return 1
  _arch="$(os__arch)"
  case "$_arch" in
    x86_64) ;;
    aarch64 | arm64)
      if [[ "$_os" == "darwin" ]]; then
        logging__debug "install-shellcheck: no release binary for darwin/arm64; falling back to package."
        return 1
      fi
      _arch="aarch64"
      ;;
    *)
      logging__error "install-shellcheck: unsupported architecture '${_arch}'."
      return 1
      ;;
  esac
  _asset="shellcheck-v${_version}.${_os}.${_arch}.tar.xz"
  github__install_release \
    --repo "${GH_REPO}" --tag "v${_version}" \
    --asset "$_asset" --binary-src shellcheck --binary-dest "${PREFIX%/}/bin/" \
    --installer-dir "${INSTALLER_DIR}" ||
    return 1
}

install_package() {
  local _repos_manifest="${1-}"
  ospkg__run --manifest "$_repos_manifest" --skip_installed || return 1
  command -v shellcheck 2> /dev/null || {
    logging__error "install-shellcheck: shellcheck not found on PATH after package install."
    return 1
  }
}

_shellcheck__handle_existing() {
  local _shellcheck_path="${1-}" _if_exists="${2-}"
  [[ -n "$_shellcheck_path" ]] || return 0
  case "$_if_exists" in
    fail)
      logging__error "install-shellcheck: shellcheck already exists at $_shellcheck_path."
      return 1
      ;;
    skip)
      logging__info "install-shellcheck: shellcheck already installed at $_shellcheck_path — skipping."
      exit 0
      ;;
  esac
}
_shellcheck_path="$(command -v shellcheck 2> /dev/null || true)"
_shellcheck__handle_existing "$_shellcheck_path" "$IF_EXISTS"

case "$METHOD" in
  binary)
    _resolved="$(resolve_input_version "$VERSION")" || {
      logging__error "install-shellcheck: could not resolve version '${VERSION}'."
      exit 1
    }
    install_binary "$_resolved"
    ;;
  package)
    install_package "${_FEAT_DIR}/dependencies/run/os-pkg.yaml"
    ;;
  auto)
    _resolved="$(resolve_input_version "$VERSION" 2> /dev/null || true)"
    if [[ -n "$_resolved" ]] && install_binary "$_resolved" 2> /dev/null; then
      METHOD=binary
    else
      install_package "${_FEAT_DIR}/dependencies/run/os-pkg.yaml"
      METHOD=package
    fi
    ;;
  *)
    logging__error "install-shellcheck: invalid method '${METHOD}'."
    exit 1
    ;;
esac
