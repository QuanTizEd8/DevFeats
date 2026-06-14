# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# Override: use pixi's native self-update command for updates.
# Version and prefix checks are handled by __update_predispatch__; this hook
# only runs when a version update is actually needed.
# shellcheck disable=SC2329,SC2317
__update_run__() {
  logging__install "Updating pixi to version '${VERSION}' via self-update."
  "${_FEAT_EXISTING_PATH}" self-update --version "${VERSION}" || {
    logging__error "pixi self-update to version '${VERSION}' failed."
    return 1
  }
}

# Invoked by the generated prefix activation system for each configured shell.
# shellcheck disable=SC2329,SC2317
__prefix_activation_snippet() {
  if [ -n "${HOME_DIR}" ]; then
    # Normalize a leading ~ to ${HOME} so the expression expands correctly in
    # double-quoted shell strings at runtime (bare tilde is not expanded there).
    local _pixi_home="${HOME_DIR}"
    # shellcheck disable=SC2088,SC2016
    [[ "$_pixi_home" == '~/'* ]] && _pixi_home='${HOME}/'"${_pixi_home#\~/}"
    # shellcheck disable=SC2016
    [[ "$_pixi_home" == '~' ]] && _pixi_home='${HOME}'
    printf 'export PIXI_HOME="%s"\n' "$_pixi_home"
  else
    # shellcheck disable=SC2016
    printf 'export PIXI_HOME="${HOME}/.pixi"\n'
  fi
  return 0
}
