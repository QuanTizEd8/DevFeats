#!/usr/bin/env bash
# shellcheck source=lib/install/common.sh
. "${_BASE_DIR}/_lib/install/common.sh"
# shellcheck source=lib/os.sh
. "${_BASE_DIR}/_lib/os.sh"
# shellcheck source=lib/ospkg.sh
. "${_BASE_DIR}/_lib/ospkg.sh"
# shellcheck source=lib/net.sh
. "${_BASE_DIR}/_lib/net.sh"
# shellcheck source=lib/verify.sh
. "${_BASE_DIR}/_lib/verify.sh"
# shellcheck source=lib/github.sh
. "${_BASE_DIR}/_lib/github.sh"
# shellcheck source=lib/file.sh
. "${_BASE_DIR}/_lib/file.sh"
# shellcheck source=lib/shell.sh
. "${_BASE_DIR}/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "${_BASE_DIR}/_lib/users.sh"

_install__just_resolve_version() {
  local _spec="$1"
  local _out
  _out="$(github__resolve_version "casey/just" "$_spec")" || return 1
  printf '%s\n' "${_out#*$'\n'}"
}

_install__just_resolve_target() {
  local _target="${1-}"
  if [[ -n "$_target" && "$_target" != "auto" ]]; then
    printf '%s\n' "$_target"
    return 0
  fi
  os__rust_triple || {
    logging__error "install-just: unsupported kernel/arch '$(os__kernel)/$(os__arch)' for binary target."
    return 1
  }
}

