#!/usr/bin/env bats
# Integration tests for lib/file.bash — exercises real extraction tools.
#
# file__extract_archive handles tool bootstrapping internally, so no
# explicit setup is required beyond loading the lib.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  reload_lib
}

@test "file__extract_archive: extracts .tar.gz and produces correct files" {
  local _arc="${BATS_TEST_DIRNAME}/../fixtures/archives/hello.tar.gz"
  local _dest="${BATS_TEST_TMPDIR}/out_tgz"
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  [[ -f "${_dest}/hello.txt" ]]
}

@test "file__extract_archive: extracts .tgz using .tgz extension" {
  local _arc="${BATS_TEST_DIRNAME}/../fixtures/archives/world.tgz"
  local _dest="${BATS_TEST_TMPDIR}/out_tgz2"
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  [[ -f "${_dest}/world.txt" ]]
}

@test "file__extract_archive: uses original_name for format detection" {
  local _tmpfile
  _tmpfile="$(mktemp "${BATS_TEST_TMPDIR}/archive.XXXXXX")"
  cp "${BATS_TEST_DIRNAME}/../fixtures/archives/named.tar.gz" "$_tmpfile"
  local _dest="${BATS_TEST_TMPDIR}/out_named"
  run file__extract_archive "$_tmpfile" "$_dest" "some_release.tar.gz"
  assert_success
  [[ -f "${_dest}/named.txt" ]]
}

@test "file__extract_archive: creates destination directory when absent" {
  local _arc="${BATS_TEST_DIRNAME}/../fixtures/archives/mkdir_test.tar.gz"
  local _dest="${BATS_TEST_TMPDIR}/newly_created_dir"
  [[ ! -d "$_dest" ]]
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  assert_dir_exists "$_dest"
}

@test "file__extract_archive: extracts .zip archive and produces correct files" {
  local _arc="${BATS_TEST_DIRNAME}/../fixtures/archives/test.zip"
  local _dest="${BATS_TEST_TMPDIR}/out_zip"
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  [[ -f "${_dest}/zipped.txt" ]]
  [[ "$(cat "${_dest}/zipped.txt")" == "zipped" ]]
}
