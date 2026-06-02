# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# pixi supports only the binary install method.
# shellcheck disable=SC2329,SC2317
__resolve_method() { printf 'binary\n'; }

# Override: use pixi's native self-update command for updates.
# shellcheck disable=SC2329,SC2317
__update_run__() {
  if __feat_check_version_match__; then return 0; fi
  logging__info "Updating pixi to version '${VERSION}' via self-update."
  "${_FEAT_EXISTING_PATH}" self-update --version "${VERSION}"
}

# Invoked by the generated prefix activation system for each configured shell.
# shellcheck disable=SC2329,SC2317
prefix_activation_snippet() {
  if [ -n "${HOME_DIR}" ]; then
    printf 'export PIXI_HOME="%s"\n' "${HOME_DIR}"
  else
    # shellcheck disable=SC2016
    printf 'export PIXI_HOME="${HOME}/.pixi"\n'
  fi
  return 0
}

_write_lifecycle_hooks() {
  # In a devcontainer build, install a root-owned entrypoint that runs at
  # container start to fix ownership of the .pixi named volume mount.
  # Docker creates named volumes owned by root; the entrypoint chowns the
  # directory to the configured remote user so they can write to it.
  # On standalone/host installs there is no named volume and no entrypoint
  # caller, so this section is skipped.
  os__is_devcontainer_build || return 0
  mkdir -p "${_FEAT_LIFECYCLE_DIR}"
  printf '#!/bin/sh\n"%s" info --extended\n' "${_DF_EXPECTED_CMD}" \
    > "${_FEAT_LIFECYCLE_ON_CREATE}verification.sh"
  chmod +x "${_FEAT_LIFECYCLE_ON_CREATE}verification.sh"
  install__copy_bin "${_FEAT_FILES_DIR}/entrypoint.sh" "${_FEAT_ENTRYPOINT_PATH}"
  printf 'PIXI_VOLUME_USER="%s"\n' "${_REMOTE_USER}" \
    > "${_FEAT_LIFECYCLE_DIR}/entrypoint.sh.conf"
}

__skip_post() {
  _write_lifecycle_hooks
}

__install_finish_post() {
  _write_lifecycle_hooks
}
