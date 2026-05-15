#!/usr/bin/env bash
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_INSTALL_ORAS__LIB_LOADED-}" ]] && return 0
_INSTALL_ORAS__LIB_LOADED=1

_INSTALL_ORAS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/install/common.sh
. "${_INSTALL_ORAS_LIB_DIR}/common.sh"
# shellcheck source=lib/os.sh
. "${_INSTALL_ORAS_LIB_DIR}/../os.sh"
# shellcheck source=lib/str.sh
. "${_INSTALL_ORAS_LIB_DIR}/../str.sh"
# shellcheck source=lib/file.sh
. "${_INSTALL_ORAS_LIB_DIR}/../file.sh"
# shellcheck source=lib/ospkg.sh
. "${_INSTALL_ORAS_LIB_DIR}/../ospkg.sh"
# shellcheck source=lib/github.sh
. "${_INSTALL_ORAS_LIB_DIR}/../github.sh"
# shellcheck source=lib/net.sh
. "${_INSTALL_ORAS_LIB_DIR}/../net.sh"
# shellcheck source=lib/verify.sh
[[ -z "${_VERIFY__LIB_LOADED-}" ]] && . "${_INSTALL_ORAS_LIB_DIR}/../verify.sh"

# @brief _install__oras_resolve_version <version|latest> — Resolve requested version to bare semver (no leading `v`).
_install__oras_resolve_version() {
  local _version="${1-}"
  if [[ -z "$_version" || "$_version" == "latest" ]]; then
    _version="$(github__latest_tag "oras-project/oras" 2> /dev/null || true)"
    _version="${_version#v}"
  fi
  [[ -n "$_version" ]] || return 1
  printf '%s\n' "${_version#v}"
}

# @brief _install__oras_install_release <version> <prefix> <group> <context> <download_url> — Install ORAS from release artifact with mandatory checksum+GPG verification.
#
# Downloads the release tarball and its detached GPG signature from GitHub,
# verifies both before extracting, then installs the `oras` binary to
# `<prefix>/bin/oras`. The `--download-url` parameter is intentionally rejected
# because bypassing GitHub releases would skip the mandatory GPG verification.
# Temporary files are managed by `file__tmpdir` and cleaned up automatically
# by `logging__cleanup` at script exit.
#
# Args:
#   <version>       Bare semver string (no leading `v`), e.g. `1.2.3`.
#   <prefix>        Installation prefix; binary goes to `<prefix>/bin/oras`.
#   <group>         Resource-tracking group ID (e.g. `lib-oci-oras`).
#   <context>       `internal` or `user`; controls cleanup tracking.
#   <download_url>  Must be empty — supplying a value causes an immediate error.
#
# Stdout: absolute path to the installed binary on success.
# Returns: 0 on success, 1 on any failure.
_install__oras_install_release() {
  local _version="${1-}" _install_prefix="${2-}" _group="${3-}" _context="${4-}" _download_url="${5-}"
  local _platform _arch _asset _tmp _bin_src _bin_dest _tag
  _platform="$(os__release_kernel)" || return 1
  _arch="$(os__release_arch)" || return 1
  case "$_arch" in
    amd64 | arm64 | armv7 | ppc64le | s390x | riscv64 | loong64) ;;
    *)
      logging__error "install__oras: unsupported architecture '${_arch}'."
      return 1
      ;;
  esac
  _tag="v${_version#v}"
  _asset="oras_${_version#v}_${_platform}_${_arch}.tar.gz"
  _tmp="$(file__tmpdir "install/oras")"
  if [[ -n "$_download_url" ]]; then
    logging__error "install__oras: --download-url is not supported because checksum+GPG verification is mandatory."
    return 1
  fi
  github__fetch_release_asset_tarball "oras-project/oras" "$_tag" "$_asset" "${_tmp}/${_asset}" || return 1
  net__fetch_url_file "https://github.com/oras-project/oras/releases/download/${_tag}/${_asset}.asc" "${_tmp}/${_asset}.asc" || return 1
  net__fetch_url_file "https://raw.githubusercontent.com/oras-project/oras/refs/heads/main/KEYS" "${_tmp}/KEYS" || return 1
  verify__gpg_detached "${_tmp}/${_asset}" "${_tmp}/${_asset}.asc" "${_tmp}/KEYS" "$_group" || {
    logging__error "install__oras: signature verification failed for ${_asset}."
    return 1
  }
  file__extract_archive "${_tmp}/${_asset}" "$_tmp" || return 1
  _bin_src="${_tmp}/oras"
  [[ -x "$_bin_src" ]] || {
    logging__error "install__oras: extracted binary '${_bin_src}' not found or not executable."
    return 1
  }
  _bin_dest="${_install_prefix%/}/bin/oras"
  install__copy_bin "$_bin_src" "$_bin_dest" || return 1
  if [[ "$_context" == "internal" ]]; then
    install__track_internal_path "$_group" "$_bin_dest"
  fi
  install__state_record "oras" "$_context" "binary" "$_bin_dest" "$_group" || true
  printf '%s\n' "$_bin_dest"
  return 0
}

