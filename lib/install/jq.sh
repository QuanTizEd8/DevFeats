#!/usr/bin/env bash
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_INSTALL_JQ__LIB_LOADED-}" ]] && return 0
_INSTALL_JQ__LIB_LOADED=1

_INSTALL_JQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/install/common.sh
. "${_INSTALL_JQ_LIB_DIR}/common.sh"
# shellcheck source=lib/verify.sh
. "${_INSTALL_JQ_LIB_DIR}/../verify.sh"
# shellcheck source=lib/os.sh
. "${_INSTALL_JQ_LIB_DIR}/../os.sh"
# shellcheck source=lib/file.sh
. "${_INSTALL_JQ_LIB_DIR}/../file.sh"
# shellcheck source=lib/ospkg.sh
. "${_INSTALL_JQ_LIB_DIR}/../ospkg.sh"
# shellcheck source=lib/net.sh
. "${_INSTALL_JQ_LIB_DIR}/../net.sh"
# shellcheck source=lib/users.sh
. "${_INSTALL_JQ_LIB_DIR}/../users.sh"
# shellcheck source=lib/github.sh
. "${_INSTALL_JQ_LIB_DIR}/../github.sh"

# @brief _install__jq_asset_name <version> <os> <arch> — Print jq release asset filename.
#
# jq 1.7+ uses modern naming: jq-{os}-{arch} (e.g. jq-linux-amd64).
# jq 1.6 and older use legacy naming: jq-linux64, jq-linux32, jq-osx-amd64.
_install__jq_asset_name() {
  local _version="$1" _os="$2" _arch="$3"
  local _major _minor
  _major="${_version%%.*}"
  _minor="${_version#*.}"
  _minor="${_minor%%.*}"
  if [[ "$_major" -eq 1 && "$_minor" -le 6 ]]; then
    # Legacy asset naming for jq 1.6 and older.
    case "${_os}-${_arch}" in
      linux-amd64) printf 'jq-linux64\n' ;;
      linux-i386) printf 'jq-linux32\n' ;;
      macos-amd64) printf 'jq-osx-amd64\n' ;;
      *)
        logging__error "install__jq: no release asset for ${_os}/${_arch} at legacy version ${_version}."
        return 1
        ;;
    esac
  else
    printf 'jq-%s-%s\n' "$_os" "$_arch"
  fi
}

# @brief _install__jq_gpg_key_url <version> — Print the URL for the jq release signing key.
#
# jq 1.7+ is signed with jq-release-new.key; 1.6 and older with jq-release-old.key.
_install__jq_gpg_key_url() {
  local _version="$1" _major _minor
  _major="${_version%%.*}"
  _minor="${_version#*.}"
  _minor="${_minor%%.*}"
  if [[ "$_major" -eq 1 && "$_minor" -le 6 ]]; then
    printf 'https://raw.githubusercontent.com/jqlang/jq/master/sig/jq-release-old.key\n'
  else
    printf 'https://raw.githubusercontent.com/jqlang/jq/master/sig/jq-release-new.key\n'
  fi
}

