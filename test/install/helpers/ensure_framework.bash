# shellcheck shell=bash
# Load synced install.bash once per bats process (setup_file does not share shell with tests).

install_test__ensure_framework() {
  if declare -f __dep_normalize_manifest_value__ > /dev/null 2>&1; then
    return 0
  fi
  load 'helpers/common'
  install_test__source_framework
}
