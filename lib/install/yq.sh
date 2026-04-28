#!/usr/bin/env bash
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_INSTALL_YQ__LIB_LOADED-}" ]] && return 0
_INSTALL_YQ__LIB_LOADED=1

_INSTALL_YQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/install/common.sh
. "${_INSTALL_YQ_LIB_DIR}/common.sh"
# shellcheck source=lib/checksum.sh
. "${_INSTALL_YQ_LIB_DIR}/../checksum.sh"
# shellcheck source=lib/os.sh
. "${_INSTALL_YQ_LIB_DIR}/../os.sh"
# shellcheck source=lib/ospkg.sh
. "${_INSTALL_YQ_LIB_DIR}/../ospkg.sh"

# @brief _install__yq_compatible <bin> — Return 0 when candidate binary is mikefarah/yq-compatible (`-o=json` supported).
_install__yq_compatible() {
  local _bin="${1-}"
  [[ -n "$_bin" ]] || return 1
  "$_bin" -o=json '.' /dev/null > /dev/null 2>&1
}

# @brief _install__yq_platform_arch — Print `<os> <arch>` tokens used by yq GitHub release assets.
_install__yq_platform_arch() {
  local _os _arch
  _os="$(os__kernel | tr '[:upper:]' '[:lower:]')"
  _arch="$(os__arch)"
  case "$_arch" in
    x86_64) _arch="amd64" ;;
    aarch64 | arm64) _arch="arm64" ;;
    *) return 1 ;;
  esac
  printf '%s %s\n' "$_os" "$_arch"
}

# @brief _install__yq_install_release <context> <group> <prefix> — Install yq from GitHub release assets with checksum verification.
_install__yq_install_release() {
  local _context="${1-}" _group="${2-}" _prefix="${3-}"
  local _os _arch _base _dir _dest _expected_hash _line _final_dest
  read -r _os _arch <<< "$(_install__yq_platform_arch)" || return 1
  _base="https://github.com/mikefarah/yq/releases/latest/download"
  _dir="$(logging__tmpdir "install/yq")"
  _dest="${_dir}/yq_${_os}_${_arch}"
  net__fetch_url_file "${_base}/yq_${_os}_${_arch}" "$_dest" || return 1
  net__fetch_url_file "${_base}/checksums" "${_dir}/checksums" || return 1
  _line="$(sed -n "/ yq_${_os}_${_arch}\$/p" "${_dir}/checksums" | head -n1)"
  _expected_hash="$(printf '%s\n' "$_line" | awk '{print $1}')"
  [[ "${_expected_hash:-}" =~ ^[0-9a-f]{64}$ ]] || return 1
  checksum__verify_sha256 "$_dest" "$_expected_hash" || return 1
  chmod +x "$_dest" || return 1
  _final_dest="$_dest"
  if [[ "$_context" == "user" ]]; then
    if [[ -z "$_prefix" || "$_prefix" == "auto" ]]; then
      if [[ "$(id -u)" -eq 0 ]]; then
        _prefix="/usr/local"
      else
        _prefix="${HOME}/.local"
      fi
    fi
    _final_dest="${_prefix%/}/bin/yq"
    mkdir -p "$(dirname "$_final_dest")" || return 1
    if command -v install > /dev/null 2>&1; then
      install -m 0755 "$_dest" "$_final_dest" || return 1
    else
      cp "$_dest" "$_final_dest" || return 1
      chmod +x "$_final_dest" || return 1
    fi
  fi
  if [[ "$_context" == "internal" ]]; then
    install__track_internal_path "$_group" "$_final_dest"
  fi
  install__state_record "yq" "$_context" "release" "$_final_dest" "$_group" || true
  printf '%s\n' "$_final_dest"
  return 0
}

# @brief _install__yq_install_repos <context> <group> — Install yq via package manager with context-aware tracking.
_install__yq_install_repos() {
  local _context="${1-}" _group="${2-}" _bin
  if [[ "$_context" == "user" ]]; then
    ospkg__install_user yq || return 1
  else
    ospkg__install_tracked "$_group" yq || return 1
  fi
  _bin="$(command -v yq 2> /dev/null || true)"
  _install__yq_compatible "${_bin}" || return 1
  install__state_record "yq" "$_context" "repos" "$_bin" "$_group" || true
  printf '%s\n' "$_bin"
  return 0
}

# @brief install__yq --context <internal|user> [--method <auto|release|repos>] [--owner-group <id>] [--if-exists <skip|fail|reinstall>] [--prefix <path|auto>] — Ensure yq is installed with context-aware ownership semantics.
install__yq() {
  local _context="internal" _method="auto" _owner_group="sysset-ospkg-internals" _if_exists="skip" _prefix="auto"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context) shift; _context="${1-}" ;;
      --method) shift; _method="${1-}" ;;
      --owner-group) shift; _owner_group="${1-}" ;;
      --if-exists) shift; _if_exists="${1-}" ;;
      --prefix) shift; _prefix="${1-}" ;;
      *) logging__error "install__yq: unknown option '$1'"; return 1 ;;
    esac
    shift
  done
  [[ "$_context" == "internal" || "$_context" == "user" ]] || return 1
  local _existing _state_ctx _state_path _state_group
  _existing="$(command -v yq 2> /dev/null || true)"
  _state_ctx="$(install__state_context "yq" 2> /dev/null || true)"
  _state_path="$(install__state_install_path "yq" 2> /dev/null || true)"
  _state_group="$(install__state_owner_group "yq" 2> /dev/null || true)"
  if [[ -n "$_existing" ]] && _install__yq_compatible "$_existing"; then
    if [[ "$_context" == "user" && "$_state_ctx" == "internal" ]]; then
      install__promote_path_to_user "${_state_group:-$_owner_group}" "$_state_path"
      install__state_record "yq" "user" "${_method}" "$_existing" "$_owner_group" || true
    fi
    if [[ "$_if_exists" == "fail" ]]; then
      logging__error "install__yq: yq already installed at $_existing."
      return 1
    fi
    printf '%s\n' "$_existing"
    return 0
  fi
  case "$_method" in
    release) _install__yq_install_release "$_context" "$_owner_group" "$_prefix" ;;
    repos) _install__yq_install_repos "$_context" "$_owner_group" ;;
    auto) _install__yq_install_repos "$_context" "$_owner_group" || _install__yq_install_release "$_context" "$_owner_group" "$_prefix" ;;
    *) return 1 ;;
  esac
}
