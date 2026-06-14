# shellcheck shell=bash

__install_run_script_pre() {
  logging__install "Preparing just installer args (dest='${_RESOLVED_PREFIX%/}/bin')."
  declare -g -a _FEAT_INSTALL_SCRIPT_ARGS
  _FEAT_INSTALL_SCRIPT_ARGS=(--to "${_RESOLVED_PREFIX%/}/bin")
  [[ -v VERSION && -n "${VERSION}" ]] && _FEAT_INSTALL_SCRIPT_ARGS+=(--tag "${VERSION}")
  [[ "${SCRIPT_FORCE:-false}" == true ]] && _FEAT_INSTALL_SCRIPT_ARGS+=(--force)
}
