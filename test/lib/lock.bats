#!/usr/bin/env bats
# Unit tests for lib/lock.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
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

# ---------------------------------------------------------------------------
# bootstrap__flock bootstrap
# ---------------------------------------------------------------------------

@test "bootstrap__flock: returns 0 when flock is present" {
  [[ "$(uname)" != "Darwin" ]] || skip "flock is unavailable on macOS"
  run bootstrap__flock
  assert_success
}

@test "lock__run_with_lockfile uses spinlock fallback when flock is absent" {
  ospkg__run() { return 1; }
  export -f ospkg__run
  begin_path_isolation mkdir rmdir sleep dirname mktemp
  local _lock="${BATS_TEST_TMPDIR}/t.lock"
  run --separate-stderr lock__run_with_lockfile "$_lock" "printf '%s\n' spinlock-ran"
  end_path_isolation
  assert_success
  assert_output "spinlock-ran"
}