# @brief _install__jq_install_release <version> <prefix> <group> <context> — Install jq from a GitHub release binary with SHA-256 and GPG verification.
#
# Args:
#   <version>  Bare semver string (no leading `v`), e.g. `1.7.1`.
#   <prefix>   Installation prefix; binary goes to `<prefix>/bin/jq`.
#   <group>    Resource-tracking group ID.
#   <context>  `internal` or `user`; controls cleanup tracking.
#
# Stdout: absolute path to the installed binary on success.
# Returns: 0 on success, 1 on any failure.
_install__jq_install_release() {
  local _version="${1-}" _install_prefix="${2-}" _group="${3-}" _context="${4-}"
  local _os _arch _asset _base_url _key_url _major _minor
  _os="$(os__release_kernel)" || return 1
  [[ "$_os" == "darwin" ]] && _os="macos"
  _arch="$(os__release_arch)" || return 1
  case "$_arch" in
    amd64 | arm64 | i386) ;;
    *)
      logging__error "install__jq: unsupported architecture '${_arch}'."
      return 1
      ;;
  esac
  _asset="$(_install__jq_asset_name "$_version" "$_os" "$_arch")" || return 1
  _base_url="https://github.com/jqlang/jq/releases/download/jq-${_version}"
  _key_url="$(_install__jq_gpg_key_url "$_version")"

  _major="${_version%%.*}"
  _minor="${_version#*.}"
  _minor="${_minor%%.*}"
  # jq ≤1.6 has no sha256sum.txt; for newer versions add explicit sidecar URL.
  local -a _sidecar_args=()
  if ! [[ "$_major" -eq 1 && "$_minor" -le 6 ]]; then
    _sidecar_args=(--sidecar-url "${_base_url}/sha256sum.txt")
  fi

  local -a _owner_group_arg=()
  [[ "$_context" == "internal" ]] && _owner_group_arg=(--owner-group "$_group")

  github__install_release \
    --repo "jqlang/jq" --tag "jq-${_version}" \
    --asset "$_asset" --binary-src jq --binary-dest "${_install_prefix%/}/bin" \
    "${_sidecar_args[@]}" \
    --gpg-key-url "$_key_url" \
    --gpg-sig-url "https://raw.githubusercontent.com/jqlang/jq/master/sig/v${_version}/${_asset}.asc" \
    "${_owner_group_arg[@]}" ||
    return 1
  install__state_record "jq" "$_context" "binary" "${_install_prefix%/}/bin/jq" "$_group" || true
}

# @brief _install__jq_install_repos <group> <context> [repos-manifest] — Install jq via the OS package manager.
_install__jq_install_repos() {
  local _group="${1-}" _context="${2-}" _repos_manifest="${3-}"
  if [[ -n "$_repos_manifest" ]]; then
    ospkg__run --manifest "$_repos_manifest" --skip_installed || return 1
  else
    if [[ "$_context" == "user" ]]; then
      ospkg__install_user jq || return 1
    else
      ospkg__install_tracked "$_group" jq || return 1
    fi
  fi
  local _bin
  _bin="$(command -v jq 2> /dev/null || true)"
  [[ -n "$_bin" ]] || {
    logging__error "install__jq: jq not found on PATH after package install."
    return 1
  }
  install__state_record "jq" "$_context" "package" "$_bin" "$_group" || true
  printf '%s\n' "$_bin"
  return 0
}

# @brief _install__jq_install_source <version> <prefix> <group> <context> — Build and install jq from the release tarball.
#
# Runs ./configure --with-oniguruma=builtin, make, make check, make install.
# Build tools must be installed by the caller before this function is invoked.
_install__jq_install_source() {
  local _version="${1-}" _install_prefix="${2-}" _group="${3-}" _context="${4-}"
  local _tarball_url _dir _tarball _src_dir _jobs _final_dest
  _tarball_url="https://github.com/jqlang/jq/releases/download/jq-${_version}/jq-${_version}.tar.gz"
  _dir="$(file__tmpdir "install/jq-source")"
  _tarball="${_dir}/jq-${_version}.tar.gz"

  net__fetch_url_file "$_tarball_url" "$_tarball" || return 1
  file__extract_archive "$_tarball" "$_dir" || {
    logging__error "install__jq: failed to extract source tarball."
    return 1
  }
  _src_dir="${_dir}/jq-${_version}"
  [[ -d "$_src_dir" ]] || {
    logging__error "install__jq: expected source directory '${_src_dir}' not found after extraction."
    return 1
  }
  _jobs="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || printf '1')"
  (
    cd "$_src_dir" || exit 1
    ./configure --with-oniguruma=builtin --prefix="${_install_prefix}" || exit 1
    make -j"${_jobs}" || exit 1
    make check || exit 1
    make install || exit 1
  ) || return 1

  _final_dest="${_install_prefix%/}/bin/jq"
  [[ -x "$_final_dest" ]] || {
    logging__error "install__jq: binary '${_final_dest}' not found after source build."
    return 1
  }
  if [[ "$_context" == "internal" ]]; then
    install__track_internal_path "$_group" "$_final_dest"
  fi
  install__state_record "jq" "$_context" "source" "$_final_dest" "$_group" || true
  printf '%s\n' "$_final_dest"
  return 0
}