_install__just_install_release() {
  local _version="${1-}" _install_prefix="${2-}" _target="${3-}" _context="${4-}" _group="${5-}"
  local _base _asset _tmp _tar _sums _hash _dest
  _base="https://github.com/casey/just/releases/download/${_version}"
  _asset="just-${_version}-${_target}.tar.gz"
  _tmp="$(file__tmpdir "install/just")"
  _tar="${_tmp}/${_asset}"
  _sums="${_tmp}/SHA256SUMS"

  net__fetch_url_file "${_base}/${_asset}" "$_tar" || return 1
  net__fetch_url_file "${_base}/SHA256SUMS" "$_sums" || return 1
  _hash="$(awk -v f="${_asset}" '$2 == f { print $1; exit }' "$_sums")"
  if [[ ! "${_hash:-}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    logging__error "install-just: could not resolve checksum for ${_asset}."
    return 1
  fi
  verify__sha "$_tar" "$_hash" || return 1

  file__extract_archive "$_tar" "$_tmp" || return 1
  [[ -f "${_tmp}/just" ]] || return 1
  _dest="${_install_prefix%/}/bin/just"
  mkdir -p "$(dirname "$_dest")" || return 1
  if command -v install > /dev/null 2>&1; then
    install -m 0755 "${_tmp}/just" "$_dest" || return 1
  else
    cp "${_tmp}/just" "$_dest" || return 1
    chmod 0755 "$_dest" || return 1
  fi

  if [[ "$_context" == "internal" ]]; then
    install__track_internal_path "$_group" "$_dest"
  fi
  install__state_record "just" "$_context" "binary" "$_dest" "$_group" || true
  printf '%s\n' "$_dest"
}

_install__just_install_repos() {
  local _version="${1-}" _manifest="${2-}" _context="${3-}" _group="${4-}"
  local _bin
  if [[ -n "$_manifest" ]]; then
    ospkg__run --manifest "$_manifest" --skip_installed || return 1
  elif [[ -n "$_version" && "$_version" != "latest" && "$_version" != "stable" ]]; then
    ospkg__detect || return 1
    if [[ "${_OSPKG_PKG_MNGR:-}" == "apt-get" ]]; then
      ospkg__run --manifest "$(printf 'packages:\n  - name: just\n    version: "%s"\n' "$_version")" || return 1
    else
      logging__warn "install-just: version pinning for method=package is not supported on '${_OSPKG_PKG_MNGR:-unknown}'."
      ospkg__install just || return 1
    fi
  else
    if [[ "$_context" == "user" ]]; then
      ospkg__install_user just || return 1
    else
      ospkg__install_tracked "$_group" just || return 1
    fi
  fi
  _bin="$(command -v just 2> /dev/null || true)"
  [[ -n "$_bin" ]] || return 1
  install__state_record "just" "$_context" "package" "$_bin" "$_group" || true
  printf '%s\n' "$_bin"
}

_install__just_install_script() {
  local _version="${1-}" _install_prefix="${2-}" _target="${3-}" _force="${4-}" _context="${5-}" _group="${6-}"
  local _tmp _script _dest
  _tmp="$(file__tmpdir "install/just-script")"
  _script="${_tmp}/install.sh"
  _dest="${_install_prefix%/}/bin/just"
  net__fetch_url_file "https://just.systems/install.sh" "$_script" || return 1
  chmod +x "$_script" || return 1

  local -a _cmd
  _cmd=(bash "$_script" --to "${_install_prefix%/}/bin")
  if [[ -n "$_version" && "$_version" != "latest" ]]; then
    _cmd+=(--tag "$_version")
  fi
  if [[ -n "$_target" && "$_target" != "auto" ]]; then
    _cmd+=(--target "$_target")
  fi
  if [[ "$_force" == "true" ]]; then
    _cmd+=(--force)
  fi

  "${_cmd[@]}" || return 1
  [[ -x "$_dest" ]] || return 1
  if [[ "$_context" == "internal" ]]; then
    install__track_internal_path "$_group" "$_dest"
  fi
  install__state_record "just" "$_context" "script" "$_dest" "$_group" || true
  printf '%s\n' "$_dest"
}

_install__just_install_cargo() {
  local _version="${1-}" _install_prefix="${2-}" _binstall="${3-}" _force="${4-}" _context="${5-}" _group="${6-}"
  local _dest
  command -v cargo > /dev/null 2>&1 || {
    logging__error "install-just: method=cargo requires cargo in PATH."
    return 1
  }

  if [[ "$_binstall" == "true" ]] && cargo binstall --help > /dev/null 2>&1; then
    if [[ -n "$_version" && "$_version" != "latest" ]]; then
      cargo binstall --no-confirm --root "$_install_prefix" --version "$_version" just || return 1
    else
      cargo binstall --no-confirm --root "$_install_prefix" just || return 1
    fi
  else
    local -a _cmd
    _cmd=(cargo install --root "$_install_prefix")
    if [[ "$_force" == "true" ]]; then
      _cmd+=(--force)
    fi
    if [[ -n "$_version" && "$_version" != "latest" ]]; then
      _cmd+=(--version "$_version")
    fi
    _cmd+=(just)
    "${_cmd[@]}" || return 1
  fi

  _dest="${_install_prefix%/}/bin/just"
  [[ -x "$_dest" ]] || return 1
  if [[ "$_context" == "internal" ]]; then
    install__track_internal_path "$_group" "$_dest"
  fi
  install__state_record "just" "$_context" "cargo" "$_dest" "$_group" || true
  printf '%s\n' "$_dest"
}

install__just() {
  local _context="internal" _method="auto" _version="stable" _install_prefix="" _if_exists="skip"
  local _target="auto" _repos_manifest="" _script_force="false" _cargo_binstall="false"
  local _owner_group="install-just"

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
      --version)
        shift
        _version="${1-}"
        ;;
      --prefix)
        shift
        _install_prefix="${1-}"
        ;;
      --if-exists)
        shift
        _if_exists="${1-}"
        ;;
      --target)
        shift
        _target="${1-}"
        ;;
      --repos-manifest)
        shift
        _repos_manifest="${1-}"
        ;;
      --script-force)
        shift
        _script_force="${1-}"
        ;;
      --cargo-binstall)
        shift
        _cargo_binstall="${1-}"
        ;;
      --owner-group)
        shift
        _owner_group="${1-}"
        ;;
      *)
        logging__error "install-just: unknown option '$1'"
        return 1
        ;;
    esac
    shift
  done

  [[ "$_context" == "internal" || "$_context" == "user" ]] || return 1
  [[ "$_if_exists" == "skip" || "$_if_exists" == "fail" || "$_if_exists" == "reinstall" ]] || return 1

  local _existing _state_ctx _state_path _state_group
  _existing="$(command -v just 2> /dev/null || true)"
  _state_ctx="$(install__state_context "just" 2> /dev/null || true)"
  _state_path="$(install__state_install_path "just" 2> /dev/null || true)"
  _state_group="$(install__state_owner_group "just" 2> /dev/null || true)"

  if [[ -n "$_existing" && "$_context" == "user" && "$_state_ctx" == "internal" ]]; then
    install__promote_path_to_user "${_state_group:-$_owner_group}" "$_state_path"
    install__state_record "just" "user" "$_method" "$_existing" "$_owner_group" || true
    _state_ctx="user"
  fi

  if [[ -n "$_existing" ]]; then
    case "$_if_exists" in
      fail)
        logging__error "install-just: just already exists at $_existing."
        return 1
        ;;
      skip)
        printf '%s\n' "$_existing"
        return 0
        ;;
      reinstall)
        ;;
    esac
    if [[ "$_context" == "internal" && "$_state_ctx" == "user" ]]; then
      printf '%s\n' "$_existing"
      return 0
    fi
  fi

  case "$_method" in
    binary)
      local _resolved_version _resolved_target
      _resolved_version="$(_install__just_resolve_version "$_version")" || return 1
      _resolved_target="$(_install__just_resolve_target "$_target")" || return 1
      _install__just_install_release "$_resolved_version" "$_install_prefix" "$_resolved_target" "$_context" "$_owner_group"
      ;;
    package)
      _install__just_install_repos "$_version" "$_repos_manifest" "$_context" "$_owner_group"
      ;;
    script)
      local _script_version _script_target
      _script_version="$(_install__just_resolve_version "$_version" 2> /dev/null || true)"
      [[ -z "$_script_version" ]] && _script_version="latest"
      _script_target="$(_install__just_resolve_target "$_target")" || return 1
      _install__just_install_script "$_script_version" "$_install_prefix" "$_script_target" "$_script_force" "$_context" "$_owner_group"
      ;;
    cargo)
      local _cargo_version
      _cargo_version="$(_install__just_resolve_version "$_version" 2> /dev/null || true)"
      [[ -z "$_cargo_version" ]] && _cargo_version="latest"
      _install__just_install_cargo "$_cargo_version" "$_install_prefix" "$_cargo_binstall" "true" "$_context" "$_owner_group"
      ;;
    auto)
      local _auto_version _auto_target
      _auto_version="$(_install__just_resolve_version "$_version" 2> /dev/null || true)"
      _auto_target="$(_install__just_resolve_target "$_target" 2> /dev/null || true)"
      if [[ -n "$_auto_version" && -n "$_auto_target" ]]; then
        _install__just_install_release "$_auto_version" "$_install_prefix" "$_auto_target" "$_context" "$_owner_group" &&
          return 0
      fi
      _install__just_install_repos "$_version" "$_repos_manifest" "$_context" "$_owner_group" && return 0
      _install__just_install_script "${_auto_version:-latest}" "$_install_prefix" "${_auto_target:-auto}" "$_script_force" "$_context" "$_owner_group" && return 0
      _install__just_install_cargo "${_auto_version:-latest}" "$_install_prefix" "$_cargo_binstall" "true" "$_context" "$_owner_group"
      ;;
    *)
      logging__error "install-just: invalid method '${_method}'."
      return 1
      ;;
  esac
}
install__just \
  --context user \
  --owner-group "feature::install-just" \
  --method "${METHOD}" \
  --version "${VERSION}" \
  --prefix "${PREFIX}" \
  --if-exists "${IF_EXISTS}" \
  --target "${TARGET}" \
  --script-force "${SCRIPT_FORCE}" \
  --cargo-binstall "${CARGO_BINSTALL}" \
  --repos-manifest "${_BASE_DIR}/dependencies/run/os-pkg.yaml" > /dev/null
if [[ "${METHOD}" == "auto" ]]; then
  if [[ -x "${PREFIX}/bin/just" ]]; then
    METHOD=binary
  else
    METHOD=package
  fi
fi
