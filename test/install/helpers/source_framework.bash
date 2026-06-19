# shellcheck shell=bash
# Source a synced feature install.bash without running __main__ (framework unit tests).

INSTALL_TEST_FIXTURE="${INSTALL_TEST_FIXTURE:-install-jq}"

install_test__source_framework() {
  local _root="${REPO_ROOT:-}"
  if [[ -z "${_root}" ]]; then
    _root="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  fi
  local _fixture="${INSTALL_TEST_FIXTURE:-install-jq}"
  local _install_bash="${_root}/src/${_fixture}/install.bash"
  if [[ ! -f "${_install_bash}" ]]; then
    echo "FATAL: synced install.bash not found at '${_install_bash}' (run: just sync-src)" >&2
    return 1
  fi
  local _tmp_dir="${BATS_SUITE_TMPDIR:-${TMPDIR:-/tmp}}"
  mkdir -p "${_tmp_dir}"
  local _tmp="${_tmp_dir}/install-framework-${_fixture}.bash"
  # Drop dispatch and strict-mode lines so bats `run` and test helpers keep working.
  sed \
    -e '/^__main__ "\$@"$/d' \
    -e '/^set -Eeuo pipefail$/d' \
    -e '/^shopt -s inherit_errexit$/d' \
    "${_install_bash}" > "${_tmp}"
  # shellcheck source=/dev/null
  source "${_tmp}"
}
