# shellcheck shell=bash

_bundles__select() {
  local -n _ref="$1"
  _ref=()
  [[ "${ARCHIVE_TOOLS:-}" == true ]] && _ref+=("archive-tools")
  [[ "${BUILD_TOOLS:-}" == true ]] && _ref+=("build-tools")
  [[ "${DATA_TOOLS:-}" == true ]] && _ref+=("data-tools")
  [[ "${DATABASE_DEV:-}" == true ]] && _ref+=("database-dev")
  [[ "${DATABASE_TOOLS:-}" == true ]] && _ref+=("database-tools")
  [[ "${DEV_LIBS:-}" == true ]] && _ref+=("dev-libs")
  [[ "${DEV_TOOLS:-}" == true ]] && _ref+=("dev-tools")
  [[ "${DOCUMENT_TOOLS:-}" == true ]] && _ref+=("document-tools")
  [[ "${EDITORS:-}" == true ]] && _ref+=("editors")
  [[ "${FILE_UTILS:-}" == true ]] && _ref+=("file-utils")
  [[ "${HEADLESS_BROWSER:-}" == true ]] && _ref+=("headless-browser")
  [[ "${MAN_PAGES:-}" == true ]] && _ref+=("man-pages")
  [[ "${MULTIMEDIA:-}" == true ]] && _ref+=("multimedia")
  [[ "${NETWORK_TOOLS:-}" == true ]] && _ref+=("network-tools")
  [[ "${OS_ESSENTIALS:-}" == true ]] && _ref+=("os-essentials")
  [[ "${PYTHON_DEV:-}" == true ]] && _ref+=("python-dev")
  [[ "${SCI_COMPUTE:-}" == true ]] && _ref+=("sci-compute")
  [[ "${SCRIPT_UTILS:-}" == true ]] && _ref+=("script-utils")
  [[ "${SHELLS:-}" == true ]] && _ref+=("shells")
  [[ "${SYS_MONITOR:-}" == true ]] && _ref+=("sys-monitor")
  [[ "${TERMINAL_UX:-}" == true ]] && _ref+=("terminal-ux")
  [[ "${TEXT_PROCESSING:-}" == true ]] && _ref+=("text-processing")
  [[ "${VCS_TOOLS:-}" == true ]] && _ref+=("vcs-tools")
  return 0
}

__install_run__() {
  local -a _bundles
  _bundles__select _bundles

  if [[ ${#_bundles[@]} -eq 0 ]]; then
    logging__skip "No bundles selected; nothing to install."
    return 0
  fi

  local -a _dep_args=()
  case "${IF_EXISTS:-skip}" in
    update) _dep_args+=(--update) ;;
    fail) _dep_args+=(--fail-if-installed) ;;
  esac

  local _bundle
  for _bundle in "${_bundles[@]}"; do
    __dep_install__ run "${_bundle}" "${_dep_args[@]+"${_dep_args[@]}"}"
  done
}

__if_exists_dispatch__() {
  case "${IF_EXISTS:-skip}" in
    uninstall) __uninstall_run__ ;;
    reinstall)
      __uninstall_run__
      __install__
      ;;
    *) __install__ ;;
  esac
}

__uninstall_run__() {
  local -a _bundles
  _bundles__select _bundles

  if [[ ${#_bundles[@]} -eq 0 ]]; then
    logging__skip "No bundles selected; nothing to uninstall."
    return 0
  fi

  local _bundle
  for _bundle in "${_bundles[@]}"; do
    __dep_uninstall__ run "${_bundle}"
  done
}
