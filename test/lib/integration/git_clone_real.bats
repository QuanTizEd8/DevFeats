#!/usr/bin/env bats
# Integration tests for lib/git.sh requiring real git.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  reload_lib git.sh
  if [[ "${SYSSET_RUN_INTEGRATION_DEPS:-0}" != "1" ]]; then
    skip "set SYSSET_RUN_INTEGRATION_DEPS=1 to run integration tests"
  fi
  command -v git > /dev/null 2>&1 || skip "real git is not available"
}

@test "git__clone clones a local bare repo (real git)" {
  local _src="${BATS_TEST_TMPDIR}/src.git"
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git init --bare "$_src" > /dev/null 2>&1

  local _work="${BATS_TEST_TMPDIR}/work"
  git clone "$_src" "$_work" > /dev/null 2>&1
  git -C "$_work" config user.email "test@test.com"
  git -C "$_work" config user.name "Test"
  echo "hi" > "${_work}/file.txt"
  git -C "$_work" add file.txt
  git -C "$_work" commit -m "init" > /dev/null 2>&1
  git -C "$_work" push > /dev/null 2>&1

  run git__clone --url "file://${_src}" --dir "$_dst"
  assert_success
  assert_file_exists "${_dst}/.git/HEAD"
}
