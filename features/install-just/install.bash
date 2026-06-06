# shellcheck shell=bash

__resolve_method() {
  # Binary releases are published for all platforms with a known Rust triple.
  if [[ -n "$(os__rust_triple)" ]]; then
    printf 'binary\n'
  else
    printf 'package\n'
  fi
}

__install_run_script_pre() {
  declare -g -a _FEAT_INSTALL_SCRIPT_ARGS
  _FEAT_INSTALL_SCRIPT_ARGS=(--to "${_RESOLVED_PREFIX%/}/bin")
  [[ -v VERSION && -n "${VERSION}" ]] && _FEAT_INSTALL_SCRIPT_ARGS+=(--tag "${VERSION}")
  [[ "${SCRIPT_FORCE:-false}" == true ]] && _FEAT_INSTALL_SCRIPT_ARGS+=(--force)
}
