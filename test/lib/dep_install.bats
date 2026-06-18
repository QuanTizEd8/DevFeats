#!/usr/bin/env bats
# Unit tests for dependency manifest helpers in features/install.tmpl.bash.

bats_require_minimum_version 1.5.0

setup_file() {
  load 'helpers/common'

  _DEP_FUNCS="$(
    sed -n '2306,2492p' "${REPO_ROOT}/features/install.tmpl.bash"
  )"
  [[ -n "${_DEP_FUNCS}" ]] || {
    echo "FATAL: could not extract dependency helpers from install.tmpl.bash" >&2
    return 1
  }
  export _DEP_FUNCS
}

setup() {
  load 'helpers/common'
  load 'helpers/stubs'

  eval "${_DEP_FUNCS}"

  OSPKG_MANIFEST_BASE_RUN=""
  METHOD="package"
  VERSION="stable"
  KEEP_REPOS="false"
  FETCH_NETRC=""
  FETCH_HEADERS=()
  _SYSSET_BUILD_CONTEXT="test::feat"
  _FEAT_DEP_TRIGGER_SPECS=$'archive_tools\tOSPKG_MANIFEST_OPTION_ARCHIVE_TOOLS\tARCHIVE_TOOLS'

  ospkg__run() {
    printf 'ospkg__run %s\n' "$*" >> "${BATS_TEST_TMPDIR}/ospkg.log"
    return 0
  }

  users__is_privileged() { return 0; }
}

@test "__dep_normalize_manifest_value__ expands literal backslash-n" {
  OSPKG_MANIFEST_BASE_RUN='packages:\n- jq'
  __dep_normalize_manifest_value__ OSPKG_MANIFEST_BASE_RUN
  [[ "${OSPKG_MANIFEST_BASE_RUN}" == *$'\n'* ]]
  [[ "${OSPKG_MANIFEST_BASE_RUN}" == *"- jq"* ]]
}

@test "__dep_install_from_env__ skips empty manifest" {
  OSPKG_MANIFEST_BASE_RUN=""
  run __dep_install_from_env__ OSPKG_MANIFEST_BASE_RUN run base
  assert_success
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg.log" ]]
}

@test "__dep_install_from_env__ calls ospkg with manifest" {
  OSPKG_MANIFEST_METHOD_PACKAGE_RUN=$'packages:\n- jq'
  run __dep_install_from_env__ OSPKG_MANIFEST_METHOD_PACKAGE_RUN run method-package
  assert_success
  grep -Fq -- '--manifest' "${BATS_TEST_TMPDIR}/ospkg.log"
}

@test "__dep_install_option_bound__ honors boolean gate" {
  ARCHIVE_TOOLS='false'
  run __dep_install_option_bound__
  assert_success
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg.log" ]]

  ARCHIVE_TOOLS='true'
  OSPKG_MANIFEST_OPTION_ARCHIVE_TOOLS=$'packages:\n- zip'
  run __dep_install_option_bound__
  assert_success
  grep -Fq 'zip' "${BATS_TEST_TMPDIR}/ospkg.log"
}

@test "__dep_pm_extra_args__ passes VERSION for package method" {
  VERSION="1.2.3"
  local -a _args=()
  __dep_pm_extra_args__ run _args
  [[ " ${_args[*]} " == *" VERSION=1.2.3 "* ]]
}

@test "__dep_install_from_env__ skips on Linux when not privileged" {
  OSPKG_MANIFEST_METHOD_PACKAGE_RUN=$'packages:\n- jq'
  users__is_privileged() { return 1; }
  os__kernel() { printf 'Linux\n'; }
  run __dep_install_from_env__ OSPKG_MANIFEST_METHOD_PACKAGE_RUN run method-package
  assert_success
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg.log" ]]
}

@test "__dep_install_from_env__ installs on Darwin when not privileged" {
  OSPKG_MANIFEST_METHOD_PACKAGE_RUN=$'packages:\n- jq'
  users__is_privileged() { return 1; }
  os__kernel() { printf 'Darwin\n'; }
  run __dep_install_from_env__ OSPKG_MANIFEST_METHOD_PACKAGE_RUN run method-package
  assert_success
  grep -Fq -- '--manifest' "${BATS_TEST_TMPDIR}/ospkg.log"
}

@test "__dep_install_for_method__ skips build deps on Linux when not privileged" {
  METHOD="source"
  OSPKG_MANIFEST_METHOD_SOURCE_BUILD=$'packages:\n- make'
  users__is_privileged() { return 1; }
  os__kernel() { printf 'Linux\n'; }
  run __dep_install_for_method__
  assert_success
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg.log" ]]
}
