resolve_input_version() {
  local _out
  _out="$(github__resolve_version "${GH_REPO}" "$VERSION")" || return 1
  _resolved_version="${_out#*$'\n'}"
}

resolve_input_target() {
  if [[ -n "$TARGET" && "$TARGET" != "auto" ]]; then
    _resolved_target="$TARGET"
    return 0
  fi
  _resolved_target="$(os__rust_triple)" || {
    logging__error "install-just: unsupported kernel/arch '$(os__kernel)/$(os__arch)' for binary target."
    return 1
  }
}

install_binary() {
  local _base _asset
  _base="https://github.com/${GH_REPO}/releases/download/${_resolved_version}"
  _asset="just-${_resolved_version}-${_resolved_target}.tar.gz"

  github__install_release \
    --repo "${GH_REPO}" --tag "${_resolved_version}" \
    --asset "$_asset" --binary-src just --binary-dest "${PREFIX%/}/bin/" \
    --sidecar "${_base}/SHA256SUMS" \
    --installer-dir "${INSTALLER_DIR}" ||
    return 1
}

install_package() {
  __install_dependencies run os-pkg
}

install_script() {
  local _tmp _script _dest
  _tmp="$(file__tmpdir "install/just-script")"
  _script="${_tmp}/install.sh"
  _dest="${PREFIX%/}/bin/just"
  net__fetch_url_file "https://just.systems/install.sh" "$_script" || return 1
  chmod +x "$_script" || return 1

  local -a _cmd
  _cmd=(bash "$_script" --to "${PREFIX%/}/bin")
  if [[ -n "$_resolved_version" && "$_resolved_version" != "latest" ]]; then
    _cmd+=(--tag "$_resolved_version")
  fi
  if [[ -n "$_resolved_target" && "$_resolved_target" != "auto" ]]; then
    _cmd+=(--target "$_resolved_target")
  fi
  if [[ "$SCRIPT_FORCE" == "true" ]]; then
    _cmd+=(--force)
  fi

  "${_cmd[@]}" || return 1
  [[ -x "$_dest" ]] || return 1
}

install_cargo() {
  local _dest
  command -v cargo > /dev/null 2>&1 || {
    logging__error "install-just: method=cargo requires cargo in PATH."
    return 1
  }

  if [[ "$CARGO_BINSTALL" == "true" ]] && cargo binstall --help > /dev/null 2>&1; then
    if [[ -n "$_resolved_version" && "$_resolved_version" != "latest" ]]; then
      cargo binstall --no-confirm --root "$PREFIX" --version "$_resolved_version" just || return 1
    else
      cargo binstall --no-confirm --root "$PREFIX" just || return 1
    fi
  else
    local -a _cmd
    _cmd=(cargo install --root "$PREFIX" --force)
    if [[ -n "$_resolved_version" && "$_resolved_version" != "latest" ]]; then
      _cmd+=(--version "$_resolved_version")
    fi
    _cmd+=(just)
    "${_cmd[@]}" || return 1
  fi

  _dest="${PREFIX%/}/bin/just"
  [[ -x "$_dest" ]] || return 1
}

__install() {
  [[ "$IF_EXISTS" == "skip" || "$IF_EXISTS" == "fail" || "$IF_EXISTS" == "reinstall" ]] || return 1

  local _existing
  _existing="$(command -v just 2> /dev/null || true)"

  if [[ -n "$_existing" ]]; then
    case "$IF_EXISTS" in
      fail)
        logging__error "install-just: just already exists at $_existing."
        return 1
        ;;
      skip)
        return 0
        ;;
      reinstall)
        ;;
    esac
  fi

  case "$METHOD" in
    binary)
      local _resolved_version _resolved_target
      resolve_input_version || return 1
      resolve_input_target || return 1
      install_binary
      ;;
    package)
      install_package
      ;;
    script)
      local _resolved_version="" _resolved_target
      resolve_input_version 2> /dev/null || true
      [[ -z "$_resolved_version" ]] && _resolved_version="latest"
      resolve_input_target || return 1
      install_script
      ;;
    cargo)
      local _resolved_version=""
      resolve_input_version 2> /dev/null || true
      [[ -z "$_resolved_version" ]] && _resolved_version="latest"
      install_cargo
      ;;
    auto)
      local _resolved_version="" _resolved_target=""
      resolve_input_version 2> /dev/null || true
      resolve_input_target 2> /dev/null || true
      if [[ -n "$_resolved_version" && -n "$_resolved_target" ]]; then
        install_binary && return 0
      fi
      install_package && return 0
      install_script && return 0
      install_cargo
      ;;
    *)
      logging__error "install-just: invalid method '${METHOD}'."
      return 1
      ;;
  esac
}

__install

if [[ "${METHOD}" == "auto" ]]; then
  if [[ -x "${PREFIX}/bin/just" ]]; then
    METHOD=binary
  else
    METHOD=package
  fi
fi
