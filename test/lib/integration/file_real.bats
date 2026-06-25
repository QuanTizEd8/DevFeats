#!/usr/bin/env bats
# Integration tests for lib/file.sh — exercises real zip extraction.
#
# Verifies the full file__extract_archive pipeline for .zip files using a
# pre-committed fixture archive and a real unzip binary installed via the
# lib's own bootstrap__unzip mechanism.
#
# Requires a supported package manager and root (to install unzip if absent).
# Gated by SYSSET_RUN_INTEGRATION_DEPS=1; skipped otherwise.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  load '../helpers/stubs'
  reload_lib
  if [[ "${SYSSET_RUN_INTEGRATION_DEPS:-0}" != "1" ]]; then
    skip "set SYSSET_RUN_INTEGRATION_DEPS=1 to run integration tests"
  fi
  _ospkg__detect || skip "no supported package manager detected"
  bootstrap__unzip || skip "unzip could not be installed"
  create_pass_through_bin "unzip"
  prepend_fake_bin_path
}

@test "file__extract_archive: extracts .zip archive and produces correct files" {
  local _arc="${BATS_TEST_DIRNAME}/../fixtures/archives/test.zip"
  local _dest="${BATS_TEST_TMPDIR}/out_zip"
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  [[ -f "${_dest}/zipped.txt" ]]
  [[ "$(cat "${_dest}/zipped.txt")" == "zipped" ]]
}
