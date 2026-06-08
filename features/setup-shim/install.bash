# shellcheck shell=bash

__install_run__() {
  logging__install "Deploying setup-shim wrappers to '${_RESOLVED_PREFIX}/bin'."
  local _bin="${_RESOLVED_PREFIX}/bin"
  file__mkdir "${_bin}"

  _install_shim() {
    local _src="${_FEAT_FILES_DIR}/$1" _dst="${_bin}/$1"
    [[ -f "${_src}" ]] || {
      logging__error "setup-shim: source file not found: ${_src}"
      return 1
    }
    file__cp "${_src}" "${_dst}"
    file__chmod +rx "${_dst}"
    logging__success "  $1 → ${_dst}"
  }

  [[ "${CODE}" == "true" ]] && _install_shim "code"
  [[ "${DEVCONTAINER_INFO}" == "true" ]] && _install_shim "devcontainer-info"
  [[ "${SYSTEMCTL}" == "true" ]] && _install_shim "systemctl"
  logging__success "setup-shim deployment finished."
  return 0
}
