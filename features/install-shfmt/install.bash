#!/usr/bin/env bash
# shellcheck source=lib/verify.sh
. "${_SELF_DIR}/_lib/verify.sh"
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

_shfmt__resolve_version() {
  local _version="${1-}"
  if [[ -z "$_version" || "$_version" == "latest" ]]; then
    _version="$(github__latest_tag "mvdan/sh" 2> /dev/null || true)"
  fi
  _version="${_version#v}"
  [[ "$_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$_version"
}

_shfmt__resolve_prefix() {
  if [[ -z "${PREFIX}" || "${PREFIX}" == "auto" ]]; then
    PREFIX="$(users__default_prefix)"
  fi
}

_shfmt__platform_arch() {
  local _os _arch
  case "$(os__kernel)" in
    Linux) _os="linux" ;;
    Darwin) _os="darwin" ;;
    *)
      logging__error "install-shfmt: unsupported kernel '$(os__kernel)'."
      return 1
      ;;
  esac
  case "$(os__arch)" in
    x86_64) _arch="amd64" ;;
    aarch64 | arm64) _arch="arm64" ;;
    *)
      logging__error "install-shfmt: unsupported architecture '$(os__arch)'."
      return 1
      ;;
  esac
  printf '%s %s\n' "$_os" "$_arch"
}

_shfmt__install_release() {
  local _version="${1-}"
  local _os _arch _asset _tmp _dest
  read -r _os _arch <<< "$(_shfmt__platform_arch)" || return 1
  _asset="shfmt_v${_version}_${_os}_${_arch}"
  _tmp="$(logging__tmpdir "install/shfmt")"
  _download_deps__install

  github__fetch_release_asset_tarball "mvdan/sh" "v${_version}" "${_asset}" "${_tmp}/${_asset}" || return 1
  chmod +x "${_tmp}/${_asset}" || return 1

  _dest="${PREFIX%/}/bin/shfmt"
  mkdir -p "$(dirname "$_dest")" || return 1
  if command -v install > /dev/null 2>&1; then
    install -m 0755 "${_tmp}/${_asset}" "$_dest" || return 1
  else
    cp "${_tmp}/${_asset}" "$_dest" || return 1
    chmod 0755 "$_dest" || return 1
  fi
  printf '%s\n' "$_dest"
}

_shfmt__install_repos() {
  local _repos_manifest="${1-}"
  ospkg__run --manifest "$_repos_manifest" --skip_installed || return 1
  command -v shfmt 2> /dev/null || return 1
}

# Resolve an existing install: skip, fail, or continue to reinstall.
_shfmt__handle_existing() {
  local _existing="${1-}" _if_exists="${2-}"
  [[ -n "$_existing" ]] || return 0
  case "$_if_exists" in
    fail)
      logging__error "install-shfmt: shfmt already exists at $_existing."
      return 1
      ;;
    skip)
      logging__info "install-shfmt: shfmt already installed at $_existing — skipping."
      exit 0
      ;;
  esac
}

_shfmt__create_symlink() {
  if [[ "${SYMLINK}" != "true" ]]; then
    logging__info "symlink=false; skipping symlink creation."
    return 0
  fi
  if [[ "${METHOD}" == "repos" ]]; then
    logging__info "method=repos; symlink not applicable."
    return 0
  fi
  if [[ ! -x "${PREFIX}/bin/shfmt" ]]; then
    return 0
  fi
  shell__create_symlink \
    --src "${PREFIX}/bin/shfmt" \
    --system-target "/usr/local/bin/shfmt" \
    --user-target "${HOME}/.local/bin/shfmt"
}

_shfmt__resolve_prefix
_existing="$(command -v shfmt 2> /dev/null || true)"
_shfmt__handle_existing "$_existing" "$IF_EXISTS"

case "$METHOD" in
  release)
    _resolved="$(_shfmt__resolve_version "$VERSION")" || {
      logging__error "install-shfmt: could not resolve version '${VERSION}'."
      exit 1
    }
    _shfmt__install_release "$_resolved"
    ;;
  repos)
    _shfmt__install_repos "${_BASE_DIR}/dependencies/run/os-pkg.yaml"
    ;;
  auto)
    _resolved="$(_shfmt__resolve_version "$VERSION" 2> /dev/null || true)"
    if [[ -n "$_resolved" ]] && _shfmt__install_release "$_resolved" 2> /dev/null; then
      :
    else
      _shfmt__install_repos "${_BASE_DIR}/dependencies/run/os-pkg.yaml"
    fi
    ;;
  *)
    logging__error "install-shfmt: invalid method '${METHOD}'."
    exit 1
    ;;
esac

_shfmt__create_symlink
