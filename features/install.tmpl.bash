#!/usr/bin/env bash
set -euo pipefail

__usage__() {
  cat << 'EOF'
${{ name }}$ v${{ version }}$

Usage: install.bash [OPTIONS]

Options:
${{ _script.usage_options }}$
EOF
  return
}

__argparse__() {
  if [ "$#" -gt 0 ]; then
    logging__info "Script called with arguments: $*"

    ${{ _script.argparse.cli_inits }}$

    while [ "$#" -gt 0 ]; do
      case $1 in
        ${{ _script.argparse.case_arms }}$
        -h | --help)
          __usage__
          exit 0
          ;;
        --*)
          logging__error "Unknown option: '${1}'"
          exit 1
          ;;
        *)
          logging__error "Unexpected argument: '${1}'"
          exit 1
          ;;
      esac
    done
  else
    logging__info "Script called with no arguments. Read environment variables."

    ${{ _script.argparse.env_reads }}$
  fi

  logging__set_level

  # Apply defaults.
  ${{ _script.argparse.defaults }}$

  # Auto-initialize INSTALLER_DIR to a private temporary directory when not set.
  [ -z "${INSTALLER_DIR:-}" ] && INSTALLER_DIR="$(file__mktmpdir "$_FEAT_ID")"

  # Validate input options.
  ${{ _script.argparse.validations }}$

  # Unexport option variables — values remain accessible in this script,
  # but are not inherited by child processes.
  declare +x ${{ _script.argparse.unexports }}$
}

# shellcheck disable=SC2329,SC2317
_on_exit() {
  local _rc=$?

  if [[ $_rc -eq 0 ]]; then
    logging__success "$_FEAT_NAME script finished successfully."
  else
    logging__fatal "$_FEAT_NAME script exited with error ${_rc}."
  fi

  # Define _cleanup_hook in the hand-written section
  # for feature-specific cleanup (e.g. removing temp files).
  if declare -f _cleanup_hook > /dev/null; then _cleanup_hook; fi

  [[ $_rc -eq 0 ]] && _prefix_post_install

  if [[ "${KEEP_CACHE:-true}" != true ]]; then
    if users__is_privileged || [[ "$(os__kernel)" == "Darwin" ]]; then
      ospkg__clean
    else
      logging__info "Skipping package-manager cache cleanup (no privilege available)."
    fi
  fi

  [[ "${KEEP_BUILD_DEPS:-false}" != true ]] && [[ -z "${_SYSSET_SESSION_TRACK_DIR:-}" ]] && ospkg__cleanup_all_build_groups

  logging__cleanup
  logging__feature_exit "$_FEAT_NAME v$_FEAT_VERSION"
  return
}

# shellcheck disable=SC2329,SC2317
_prefix_post_install() {
  ${{ _script.prefix_post_install_body }}$
  if declare -f _prefix_post_install_hook > /dev/null; then _prefix_post_install_hook; fi
  return
}

${{ _script.dependency_install_functions }}$

# Prefix group helpers (generated)
${{ _script.prefix_resolver_functions }}$


# Path to the feature's root directory.
_FEAT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/__init__.bash
. "$_FEAT_DIR/lib/__init__.bash"

_FEAT_ID="${{ id }}$"
_FEAT_VERSION="${{ version }}$"
_FEAT_NAME="${{ name }}$"
_FEAT_FILES_DIR="${_FEAT_DIR}/files"
_FEAT_DEPS_DIR="${_FEAT_DIR}/dependencies"

${{ _script.env_var_assignments }}$

_SYSSET_BUILD_CONTEXT="${_SYSSET_BUILD_CONTEXT:-feature::$_FEAT_ID}"
export _SYSSET_BUILD_CONTEXT

# Set up logging and exit trap.
logging__setup
logging__feature_entry "$_FEAT_NAME v$_FEAT_VERSION"
trap '_on_exit' EXIT

# Parse and validate input options and set environment variables.
__argparse__ "$@"

${{ _script.dependency_install_calls }}$

${{ _script.prefix_resolver_calls }}$