# @brief install__jq --context <internal|user> [--method <auto|binary|package|source>] [--version <semver|stable|latest>] [--prefix <path|auto>] [--if-exists <skip|fail|reinstall>] [--repos-manifest <path>] [--owner-group <id>] — Ensure jq is installed with context-aware ownership semantics.
install__jq() {
  local _context="internal" _version="stable" _method="auto" _install_prefix="auto"
  local _if_exists="skip" _repos_manifest="" _owner_group="feature::install-jq"
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
      --repos-manifest)
        shift
        _repos_manifest="${1-}"
        ;;
      --owner-group)
        shift
        _owner_group="${1-}"
        ;;
      *)
        logging__error "install__jq: unknown option '$1'"
        return 1
        ;;
    esac
    shift
  done
  [[ "$_context" == "internal" || "$_context" == "user" ]] || return 1
  [[ -n "$_owner_group" ]] || _owner_group="install-jq"

  # Resolve prefix early so the existence check targets the actual install
  # location rather than any jq found anywhere in PATH.
  local _check_prefix="$_install_prefix"
  if [[ "$_check_prefix" == "auto" || -z "$_check_prefix" ]]; then
    _check_prefix="$(users__default_prefix)"
  fi

  local _existing _state_ctx _state_path _state_group
  if [[ "$_method" == "package" ]]; then
    _existing="$(command -v jq 2> /dev/null || true)"
  elif [[ -x "${_check_prefix}/bin/jq" ]]; then
    _existing="${_check_prefix}/bin/jq"
  else
    _existing=""
  fi
  install__read_state "jq" _state_ctx _state_path _state_group

  # For package: a jq that landed in PATH solely as a transient build-dep (e.g.
  # lib-json) has no state record.  Clear _existing so _install__jq_install_repos
  # always runs and marks the package permanent via the package manager.
  if [[ "$_method" == "package" && -n "$_existing" && -z "$_state_ctx" ]]; then
    _existing=""
  fi

  if [[ -n "$_existing" && "$_context" == "user" && "$_state_ctx" == "internal" ]]; then
    install__promote_path_to_user "${_state_group:-$_owner_group}" "$_state_path"
    install__state_record "jq" "user" "${_method}" "${_existing}" "$_owner_group" || true
    _state_ctx="user"
  fi

  if [[ -n "$_existing" ]]; then
    if [[ "$_context" == "internal" && "$_state_ctx" == "user" ]]; then
      printf '%s\n' "$_existing"
      return 0
    fi
    if [[ "$_if_exists" == "fail" ]]; then
      logging__error "install__jq: jq already exists at '$_existing'."
      return 1
    fi
    if [[ "$_if_exists" == "skip" ]]; then
      printf '%s\n' "$_existing"
      return 0
    fi
    # if_exists=reinstall: fall through to install.
  fi

  _install_prefix="$_check_prefix"

  case "$_method" in
    binary)
      _install__jq_install_release "$_version" "$_install_prefix" "$_owner_group" "$_context"
      ;;
    package)
      _install__jq_install_repos "$_owner_group" "$_context" "$_repos_manifest"
      ;;
    source)
      _install__jq_install_source "$_version" "$_install_prefix" "$_owner_group" "$_context"
      ;;
    auto)
      _install__jq_install_release "$_version" "$_install_prefix" "$_owner_group" "$_context" ||
        _install__jq_install_repos "$_owner_group" "$_context" "$_repos_manifest"
      ;;
    *)
      logging__error "install__jq: invalid method '${_method}'."
      return 1
      ;;
  esac
}
