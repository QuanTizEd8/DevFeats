# shellcheck shell=bash
# Do not edit _lib/ copies directly — edit lib/ instead.

# @brief _install_yq__compatible <bin> — Return 0 when candidate binary is mikefarah/yq-compatible (`-o=json` supported).
#
# Tests whether `<bin>` accepts the `-o=json` flag, which is unique to
# mikefarah/yq and absent from the unrelated `yq` Haskell tool sometimes
# installed by package managers.
#
# Args:
#   <bin>  Path to the binary to test.
#
# Returns: 0 if compatible, 1 if not or if <bin> is empty.
_install_yq__compatible() {
  local _bin="${1-}"
  [[ -n "$_bin" ]] || return 1
  "$_bin" -o=json '.' /dev/null > /dev/null 2>&1
}

# @brief _install_yq__install_release <context> <group> <prefix> [version] [installer-dir] — Install yq from GitHub release assets with checksum verification.
#
# Args:
#   <context>        `internal` or `user`.
#   <group>          Resource-tracking group ID.
#   <prefix>         Installation prefix (only used for `user` context).
#   [version]        Bare semver (no `v`). Empty means latest.
#   [installer-dir]  Optional persistent work directory (passed to github__install_release).
#
# Stdout: absolute path to the installed binary on success.
# Returns: 0 on success, 1 on any failure.
_install_yq__install_release() {
  local _context="${1-}" _group="${2-}" _install_prefix="${3-}" _version="${4-}" _installer_dir="${5-}"
  local _os _arch _base _install_bin_dir _expected_hash _hdir _f
  _os="$(os__release_kernel)" || return 1
  _arch="$(os__release_arch)" || return 1
  case "$_arch" in
    amd64 | arm64) ;;
    *)
      logging__error "install__yq: unsupported architecture '${_arch}'."
      return 1
      ;;
  esac

  # Resolve latest version when none given.
  if [[ -z "$_version" ]]; then
    _version="$(github__resolve_version "mikefarah/yq" --version)" || return 1
  fi
  _base="https://github.com/mikefarah/yq/releases/download/v${_version}"

  # Determine install destination directory.
  if [[ "$_context" == "user" ]]; then
    [[ -z "$_install_prefix" || "$_install_prefix" == "auto" ]] && _install_prefix="$(users__default_prefix)"
    _install_bin_dir="${_install_prefix%/}/bin"
  else
    _install_bin_dir="$(file__mktmpdir "install/yq")"
  fi

  # Compute hash via yq's custom checksum extraction script.
  _hdir="$(file__mktmpdir "install/yq-checksums")"
  for _f in checksums checksums_hashes_order extract-checksum.sh; do
    net__fetch_url_file "${_base}/${_f}" "${_hdir}/${_f}" || return 1
  done
  _expected_hash="$(cd "${_hdir}" && bash extract-checksum.sh SHA-256 "yq_${_os}_${_arch}" | awk '{print $2}')"
  if [[ ! "${_expected_hash:-}" =~ ^[0-9a-f]{64}$ ]]; then
    logging__error "install__yq: invalid extracted hash for yq_${_os}_${_arch}."
    return 1
  fi

  local -a _owner_group_arg _idir_arg
  install__build_release_args "$_context" "$_group" "$_installer_dir" _owner_group_arg _idir_arg

  github__install_release \
    --repo "mikefarah/yq" --tag "v${_version}" \
    --asset "yq_${_os}_${_arch}" --binary-dest "${_install_bin_dir%/}/yq" \
    --sha256 "$_expected_hash" \
    "${_idir_arg[@]}" \
    "${_owner_group_arg[@]}" ||
    return 1
  install__state_record "yq" "$_context" "binary" "${_install_bin_dir%/}/yq" "$_group" || true
}

# @brief _install_yq__install_repos <context> <group> [repos-manifest] — Install yq via package manager with context-aware tracking.
_install_yq__install_repos() {
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
  if ! _install_yq__compatible "${_bin}"; then
    logging__error "install__yq: method=package did not yield a mikefarah/yq-compatible binary."
    return 1
  fi
  install__state_record "yq" "$_context" "package" "$_bin" "$_group" || true
  printf '%s\n' "$_bin"
  return 0
}

# @brief install__yq --context <internal|user> [--method <auto|binary|package>] [--owner-group <id>] [--if-exists <skip|fail|reinstall>] [--version <semver|''>] [--prefix <path|auto>] [--repos-manifest <path>] — Ensure yq is installed with context-aware ownership semantics.
install__yq() {
  local _context="internal" _method="auto" _owner_group="devfeats-ospkg-internals" _if_exists="skip"
  local _install_prefix="auto" _repos_manifest="" _version="" _installer_dir=""
  install__parse_common_opts "install__yq" \
    _context _version _method _install_prefix _if_exists _repos_manifest _owner_group _installer_dir \
    "" "$@" || return 1
  [[ "$_context" == "internal" || "$_context" == "user" ]] || return 1
  local _existing _state_ctx _state_path _state_group
  _existing="$(command -v yq 2> /dev/null || true)"
  install__read_state "yq" _state_ctx _state_path _state_group
  if [[ -n "$_existing" ]] && _install_yq__compatible "$_existing"; then
    if [[ "$_if_exists" == "reinstall" ]]; then
      install__maybe_promote_to_user "yq" "$_context" "$_method" "$_owner_group" \
        "$_existing" _state_ctx _state_path _state_group
    elif [[ "$_if_exists" == "fail" ]]; then
      logging__error "install__yq: yq already installed at $_existing."
      return 1
    else
      install__maybe_promote_to_user "yq" "$_context" "$_method" "$_owner_group" \
        "$_existing" _state_ctx _state_path _state_group
      printf '%s\n' "$_existing"
      return 0
    fi
  fi
  case "$_method" in
    binary) _install_yq__install_release "$_context" "$_owner_group" "$_install_prefix" "$_version" "$_installer_dir" ;;
    package) _install_yq__install_repos "$_context" "$_owner_group" "$_repos_manifest" ;;
    auto) _install_yq__install_release "$_context" "$_owner_group" "$_install_prefix" "$_version" "$_installer_dir" || _install_yq__install_repos "$_context" "$_owner_group" "$_repos_manifest" ;;
    *)
      logging__error "install__yq: invalid method '${_method}'."
      return 1
      ;;
  esac
}
