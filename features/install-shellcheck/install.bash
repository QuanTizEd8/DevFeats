#!/usr/bin/env bash
# shellcheck source=lib/checksum.sh
. "${_SELF_DIR}/_lib/checksum.sh"
# shellcheck source=lib/github.sh
. "${_SELF_DIR}/_lib/github.sh"
# shellcheck source=lib/net.sh
. "${_SELF_DIR}/_lib/net.sh"
# shellcheck source=lib/os.sh
. "${_SELF_DIR}/_lib/os.sh"
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
  local _version="${1-}" _install_prefix="${2-}"
  local _os _arch _asset _base _tmp _expected_hash _extracted _dest
  read -r _os _arch <<< "$(_shellcheck__platform_arch)" || return 1
  _asset="shellcheck-v${_version}.${_os}.${_arch}.tar.xz"
  _base="https://github.com/koalaman/shellcheck/releases/download/v${_version}"
  _tmp="$(logging__tmpdir "install/shellcheck")"
  _download_deps__install

  net__fetch_url_file "${_base}/${_asset}" "${_tmp}/${_asset}" || return 1
  net__fetch_url_file "${_base}/shellcheck-v${_version}.SHA512" "${_tmp}/shellcheck.SHA512" || return 1
  _expected_hash="$(awk -v f="${_asset}" '$2 == f { print $1; exit }' "${_tmp}/shellcheck.SHA512")"
  if [[ ! "${_expected_hash:-}" =~ ^[0-9a-fA-F]{128}$ ]]; then
    logging__error "install-shellcheck: could not resolve checksum for ${_asset}."
    return 1
  fi
  checksum__verify "${_tmp}/${_asset}" "$_expected_hash" 512 || return 1

  tar -xJf "${_tmp}/${_asset}" -C "$_tmp" || return 1
  _extracted="${_tmp}/shellcheck-v${_version}/shellcheck"
  [[ -f "$_extracted" ]] || return 1

  if [[ -z "$_install_prefix" || "$_install_prefix" == "auto" ]]; then
    _install_prefix="$(users__default_prefix)"
  fi
  _dest="${_install_prefix%/}/bin/shellcheck"
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

_existing="$(command -v shellcheck 2> /dev/null || true)"
_shellcheck__handle_existing "$_existing" "$IF_EXISTS"

case "$METHOD" in
  release)
    _resolved="$(_shellcheck__resolve_version "$VERSION")" || {
      logging__error "install-shellcheck: could not resolve version '${VERSION}'."
      exit 1
    }
    _shellcheck__install_release "$_resolved" "$PREFIX"
    ;;
  repos)
    _shellcheck__install_repos "${_BASE_DIR}/dependencies/run/os-pkg.yaml"
    ;;
  auto)
    _resolved="$(_shellcheck__resolve_version "$VERSION" 2> /dev/null || true)"
    if [[ -n "$_resolved" ]] && _shellcheck__install_release "$_resolved" "$PREFIX" 2> /dev/null; then
      exit 0
    fi
    _shellcheck__install_repos "${_BASE_DIR}/dependencies/run/os-pkg.yaml"
    ;;
  *)
    logging__error "install-shellcheck: invalid method '${METHOD}'."
    exit 1
    ;;
esac
