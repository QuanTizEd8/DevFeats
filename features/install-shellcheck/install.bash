#!/usr/bin/env bash
# shellcheck source=lib/checksum.sh
. "${_SELF_DIR}/_lib/checksum.sh"
# shellcheck source=lib/file.sh
. "${_SELF_DIR}/_lib/file.sh"
# shellcheck source=lib/github.sh
. "${_SELF_DIR}/_lib/github.sh"
# shellcheck source=lib/net.sh
. "${_SELF_DIR}/_lib/net.sh"
# shellcheck source=lib/os.sh
. "${_SELF_DIR}/_lib/os.sh"
# shellcheck source=lib/shell.sh
. "${_SELF_DIR}/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "${_SELF_DIR}/_lib/users.sh"

_shellcheck__resolve_version() {
  local _version="${1-}"
  if [[ -z "$_version" || "$_version" == "latest" ]]; then
    _version="$(github__latest_tag "koalaman/shellcheck" 2> /dev/null || true)"
  fi
  _version="${_version#v}"
  [[ "$_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$_version"
}

_shellcheck__resolve_prefix() {
  if [[ -z "${PREFIX}" || "${PREFIX}" == "auto" ]]; then
    PREFIX="$(users__default_prefix)"
  fi
}

# @stdout "<os> <arch>" for the GitHub release asset name, or return 1 when no
# release binary exists for the current platform (e.g. darwin/arm64).
_shellcheck__platform_arch() {
  local _os _arch
  case "$(os__kernel)" in
    Linux) _os="linux" ;;
    Darwin) _os="darwin" ;;
    *)
      logging__error "install-shellcheck: unsupported kernel '$(os__kernel)'."
      return 1
      ;;
  esac
  case "$(os__arch)" in
    x86_64) _arch="x86_64" ;;
    aarch64 | arm64)
      if [[ "$_os" == "darwin" ]]; then
        logging__debug "install-shellcheck: no release binary for darwin/arm64; falling back to repos."
        return 1
      fi
      _arch="aarch64"
      ;;
    *)
      logging__error "install-shellcheck: unsupported architecture '$(os__arch)'."
      return 1
      ;;
  esac
  printf '%s %s\n' "$_os" "$_arch"
}

_shellcheck__install_release() {
  local _version="${1-}"
  local _os _arch _asset _tmp _extracted _dest
  read -r _os _arch <<< "$(_shellcheck__platform_arch)" || return 1
  _asset="shellcheck-v${_version}.${_os}.${_arch}.tar.xz"
  _tmp="$(logging__tmpdir "install/shellcheck")"
  _download_deps__install

  github__fetch_release_asset_tarball "koalaman/shellcheck" "v${_version}" "${_asset}" "${_tmp}/${_asset}" || return 1

  file__extract_archive "${_tmp}/${_asset}" "$_tmp" || return 1
  _extracted="${_tmp}/shellcheck-v${_version}/shellcheck"
  [[ -f "$_extracted" ]] || return 1

  _dest="${PREFIX%/}/bin/shellcheck"
  mkdir -p "$(dirname "$_dest")" || return 1
  if command -v install > /dev/null 2>&1; then
    install -m 0755 "$_extracted" "$_dest" || return 1
  else
    cp "$_extracted" "$_dest" || return 1
    chmod 0755 "$_dest" || return 1
  fi
  printf '%s\n' "$_dest"
}

_shellcheck__install_repos() {
  local _repos_manifest="${1-}"
  ospkg__run --manifest "$_repos_manifest" --skip_installed || return 1
  command -v shellcheck 2> /dev/null || return 1
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

_shellcheck__create_symlink() {
  if [[ "${SYMLINK}" != "true" ]]; then
    logging__info "symlink=false; skipping symlink creation."
    return 0
  fi
  if [[ "${METHOD}" == "repos" ]]; then
    logging__info "method=repos; symlink not applicable."
    return 0
  fi
  if [[ ! -x "${PREFIX}/bin/shellcheck" ]]; then
    return 0
  fi
  shell__create_symlink \
    --src "${PREFIX}/bin/shellcheck" \
    --system-target "/usr/local/bin/shellcheck" \
    --user-target "${HOME}/.local/bin/shellcheck"
}

_shellcheck__resolve_prefix
_existing="$(command -v shellcheck 2> /dev/null || true)"
_shellcheck__handle_existing "$_existing" "$IF_EXISTS"

case "$METHOD" in
  release)
    _resolved="$(_shellcheck__resolve_version "$VERSION")" || {
      logging__error "install-shellcheck: could not resolve version '${VERSION}'."
      exit 1
    }
    _shellcheck__install_release "$_resolved"
    ;;
  repos)
    _shellcheck__install_repos "${_BASE_DIR}/dependencies/run/os-pkg.yaml"
    ;;
  auto)
    _resolved="$(_shellcheck__resolve_version "$VERSION" 2> /dev/null || true)"
    if [[ -n "$_resolved" ]] && _shellcheck__install_release "$_resolved" 2> /dev/null; then
      :
    else
      _shellcheck__install_repos "${_BASE_DIR}/dependencies/run/os-pkg.yaml"
    fi
    ;;
  *)
    logging__error "install-shellcheck: invalid method '${METHOD}'."
    exit 1
    ;;
esac

_shellcheck__create_symlink
