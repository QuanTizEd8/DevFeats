#!/usr/bin/env bash
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_INSTALL_YQ__LIB_LOADED-}" ]] && return 0
_INSTALL_YQ__LIB_LOADED=1

_INSTALL_YQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/install/common.sh
. "${_INSTALL_YQ_LIB_DIR}/common.sh"
# shellcheck source=lib/verify.sh
. "${_INSTALL_YQ_LIB_DIR}/../verify.sh"
# shellcheck source=lib/os.sh
. "${_INSTALL_YQ_LIB_DIR}/../os.sh"
# shellcheck source=lib/ospkg.sh
. "${_INSTALL_YQ_LIB_DIR}/../ospkg.sh"
# shellcheck source=lib/users.sh
. "${_INSTALL_YQ_LIB_DIR}/../users.sh"

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
    *)
      logging__error "install__yq: unsupported architecture '${_arch}'."
      return 1
      ;;
  esac
  printf '%s %s\n' "$_os" "$_arch"
}

# @brief _install__yq_install_release <context> <group> <prefix> [version] — Install yq from GitHub release assets with checksum verification.
# version: bare semver (no "v" prefix). If empty, uses latest/download URL.
_install__yq_install_release() {
  local _context="${1-}" _group="${2-}" _install_prefix="${3-}" _version="${4-}"
  local _os _arch _base _dir _dest _expected_hash _final_dest
  read -r _os _arch <<< "$(_install__yq_platform_arch)" || return 1
  if [[ -n "$_version" ]]; then
    _base="https://github.com/mikefarah/yq/releases/download/v${_version}"
  else
    _base="https://github.com/mikefarah/yq/releases/latest/download"
  fi
  _dir="$(logging__tmpdir "install/yq")"
  _dest="${_dir}/yq_${_os}_${_arch}"
  net__fetch_url_file "${_base}/yq_${_os}_${_arch}" "$_dest" || return 1
  net__fetch_url_file "${_base}/checksums" "${_dir}/checksums" || return 1
  net__fetch_url_file "${_base}/checksums_hashes_order" "${_dir}/checksums_hashes_order" || return 1
  net__fetch_url_file "${_base}/extract-checksum.sh" "${_dir}/extract-checksum.sh" || return 1
  _expected_hash="$(cd "${_dir}" && bash extract-checksum.sh SHA-256 "yq_${_os}_${_arch}" | awk '{print $2}')"
  if [[ ! "${_expected_hash:-}" =~ ^[0-9a-f]{64}$ ]]; then
    logging__error "install__yq: extracted checksum is invalid for yq_${_os}_${_arch}."
    return 1
  fi
  verify__sha "$_dest" "$_expected_hash" || return 1
  chmod +x "$_dest" || return 1
  _final_dest="$_dest"
  if [[ "$_context" == "user" ]]; then
    if [[ -z "$_install_prefix" || "$_install_prefix" == "auto" ]]; then
      _install_prefix="$(users__default_prefix)"
    fi
    _final_dest="${_install_prefix%/}/bin/yq"
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
  install__state_record "yq" "$_context" "binary" "$_final_dest" "$_group" || true
  printf '%s\n' "$_final_dest"
  return 0
}

# @brief _install__yq_install_repos <context> <group> [repos-manifest] — Install yq via package manager with context-aware tracking.
_install__yq_install_repos() {
  local _context="${1-}" _group="${2-}" _repos_manifest="${3-}" _bin
  if [[ -n "$_repos_manifest" ]]; then
    ospkg__run --manifest "$_repos_manifest" --skip_installed || return 1
  else
    logging__warn "install__yq: no repos manifest provided; attempting package 'yq'."
    if [[ "$_context" == "user" ]]; then
      ospkg__install_user yq || return 1
    else
      ospkg__install_tracked "$_group" yq || return 1
    fi
  fi
  _bin="$(command -v yq 2> /dev/null || true)"
  if ! _install__yq_compatible "${_bin}"; then
    logging__error "install__yq: method=package did not yield a mikefarah/yq-compatible binary."
    return 1
  fi
  install__state_record "yq" "$_context" "package" "$_bin" "$_group" || true
  printf '%s\n' "$_bin"
  return 0
}

# @brief install__yq --context <internal|user> [--method <auto|binary|package>] [--owner-group <id>] [--if-exists <skip|fail|reinstall>] [--version <semver|''>] [--prefix <path|auto>] [--repos-manifest <path>] — Ensure yq is installed with context-aware ownership semantics.
install__yq() {
  local _context="internal" _method="auto" _owner_group="devfeats-ospkg-internals" _if_exists="skip" _install_prefix="auto" _repos_manifest="" _version=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context)
        shift
        _context="${1-}"
        ;;
      --method)
        shift
        _method="${1-}"
        ;;
      --owner-group)
        shift
        _owner_group="${1-}"
        ;;
      --if-exists)
        shift
        _if_exists="${1-}"
        ;;
      --prefix)
        shift
        _install_prefix="${1-}"
        ;;
      --repos-manifest)
        shift
        _repos_manifest="${1-}"
        ;;
      --version)
        shift
        _version="${1-}"
        ;;
      *)
        logging__error "install__yq: unknown option '$1'"
        return 1
        ;;
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
    if [[ "$_if_exists" == "reinstall" ]]; then
      :
    elif [[ "$_if_exists" == "fail" ]]; then
      logging__error "install__yq: yq already installed at $_existing."
      return 1
    else
      if [[ "$_context" == "user" && "$_state_ctx" == "internal" ]]; then
        install__promote_path_to_user "${_state_group:-$_owner_group}" "$_state_path"
        install__state_record "yq" "user" "${_method}" "$_existing" "$_owner_group" || true
      fi
      printf '%s\n' "$_existing"
      return 0
    fi
    if [[ "$_context" == "user" && "$_state_ctx" == "internal" ]]; then
      install__promote_path_to_user "${_state_group:-$_owner_group}" "$_state_path"
      install__state_record "yq" "user" "${_method}" "$_existing" "$_owner_group" || true
    fi
  fi
  case "$_method" in
    binary) _install__yq_install_release "$_context" "$_owner_group" "$_install_prefix" "$_version" ;;
    package) _install__yq_install_repos "$_context" "$_owner_group" "$_repos_manifest" ;;
    auto) _install__yq_install_release "$_context" "$_owner_group" "$_install_prefix" "$_version" || _install__yq_install_repos "$_context" "$_owner_group" "$_repos_manifest" ;;
    *)
      logging__error "install__yq: invalid method '${_method}'."
      return 1
      ;;
  esac
}
