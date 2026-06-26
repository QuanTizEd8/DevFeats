#!/usr/bin/env bats
# Unit tests for dependency manifest helpers in the install framework (install.tmpl.bash).

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  load 'helpers/stubs'
  load 'helpers/ctx'
  load 'helpers/capture'

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

@test "__dep_install_from_env__ uses ctx registry (no --extra-var)" {
  VERSION="14.0.0"
  METHOD="binary"
  __ctx_sync__
  OSPKG_MANIFEST_BASE_RUN=$'packages:\n- jq'
  run __dep_install_from_env__ OSPKG_MANIFEST_BASE_RUN run base
  assert_success
  grep -Fq -- '--manifest' "${BATS_TEST_TMPDIR}/ospkg.log"
  [[ "$(ctx__get feat.version)" == "14.0.0" ]]
  ! grep -Fq -- '--extra-var' "${BATS_TEST_TMPDIR}/ospkg.log"
}

@test "ctx sync: feat.version and feat.method available for manifests" {
  VERSION="1.2.3"
  METHOD="package"
  install_test__capture_version_input
  __ctx_sync__
  [[ "$(ctx__get feat.version)" == "1.2.3" ]]
  [[ "$(ctx__get feat.method)" == "package" ]]
}

@test "ctx sync: stable channel keeps feat.version_input" {
  VERSION="stable"
  METHOD="package"
  install_test__capture_version_input
  __ctx_sync_version__
  [[ "$(ctx__get feat.version_input)" == "stable" ]]
  [[ "$(ctx__get feat.version)" == "stable" ]]
}

@test "ctx sync: upstream-package preserves VERSION_INPUT after resolution" {
  METHOD="upstream-package"
  VERSION="2.47.0"
  VERSION_INPUT="stable"
  __ctx_sync_version__
  [[ "$(ctx__get feat.version_input)" == "stable" ]]
  [[ "$(ctx__get feat.version)" == "2.47.0" ]]
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

@test "__dep_method_env_var__ uppercases method and lifecycle" {
  METHOD="upstream-package"
  [[ "$(__dep_method_env_var__ run)" == "OSPKG_MANIFEST_METHOD_UPSTREAM_PACKAGE_RUN" ]]
  [[ "$(__dep_method_env_var__ build)" == "OSPKG_MANIFEST_METHOD_UPSTREAM_PACKAGE_BUILD" ]]
}

@test "__dep_install_for_method__ installs run deps for package method" {
  METHOD="package"
  OSPKG_MANIFEST_METHOD_PACKAGE_RUN=$'packages:\n- shfmt'
  run __dep_install_for_method__
  assert_success
  grep -Fq 'shfmt' "${BATS_TEST_TMPDIR}/ospkg.log"
}

@test "__dep_install_for_method__ tolerates unset KEEP_REPOS when METHOD is not upstream-package" {
  unset KEEP_REPOS
  METHOD="package"
  OSPKG_MANIFEST_METHOD_PACKAGE_RUN=$'packages:\n- shfmt'
  run __dep_install_for_method__
  assert_success
  grep -Fq 'shfmt' "${BATS_TEST_TMPDIR}/ospkg.log"
}

@test "__dep_fetch_extra_args__ tolerates unset FETCH_HEADERS under set -u" {
  unset FETCH_HEADERS
  local -a _args=()
  run __dep_fetch_extra_args__ _args
  assert_success
  [[ ${#_args[@]} -eq 0 ]]
}
