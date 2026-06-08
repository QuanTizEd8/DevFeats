# shellcheck shell=bash

__resolve_method() {
  logging__inspect "Resolving METHOD=auto."
  # Binary releases are published for all platforms with a known Rust triple.
  if [[ -n "$(os__rust_triple)" ]]; then
    logging__info "Resolved METHOD=auto → 'binary'."
    printf 'binary\n'
  else
    logging__info "Resolved METHOD=auto → 'package'."
    printf 'package\n'
  fi
}

__install_run_script_pre() {
  logging__install "Preparing just installer args (dest='${_RESOLVED_PREFIX%/}/bin')."
  declare -g -a _FEAT_INSTALL_SCRIPT_ARGS
  _FEAT_INSTALL_SCRIPT_ARGS=(--to "${_RESOLVED_PREFIX%/}/bin")
  [[ -v VERSION && -n "${VERSION}" ]] && _FEAT_INSTALL_SCRIPT_ARGS+=(--tag "${VERSION}")
  [[ "${SCRIPT_FORCE:-false}" == true ]] && _FEAT_INSTALL_SCRIPT_ARGS+=(--force)
}
