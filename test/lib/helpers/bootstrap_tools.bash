# shellcheck shell=bash
# Shared jq/yq bootstrap helpers for bats suites that need both tools once per file.
#
# Bootstrap downloads are isolated in a short-lived subshell; stable copies land
# in BATS_FILE_TMPDIR.  Call test_bootstrap__setup_file_jq_yq from setup_file(),
# then test_bootstrap__require_* and test_bootstrap__wire_tools_for_run from setup().

test_bootstrap__setup_file_jq_yq() {
  load 'helpers/common'

  TEST_BOOTSTRAP_JQ_READY=0
  if bash -c '. "$1/__init__.bash" && bootstrap__jq' _ "${LIB_ROOT}" > /dev/null 2>&1; then
    TEST_BOOTSTRAP_JQ_READY=1
  fi

  TEST_BOOTSTRAP_JQ_BIN=""
  TEST_BOOTSTRAP_YQ_BIN=""
  if [[ "${TEST_BOOTSTRAP_JQ_READY}" == "1" ]]; then
    local _jq_path _yq_path
    _jq_path="$(bash -c '. "$1/__init__.bash" && command -v jq' _ "${LIB_ROOT}" 2> /dev/null)" || true
    _yq_path="$(
      bash -c '
        source "$1/__init__.bash" 2>/dev/null || exit 1
        ospkg__detect 2>/dev/null || exit 1
        bootstrap__yq 2>/dev/null || exit 1
      ' _ "${LIB_ROOT}" 2> /dev/null
    )" || true
    if [[ -n "${_jq_path}" && -x "${_jq_path}" ]]; then
      cp "${_jq_path}" "${BATS_FILE_TMPDIR}/jq"
      chmod +x "${BATS_FILE_TMPDIR}/jq"
      TEST_BOOTSTRAP_JQ_BIN="${BATS_FILE_TMPDIR}/jq"
    fi
    if [[ -n "${_yq_path}" && -x "${_yq_path}" ]]; then
      cp "${_yq_path}" "${BATS_FILE_TMPDIR}/yq"
      chmod +x "${BATS_FILE_TMPDIR}/yq"
      TEST_BOOTSTRAP_YQ_BIN="${BATS_FILE_TMPDIR}/yq"
    fi
  fi

  export TEST_BOOTSTRAP_JQ_READY TEST_BOOTSTRAP_JQ_BIN TEST_BOOTSTRAP_YQ_BIN
}

test_bootstrap__require_jq() {
  [[ "${TEST_BOOTSTRAP_JQ_READY:-0}" == "1" ]] || skip "jq bootstrap unavailable"
  [[ -n "${TEST_BOOTSTRAP_JQ_BIN:-}" && -x "${TEST_BOOTSTRAP_JQ_BIN}" ]] ||
    skip "jq unavailable (no network or not root)"
}

test_bootstrap__require_yq() {
  [[ "${TEST_BOOTSTRAP_JQ_READY:-0}" == "1" ]] || skip "jq bootstrap unavailable"
  [[ -n "${TEST_BOOTSTRAP_YQ_BIN:-}" && -x "${TEST_BOOTSTRAP_YQ_BIN}" ]] ||
    skip "yq unavailable (no network or not root)"
}

test_bootstrap__require_jq_yq() {
  test_bootstrap__require_jq
  test_bootstrap__require_yq
}

test_bootstrap__prepend_tools_path() {
  [[ -n "${TEST_BOOTSTRAP_JQ_BIN:-}" && -x "${TEST_BOOTSTRAP_JQ_BIN}" ]] || return 0
  [[ -n "${TEST_BOOTSTRAP_YQ_BIN:-}" && -x "${TEST_BOOTSTRAP_YQ_BIN}" ]] || return 0
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  ln -sf "${TEST_BOOTSTRAP_JQ_BIN}" "${BATS_TEST_TMPDIR}/bin/jq"
  ln -sf "${TEST_BOOTSTRAP_YQ_BIN}" "${BATS_TEST_TMPDIR}/bin/yq"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

test_bootstrap__stub_yq() {
  # shellcheck disable=SC2329  # exported stub for bats run subshells
  bootstrap__yq() {
    if [[ -n "${_BOOTSTRAP__YQ_BIN:-}" ]]; then
      printf '%s\n' "${_BOOTSTRAP__YQ_BIN}"
      return 0
    fi
    _BOOTSTRAP__YQ_BIN="${TEST_BOOTSTRAP_YQ_BIN}"
    printf '%s\n' "${_BOOTSTRAP__YQ_BIN}"
  }
  export -f bootstrap__yq
}

# PATH + bootstrap__yq stub for suites that call tool helpers via bats `run`.
test_bootstrap__wire_tools_for_run() {
  test_bootstrap__prepend_tools_path
  test_bootstrap__stub_yq
}
