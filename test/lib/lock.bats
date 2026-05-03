#!/usr/bin/env bats
# Unit tests for lib/lock.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib lock.sh
}

@test "lock__run_with_lockfile runs command serialized by lock path" {
  local _lock="${BATS_TEST_TMPDIR}/t.lock"
  local _out="${BATS_TEST_TMPDIR}/out.txt"
  touch "$_out"
  lock__run_with_lockfile "$_lock" "echo one >> \"${_out}\""
  lock__run_with_lockfile "$_lock" "echo two >> \"${_out}\""
  run cat "$_out"
  assert_success
  assert_output $'one\ntwo'
}
