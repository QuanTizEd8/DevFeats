# shellcheck shell=bash

__install_run_npm__() {
  if [ "${VERSION}" = "latest" ] && command -v corepack > /dev/null 2>&1; then
    logging__info "Enabling Yarn via corepack..."
    corepack enable
    return 0
  fi

  local _pkg="yarn"
  [ "${VERSION}" != "latest" ] && _pkg+="@${VERSION}"

  local -a _install_args=(install -g)
  [[ -n "${_FEAT_CONTRACT_PREFIX_VAR:-}" && -n "${!_FEAT_CONTRACT_PREFIX_VAR:-}" ]] &&
    _install_args+=(--prefix "${!_FEAT_CONTRACT_PREFIX_VAR}")
  _install_args+=("${_pkg}")

  npm "${_install_args[@]}"
}
