# shellcheck shell=bash

__install_run__() {
  local -a _bundles=()
  [[ "${ARCHIVE_TOOLS:-}"    == true ]] && _bundles+=("archive-tools")
  [[ "${BUILD_TOOLS:-}"      == true ]] && _bundles+=("build-tools")
  [[ "${DATA_TOOLS:-}"       == true ]] && _bundles+=("data-tools")
  [[ "${DATABASE_DEV:-}"     == true ]] && _bundles+=("database-dev")
  [[ "${DATABASE_TOOLS:-}"   == true ]] && _bundles+=("database-tools")
  [[ "${DEV_LIBS:-}"         == true ]] && _bundles+=("dev-libs")
  [[ "${DEV_TOOLS:-}"        == true ]] && _bundles+=("dev-tools")
  [[ "${DOCUMENT_TOOLS:-}"   == true ]] && _bundles+=("document-tools")
  [[ "${EDITORS:-}"          == true ]] && _bundles+=("editors")
  [[ "${FILE_UTILS:-}"       == true ]] && _bundles+=("file-utils")
  [[ "${HEADLESS_BROWSER:-}" == true ]] && _bundles+=("headless-browser")
  [[ "${MAN_PAGES:-}"        == true ]] && _bundles+=("man-pages")
  [[ "${MULTIMEDIA:-}"       == true ]] && _bundles+=("multimedia")
  [[ "${NETWORK_TOOLS:-}"    == true ]] && _bundles+=("network-tools")
  [[ "${OS_ESSENTIALS:-}"    == true ]] && _bundles+=("os-essentials")
  [[ "${PYTHON_DEV:-}"       == true ]] && _bundles+=("python-dev")
  [[ "${SCI_COMPUTE:-}"      == true ]] && _bundles+=("sci-compute")
  [[ "${SCRIPT_UTILS:-}"     == true ]] && _bundles+=("script-utils")
  [[ "${SHELLS:-}"           == true ]] && _bundles+=("shells")
  [[ "${SYS_MONITOR:-}"      == true ]] && _bundles+=("sys-monitor")
  [[ "${TERMINAL_UX:-}"      == true ]] && _bundles+=("terminal-ux")
  [[ "${TEXT_PROCESSING:-}"  == true ]] && _bundles+=("text-processing")
  [[ "${VCS_TOOLS:-}"        == true ]] && _bundles+=("vcs-tools")

  if [[ ${#_bundles[@]} -eq 0 ]]; then
    logging__skip "No bundles selected; nothing to install."
    return 0
  fi

  local _bundle
  for _bundle in "${_bundles[@]}"; do
    __dep_install__ run "${_bundle}"
  done
}
