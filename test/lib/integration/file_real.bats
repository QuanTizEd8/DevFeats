#!/usr/bin/env bats
# Integration tests for lib/file.sh — exercises real zip extraction.
#
# file__extract_archive handles tool installation internally (bootstrap__unzip),
# so no setup beyond loading the lib is required. The test exercises the full
# production code path including tool bootstrapping.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  reload_lib
}

@test "file__extract_archive: extracts .zip archive and produces correct files" {
  local _arc="${BATS_TEST_DIRNAME}/../fixtures/archives/test.zip"
  local _dest="${BATS_TEST_TMPDIR}/out_zip"
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  [[ -f "${_dest}/zipped.txt" ]]
  [[ "$(cat "${_dest}/zipped.txt")" == "zipped" ]]
}
