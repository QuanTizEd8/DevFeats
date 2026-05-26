#!/usr/bin/env bash
set -euo pipefail

__print_docs__() {
  cat << 'EOF'
${{ name }}$ v${{ version }}$

Usage: install.bash [OPTIONS]

Options:
${{ _script.usage_options }}$
EOF
  return
}

# Set internal environment variables.
__setup_env__() {

  # Common variables available in all features:
  _FEAT_DIR="$(cd "$(dirname "$0")" && pwd)" # Path to the feature's root directory.
  _FEAT_ID="${{ id }}$"
  _FEAT_VERSION="${{ version }}$"
  _FEAT_NAME="${{ name }}$"
  _FEAT_FILES_DIR="${_FEAT_DIR}/files"
  _FEAT_DEPS_DIR="${_FEAT_DIR}/dependencies"

  # Custom environment variables defined in the feature's metadata:
  ${{ _script.env_vars.assignments }}$

  # Unexport variables — values remain accessible in this script,
  # but are not inherited by child processes.
  declare -g +x _FEAT_DIR _FEAT_ID _FEAT_VERSION _FEAT_NAME _FEAT_FILES_DIR _FEAT_DEPS_DIR ${{ _script.env_vars.unexports }}$

  _SYSSET_BUILD_CONTEXT="${_SYSSET_BUILD_CONTEXT:-feature::$_FEAT_ID}"
  export _SYSSET_BUILD_CONTEXT
}

__import_lib__() {
  # shellcheck source=lib/__init__.bash
  . "$_FEAT_DIR/lib/__init__.bash"
}

# Set up logging and exit trap.
__setup_script__() {
  logging__setup
  logging__feature_entry "$_FEAT_NAME v$_FEAT_VERSION"
  trap '__exit__' EXIT
}

__verify_system_requirements__() {
  ${{ _script.system_requirements_guard }}$
}

__parse_args__() {
  if [ "$#" -gt 0 ]; then
    logging__info "Script called with arguments: $*"

    ${{ _script.argparse.cli_inits }}$

    while [ "$#" -gt 0 ]; do
      case $1 in
        ${{ _script.argparse.case_arms }}$
        -h | --help)
          __print_docs__
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

  # Validate input options.
  ${{ _script.argparse.validations }}$

  # Unexport option variables — values remain accessible in this script,
  # but are not inherited by child processes.
  declare -g +x ${{ _script.argparse.unexports }}$
}

# shellcheck disable=SC2329,SC2317
__exit__() {
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

__install_dependencies() {
  local _dep_type="$1"
  local _dep_group="$2"
  shift 2

  if users__is_privileged || [[ "$(os__kernel)" == "Darwin" ]]; then
    local -a _args=(--manifest "$_FEAT_DEPS_DIR/$_dep_type/$_dep_group.yaml")
    [[ "$_dep_type" == "build" ]] && _args+=(--build-group "${_SYSSET_BUILD_CONTEXT}::${_dep_group}")
    ospkg__run "${_args[@]}" "$@"
  else
    logging__warn "Skipping '$_dep_group' group $_dep_type dependency installation (no privilege available); ensure dependencies are pre-installed."
  fi
  return
}

__install_base_dependencies__() {
  [[ -f "$_FEAT_DEPS_DIR/build/base.yaml" ]] && __install_dependencies build base "$@"
  [[ -f "$_FEAT_DEPS_DIR/run/base.yaml" ]] && __install_dependencies run base "$@"
  return
}

# Prefix group helpers (generated)
${{ _script.prefix_resolver_functions }}$


__setup_env__
__import_lib__
__setup_script__
__verify_system_requirements__
__parse_args__ "$@"

# Install base dependencies.
__install_base_dependencies__

${{ _script.prefix_resolver_calls }}$
