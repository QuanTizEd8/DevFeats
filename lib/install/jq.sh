# shellcheck shell=bash
# Do not edit _lib/ copies directly — edit lib/ instead.

# @brief _install_jq__asset_name <version> <os> <arch> — Print jq release asset filename.
#
# jq 1.7+ uses modern naming: jq-{os}-{arch} (e.g. jq-linux-amd64).
# jq 1.6 and older use legacy naming: jq-linux64, jq-linux32, jq-osx-amd64.
_install_jq__asset_name() {
  local _version="$1" _os="$2" _arch="$3"
  if ! ver__semver_ge "$_version" "1.7"; then
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

# @brief _install_jq__gpg_key_url <version> <gh_repo> — Print the URL for the jq release signing key.
#
# jq 1.7+ is signed with jq-release-new.key; 1.6 and older with jq-release-old.key.
_install_jq__gpg_key_url() {
  local _version="$1" _gh_repo="${2-}"
  if ! ver__semver_ge "$_version" "1.7"; then
    printf 'https://raw.githubusercontent.com/%s/master/sig/jq-release-old.key\n' "$_gh_repo"
  else
    printf 'https://raw.githubusercontent.com/%s/master/sig/jq-release-new.key\n' "$_gh_repo"
  fi
}

# @brief _install_jq__install_release <version> <prefix> <group> <context> [installer-dir] [gh-repo] — Install jq from a GitHub release binary with SHA-256 and GPG verification.
#
# Args:
#   <version>        Bare semver string (no leading `v`), e.g. `1.7.1`.
#   <prefix>         Installation prefix; binary goes to `<prefix>/bin/jq`.
#   <group>          Resource-tracking group ID.
#   <context>        `internal` or `user`; controls cleanup tracking.
#   [installer-dir]  Optional persistent work directory (passed to github__install_release).
#   [gh-repo]        GitHub repository slug (default: jqlang/jq).
#
# Stdout: absolute path to the installed binary on success.
# Returns: 0 on success, 1 on any failure.
_install_jq__install_release() {
  local _version="${1-}" _install_prefix="${2-}" _group="${3-}" _context="${4-}" _installer_dir="${5-}" _gh_repo="${6-}"
  local _os _arch _asset _base_url _key_url
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
  _asset="$(_install_jq__asset_name "$_version" "$_os" "$_arch")" || return 1
  _key_url="$(_install_jq__gpg_key_url "$_version" "$_gh_repo")"

  # jq ≤1.6 has no sha256sum.txt; for newer versions add explicit sidecar.
  local -a _sidecar_args=()
  if ver__semver_ge "$_version" "1.7"; then
    _sidecar_args=(--sidecar "sha256sum.txt")
  fi

  local -a _owner_group_arg _idir_arg
  install__build_release_args "$_context" "$_group" "$_installer_dir" _owner_group_arg _idir_arg

  github__install_release \
    --repo "${_gh_repo}" --tag "jq-${_version}" \
    --asset "$_asset" --binary-dest "${_install_prefix%/}/bin/jq" \
    "${_sidecar_args[@]}" \
    --gpg-key "$_key_url" \
    --gpg-sig "https://raw.githubusercontent.com/${_gh_repo}/master/sig/v${_version}/${_asset}.asc" \
    "${_idir_arg[@]}" \
    "${_owner_group_arg[@]}" ||
    return 1
  install__state_record "jq" "$_context" "binary" "${_install_prefix%/}/bin/jq" "$_group" || true
}

# @brief _install_jq__install_repos <group> <context> [repos-manifest] — Install jq via the OS package manager.
_install_jq__install_repos() {
  local _group="${1-}" _context="${2-}" _repos_manifest="${3-}"
  if [[ -n "$_repos_manifest" ]]; then
    ospkg__run --manifest "$_repos_manifest" || return 1
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

# @brief _install_jq__install_source <version> <prefix> <group> <context> [gh-repo] — Build and install jq from the release tarball.
#
# Runs ./configure --with-oniguruma=builtin, make, make check, make install.
# Build tools must be installed by the caller before this function is invoked.
_install_jq__install_source() {
  local _version="${1-}" _install_prefix="${2-}" _group="${3-}" _context="${4-}" _gh_repo="${5-}"
  local _tarball_url _dir _tarball _src_dir _jobs _final_dest
  _tarball_url="https://github.com/${_gh_repo}/releases/download/jq-${_version}/jq-${_version}.tar.gz"
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

# @brief install__jq --context <internal|user> [--method <auto|binary|package|source>] [--version <semver|stable|latest>] [--prefix <path|auto>] [--if-exists <skip|fail|reinstall>] [--repos-manifest <path>] [--owner-group <id>] [--gh-repo <owner/repo>] — Ensure jq is installed with context-aware ownership semantics.
install__jq() {
  local _context="internal" _version="stable" _method="auto" _install_prefix="auto"
  local _if_exists="skip" _repos_manifest="" _owner_group="feature::install-jq" _installer_dir=""
  local _gh_repo="jqlang/jq"
  install__parse_common_opts "install__jq" \
    _context _version _method _install_prefix _if_exists _repos_manifest _owner_group _installer_dir \
    _gh_repo "" "$@" || return 1
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
  # lib-json) has no state record.  Clear _existing so _install_jq__install_repos
  # always runs and marks the package permanent via the package manager.
  if [[ "$_method" == "package" && -n "$_existing" && -z "$_state_ctx" ]]; then
    _existing=""
  fi

  install__maybe_promote_to_user "jq" "$_context" "$_method" "$_owner_group" \
    "$_existing" _state_ctx _state_path _state_group

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
      _install_jq__install_release "$_version" "$_install_prefix" "$_owner_group" "$_context" "$_installer_dir" "$_gh_repo"
      ;;
    package)
      _install_jq__install_repos "$_owner_group" "$_context" "$_repos_manifest"
      ;;
    source)
      _install_jq__install_source "$_version" "$_install_prefix" "$_owner_group" "$_context" "$_gh_repo"
      ;;
    auto)
      _install_jq__install_release "$_version" "$_install_prefix" "$_owner_group" "$_context" "$_installer_dir" "$_gh_repo" ||
        _install_jq__install_repos "$_owner_group" "$_context" "$_repos_manifest"
      ;;
    *)
      logging__error "install__jq: invalid method '${_method}'."
      return 1
      ;;
  esac
}
