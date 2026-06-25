#!/usr/bin/env bats
# Integration tests for lib/json.sh — exercises real jq binary interactions.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  load '../helpers/stubs'
  reload_lib
}

@test "bootstrap__jq: succeeds when jq is already available" {
  command -v jq > /dev/null 2>&1 || skip "real jq is not available on this host"
  create_pass_through_bin "jq"
  prepend_fake_bin_path
  run bootstrap__jq
  assert_success
}
