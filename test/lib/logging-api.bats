#!/usr/bin/env bats
# Unit tests for lib/logging-api.sh (POSIX sh).

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
}

_LOGGING_API="${BATS_TEST_DIRNAME}/../../lib/logging-api.sh"

@test "logging-api buffers without live stderr on success path" {
  local _stderr="${BATS_TEST_TMPDIR}/api-silent.stderr"
  run sh -c "
    exec 2>'${_stderr}'
    . '${_LOGGING_API}'
    logging__pending_init
    logging__info 'buffered-only'
    logging__pending_handoff
    logging__launch 'handed-off'
    test -s \"\${_LOGGING__PENDING_FILE}\" && grep -q 'buffered-only' \"\${_LOGGING__PENDING_FILE}\"
  "
  assert_success
  run grep -q 'buffered-only' "$_stderr"
  assert_failure
  run grep -q 'handed-off' "$_stderr"
  assert_failure
}

@test "logging-api pending file uses structured records" {
  run sh -c "
    . '${_LOGGING_API}'
    logging__pending_init
    logging__error 'bootstrap-fail-msg'
    logging__pending_handoff
    grep -q \"\$(printf '1\t⛔ bootstrap-fail-msg')\" \"\${_LOGGING__PENDING_FILE}\"
  "
  assert_success
}

@test "logging-api dumps pending journal on failure before handoff" {
  local _stderr="${BATS_TEST_TMPDIR}/api-fail.stderr"
  run sh -c "
    exec 2>'${_stderr}'
    . '${_LOGGING_API}'
    logging__pending_init
    logging__error 'visible-on-failure'
    exit 1
  "
  assert_failure
  run grep -q 'visible-on-failure' "$_stderr"
  assert_success
}

@test "logging-api set_prefix decorates pending dump on failure" {
  local _stderr="${BATS_TEST_TMPDIR}/api-prefix.stderr"
  run sh -c "
    exec 2>'${_stderr}'
    . '${_LOGGING_API}'
    logging__pending_init
    logging__set_prefix 'feat-a'
    logging__error 'bootstrap-fail'
    exit 1
  "
  assert_failure
  run grep -q '⛔ feat-a: bootstrap-fail' "$_stderr"
  assert_success
}

@test "logging-api does not dump pending journal after handoff" {
  local _stderr="${BATS_TEST_TMPDIR}/api-handoff.stderr"
  local _pending="${BATS_TEST_TMPDIR}/handoff.pending"
  run sh -c "
    exec 2>'${_stderr}'
    . '${_LOGGING_API}'
    logging__pending_init
    logging__info 'after-handoff'
    logging__pending_handoff
    exit 1
  "
  assert_failure
  run grep -q 'after-handoff' "$_stderr"
  assert_failure
}
