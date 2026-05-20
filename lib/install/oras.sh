# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_INSTALL_ORAS__LIB_LOADED-}" ]] && return 0
_INSTALL_ORAS__LIB_LOADED=1

_INSTALL_ORAS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/install/common.sh
. "${_INSTALL_ORAS_LIB_DIR}/common.sh"
# shellcheck source=lib/os.sh
. "${_INSTALL_ORAS_LIB_DIR}/../os.sh"
# shellcheck source=lib/ver.sh
. "${_INSTALL_ORAS_LIB_DIR}/../ver.sh"
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

# @brief _install__oras_resolve_version <spec> — Resolve a version spec to bare semver (no leading `v`).
# Accepts "stable" (default), "latest", "", or a semver / partial version string.
_install__oras_resolve_version() {
  local _spec="${1-}"
  local _out
  _out="$(github__resolve_version "oras-project/oras" "$_spec")" || return 1
  printf '%s\n' "${_out#*$'\n'}"
}

# @brief _install__oras_install_release <version> <prefix> <group> <context> [installer-dir] — Install ORAS from release artifact with mandatory checksum+GPG verification.
#
# Args:
#   <version>        Bare semver string (no leading `v`), e.g. `1.2.3`.
#   <prefix>         Installation prefix; binary goes to `<prefix>/bin/oras`.
#   <group>          Resource-tracking group ID (e.g. `lib-oci-oras`).
#   <context>        `internal` or `user`; controls cleanup tracking.
#   [installer-dir]  Optional persistent work directory (passed to github__install_release).
#
# Stdout: absolute path to the installed binary on success.
# Returns: 0 on success, 1 on any failure.
_install__oras_install_release() {
  local _version="${1-}" _install_prefix="${2-}" _group="${3-}" _context="${4-}" _installer_dir="${5-}"
  local _platform _arch _asset _tag _bin_dest
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
  _bin_dest="${_install_prefix%/}/bin"
  local -a _owner_group_arg _idir_arg
  install__build_release_args "$_context" "$_group" "$_installer_dir" _owner_group_arg _idir_arg
  github__install_release \
    --repo "oras-project/oras" --tag "$_tag" \
    --asset "$_asset" --binary-src oras --binary-dest "${_bin_dest}/" \
    --gpg-key "https://raw.githubusercontent.com/oras-project/oras/refs/heads/main/KEYS" \
    "${_idir_arg[@]}" \
    "${_owner_group_arg[@]}" ||
    return 1
  install__state_record "oras" "$_context" "binary" "${_bin_dest}/oras" "$_group" || true
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
  if [[ -n "$_version" && "$_version" != "latest" && "$_version" != "stable" ]]; then
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

# @brief install__oras --context <internal|user> [--version <ver|stable|latest>] [--min-version <ver>] [--method <auto|binary|package>] [--prefix <path|auto>] [--if-exists <skip|fail|reinstall>] [--repos-manifest <path>] [--owner-group <id>] [--installer-dir <dir>] — Ensure ORAS is installed with context-aware ownership semantics and mandatory checksum+GPG verification for release artifacts.
install__oras() {
  local _context="internal" _version="stable" _min_version="" _method="auto" _install_prefix="auto"
  local _if_exists="skip" _repos_manifest="" _owner_group="lib-oci-oras" _installer_dir=""
  local -a _extra=()
  install__parse_common_opts "install__oras" \
    _context _version _method _install_prefix _if_exists _repos_manifest _owner_group _installer_dir \
    _extra "$@" || return 1
  local _i=0
  while [[ $_i -lt ${#_extra[@]} ]]; do
    case "${_extra[$_i]}" in
      --min-version)
        ((_i++))
        _min_version="${_extra[$_i]-}"
        ;;
      *)
        logging__error "install__oras: unknown option '${_extra[$_i]}'"
        return 1
        ;;
    esac
    ((_i++))
  done
  [[ "$_context" == "internal" || "$_context" == "user" ]] || return 1
  [[ -n "$_owner_group" ]] || _owner_group="install-oras"

  local _existing _existing_ver _state_ctx _state_path _state_group
  _existing="$(command -v oras 2> /dev/null || true)"
  install__read_state "oras" _state_ctx _state_path _state_group
  install__maybe_promote_to_user "oras" "$_context" "$_method" "$_owner_group" \
    "$_existing" _state_ctx _state_path _state_group
  if [[ -n "$_existing" ]]; then
    _existing_ver="$(ver__extract_version "$("$_existing" version 2> /dev/null | head -n1)")"
    if [[ -n "$_min_version" ]] && ver__semver_ge "${_existing_ver:-0}" "$_min_version"; then
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
    _install_prefix="$(users__default_prefix)"
  fi
  local _version_spec="$_version"
  _version="$(_install__oras_resolve_version "$_version_spec")" || return 1
  case "$_method" in
    binary)
      _install__oras_install_release "$_version" "$_install_prefix" "$_owner_group" "$_context" "$_installer_dir"
      ;;
    package)
      _install__oras_install_repos "$_version_spec" "$_owner_group" "$_context" "$_repos_manifest"
      ;;
    auto)
      _install__oras_install_release "$_version" "$_install_prefix" "$_owner_group" "$_context" "$_installer_dir" ||
        _install__oras_install_repos "$_version_spec" "$_owner_group" "$_context" "$_repos_manifest"
      ;;
    *)
      logging__error "install__oras: invalid method '${_method}'."
      return 1
      ;;
  esac
}
