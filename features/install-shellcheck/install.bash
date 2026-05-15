#!/usr/bin/env bash
# shellcheck source=lib/verify.sh
. "${_BASE_DIR}/_lib/verify.sh"
# shellcheck source=lib/file.sh
. "${_BASE_DIR}/_lib/file.sh"
# shellcheck source=lib/install/common.sh
. "${_BASE_DIR}/_lib/install/common.sh"
# shellcheck source=lib/github.sh
. "${_BASE_DIR}/_lib/github.sh"
# shellcheck source=lib/net.sh
. "${_BASE_DIR}/_lib/net.sh"
# shellcheck source=lib/os.sh
. "${_BASE_DIR}/_lib/os.sh"
# shellcheck source=lib/shell.sh
. "${_BASE_DIR}/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "${_BASE_DIR}/_lib/users.sh"

_shellcheck__resolve_version() {
  local _version="${1-}"
  if [[ -z "$_version" || "$_version" == "latest" ]]; then
    _version="$(github__latest_tag "koalaman/shellcheck" 2> /dev/null || true)"
  fi
  _version="${_version#v}"
  [[ "$_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$_version"
}

_shellcheck__install_release() {
  local _version="${1-}"
  local _os _arch _asset _tmp _extracted _dest
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
  _tmp="$(file__tmpdir "install/shellcheck")"

  github__fetch_release_asset_tarball "koalaman/shellcheck" "v${_version}" "${_asset}" "${_tmp}/${_asset}" || return 1

  file__extract_archive "${_tmp}/${_asset}" "$_tmp" || return 1
  _extracted="${_tmp}/shellcheck-v${_version}/shellcheck"
  [[ -f "$_extracted" ]] || {
    logging__error "install-shellcheck: extracted binary '${_extracted}' not found."
    return 1
  }

  _dest="${PREFIX%/}/bin/shellcheck"
  install__copy_bin "$_extracted" "$_dest" || return 1
  printf '%s\n' "$_dest"
}

_shellcheck__install_repos() {
  local _repos_manifest="${1-}"
  ospkg__run --manifest "$_repos_manifest" --skip_installed || return 1
  command -v shellcheck 2> /dev/null || {
    logging__error "install-shellcheck: shellcheck not found on PATH after package install."
    return 1
  }
}

_shellcheck__handle_existing() {
  local _existing="${1-}" _if_exists="${2-}"
  [[ -n "$_existing" ]] || return 0
  case "$_if_exists" in
    fail)
      logging__error "install-shellcheck: shellcheck already exists at $_existing."
      return 1
      ;;
    skip)
      logging__info "install-shellcheck: shellcheck already installed at $_existing — skipping."
      exit 0
      ;;
  esac
}
_existing="$(command -v shellcheck 2> /dev/null || true)"
_shellcheck__handle_existing "$_existing" "$IF_EXISTS"

case "$METHOD" in
  binary)
    _resolved="$(_shellcheck__resolve_version "$VERSION")" || {
      logging__error "install-shellcheck: could not resolve version '${VERSION}'."
      exit 1
    }
    _shellcheck__install_release "$_resolved"
    ;;
  package)
    _shellcheck__install_repos "${_BASE_DIR}/dependencies/run/os-pkg.yaml"
    ;;
  auto)
    _resolved="$(_shellcheck__resolve_version "$VERSION" 2> /dev/null || true)"
    if [[ -n "$_resolved" ]] && _shellcheck__install_release "$_resolved" 2> /dev/null; then
      METHOD=binary
    else
      _shellcheck__install_repos "${_BASE_DIR}/dependencies/run/os-pkg.yaml"
      METHOD=package
    fi
    ;;
  *)
    logging__error "install-shellcheck: invalid method '${METHOD}'."
    exit 1
    ;;
esac