# @brief _install__oras_install_repos <version> <group> <context> [repos-manifest] — Install ORAS via system package manager.
_install__oras_install_repos() {
  local _version="${1-}" _group="${2-}" _context="${3-}" _repos_manifest="${4-}"
  if [[ -n "$_repos_manifest" && "$_context" == "user" ]]; then
    ospkg__run --manifest "$_repos_manifest" --skip_installed || return 1
    local _bin_from_manifest
    _bin_from_manifest="$(command -v oras 2> /dev/null || true)"
    [[ -n "$_bin_from_manifest" ]] || {
      logging__error "install__oras: oras not found on PATH after manifest install."
      return 1
    }
    install__state_record "oras" "$_context" "package" "$_bin_from_manifest" "$_group" || true
    printf '%s\n' "$_bin_from_manifest"
    return 0
  fi
  local _manifest
  if [[ -n "$_version" && "$_version" != "latest" ]]; then
    read -r -d '' _manifest << EOF || true
packages:
  - name: oras
    apt: "oras=${_version}"
EOF
  else
    read -r -d '' _manifest << 'EOF' || true
packages:
  - oras
EOF
  fi
  if [[ "$_context" == "user" ]]; then
    ospkg__run --manifest "$_manifest" --skip_installed || return 1
  else
    ospkg__run --manifest "$_manifest" --build-group "$_group" --skip_installed || return 1
  fi
  local _bin
  _bin="$(command -v oras 2> /dev/null || true)"
  [[ -n "$_bin" ]] || {
    logging__error "install__oras: oras not found on PATH after package install."
    return 1
  }
  install__state_record "oras" "$_context" "package" "$_bin" "$_group" || true
  printf '%s\n' "$_bin"
  return 0
}

# @brief install__oras --context <internal|user> [--version <ver|latest>] [--min-version <ver>] [--method <auto|binary|package>] [--prefix <path|auto>] [--if-exists <skip|fail|reinstall>] [--download-url <url>] [--repos-manifest <path>] [--owner-group <id>] — Ensure ORAS is installed with context-aware ownership semantics and mandatory checksum+GPG verification for release artifacts.
install__oras() {
  local _context="internal" _version="latest" _min_version="" _method="auto" _install_prefix="auto"
  local _if_exists="skip" _download_url="" _repos_manifest="" _owner_group="lib-oci-oras"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context)
        shift
        _context="${1-}"
        ;;
      --version)
        shift
        _version="${1-}"
        ;;
      --min-version)
        shift
        _min_version="${1-}"
        ;;
      --method)
        shift
        _method="${1-}"
        ;;
      --prefix)
        shift
        _install_prefix="${1-}"
        ;;
      --if-exists)
        shift
        _if_exists="${1-}"
        ;;
      --download-url)
        shift
        _download_url="${1-}"
        ;;
      --repos-manifest)
        shift
        _repos_manifest="${1-}"
        ;;
      --owner-group)
        shift
        _owner_group="${1-}"
        ;;
      *)
        logging__error "install__oras: unknown option '$1'"
        return 1
        ;;
    esac
    shift
  done
  [[ "$_context" == "internal" || "$_context" == "user" ]] || return 1
  [[ -n "$_owner_group" ]] || _owner_group="install-oras"

  local _existing _existing_ver _state_ctx _state_path _state_group
  _existing="$(command -v oras 2> /dev/null || true)"
  install__read_state "oras" _state_ctx _state_path _state_group
  if [[ -n "$_existing" && "$_context" == "user" && "$_state_ctx" == "internal" ]]; then
    install__promote_path_to_user "${_state_group:-$_owner_group}" "$_state_path"
    install__state_record "oras" "user" "${_method}" "${_existing}" "$_owner_group" || true
    _state_ctx="user"
  fi
  if [[ -n "$_existing" ]]; then
    _existing_ver="$("$_existing" version 2> /dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n1)"
    [[ -z "$_existing_ver" ]] && _existing_ver="$("$_existing" version 2> /dev/null | head -n1 | sed 's/.*version[[:space:]]\+//I')"
    if [[ -n "$_min_version" ]] && str__semver_ge "${_existing_ver:-0}" "$_min_version"; then
      printf '%s\n' "$_existing"
      return 0
    fi
    if [[ "$_context" == "internal" && "$_state_ctx" == "user" ]]; then
      printf '%s\n' "$_existing"
      return 0
    fi
    if [[ "$_if_exists" == "fail" ]]; then
      logging__error "install__oras: oras already exists at $_existing."
      return 1
    fi
    if [[ "$_if_exists" == "skip" && -z "$_min_version" ]]; then
      printf '%s\n' "$_existing"
      return 0
    fi
  fi

  if [[ "$_install_prefix" == "auto" || -z "$_install_prefix" ]]; then
    if users__is_root; then
      _install_prefix="/usr/local"
    else
      _install_prefix="${HOME}/.local"
    fi
  fi
  _version="$(_install__oras_resolve_version "$_version")" || return 1
  case "$_method" in
    binary)
      _install__oras_install_release "$_version" "$_install_prefix" "$_owner_group" "$_context" "$_download_url"
      ;;
    package)
      _install__oras_install_repos "$_version" "$_owner_group" "$_context" "$_repos_manifest"
      ;;
    auto)
      _install__oras_install_release "$_version" "$_install_prefix" "$_owner_group" "$_context" "$_download_url" ||
        _install__oras_install_repos "$_version" "$_owner_group" "$_context" "$_repos_manifest"
      ;;
    *)
      logging__error "install__oras: invalid method '${_method}'."
      return 1
      ;;
  esac
}
