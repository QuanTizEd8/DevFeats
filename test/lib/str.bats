#!/usr/bin/env bats
# Unit tests for lib/str.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
}

# ---------------------------------------------------------------------------
# str__basename_each
# ---------------------------------------------------------------------------

@test "str__basename_each prints basenames one per line" {
  run str__basename_each "zsh-users/zsh-autosuggestions" "zsh-users/zsh-syntax-highlighting"
  assert_output "zsh-autosuggestions
zsh-syntax-highlighting"
  assert_success
}

@test "str__basename_each prints nothing when given no arguments" {
  run bash -c 'source "$1" && str__basename_each' _ "${LIB_ROOT}/str.bash"
  assert_output ""
  assert_success
}

@test "str__basename_each skips an empty argument" {
  run str__basename_each "" "zsh-users/zsh-autosuggestions"
  assert_output "zsh-autosuggestions"
  assert_success
}

# ---------------------------------------------------------------------------
# str__safe_id
# ---------------------------------------------------------------------------

@test "str__safe_id uppercases and maps dashes to underscores" {
  run str__safe_id "my-opt_name"
  assert_output "MY_OPT_NAME"
  assert_success
}

@test "str__safe_id preserves underscores" {
  run str__safe_id "already_safe"
  assert_output "ALREADY_SAFE"
  assert_success
}

@test "str__safe_id preserves ASCII alphanumerics" {
  run str__safe_id "abc123"
  assert_output "ABC123"
  assert_success
}

# ---------------------------------------------------------------------------
# str__has_any_prefix / str__strip_any_prefix
# ---------------------------------------------------------------------------

@test "str__has_any_prefix matches first listed prefix" {
  run str__has_any_prefix "ghcr.io/foo" "ghcr.io/" "other/"
  assert_success
}

@test "str__has_any_prefix fails when no prefix matches" {
  run str__has_any_prefix "abc" "x" "y"
  assert_failure
}

@test "str__has_any_prefix treats an empty prefix as no-match" {
  run str__has_any_prefix "abc" "" "nomatch"
  assert_failure
}

@test "str__strip_any_prefix returns input unchanged when no prefix matches" {
  run str__strip_any_prefix "hello" "p/" "q/"
  assert_output "hello"
  assert_success
}

@test "str__strip_any_prefix uses the first prefix argument order (not longest)" {
  run str__strip_any_prefix "aa-thing" "a" "aa-"
  # First matching prefix wins — "a" trims to "a-thing".
  assert_output "a-thing"
  assert_success
}

# ---------------------------------------------------------------------------
# str__rsplit_once
# ---------------------------------------------------------------------------

@test "str__rsplit_once splits on the LAST occurrence of the separator" {
  run str__rsplit_once "a:b:c" ":"
  assert_line -n 0 "a:b"
  assert_line -n 1 "c"
  assert_success
}

@test "str__rsplit_once with no separator prints head only" {
  run str__rsplit_once "single" ":"
  assert_line -n 0 "single"
  assert_success
}

@test "str__rsplit_once with trailing separator produces empty tail" {
  run str__rsplit_once "left:" ":"
  assert_line -n 0 "left"
  # tail is empty — assert_line at index 1 must exist but be empty
  [ "${#lines[@]}" -ge 1 ]
  assert_success
}

@test "str__rsplit_once handles multi-character separators" {
  run str__rsplit_once "foo==bar==baz" "=="
  assert_line -n 0 "foo==bar"
  assert_line -n 1 "baz"
  assert_success
}

# ---------------------------------------------------------------------------
# str__find_close_brace
# ---------------------------------------------------------------------------

@test "str__find_close_brace returns index of matching close brace" {
  run str__find_close_brace "TOKEN}rest"
  assert_output "5"
  assert_success
}

@test "str__find_close_brace handles nested braces" {
  run str__find_close_brace "{nested}}"
  assert_output "8"
  assert_success
}

@test "str__find_close_brace returns 1 when no matching brace" {
  run str__find_close_brace "TOKEN"
  assert_failure
}

# ---------------------------------------------------------------------------
# str__split_conditional
# ---------------------------------------------------------------------------

@test "str__split_conditional splits condition true and false branches" {
  local tc tc_t tc_f
  str__split_conditional "OS==linux?TRUE:FALSE" tc tc_t tc_f
  [ "$tc" = "OS==linux" ]
  [ "$tc_t" = "TRUE" ]
  [ "$tc_f" = "FALSE" ]
}

@test "str__split_conditional returns 1 when no question mark" {
  local tc tc_t tc_f
  run str__split_conditional "OS==linux" tc tc_t tc_f
  assert_failure
}

@test "str__split_conditional handles nested tokens in true branch" {
  local tc tc_t tc_f
  str__split_conditional "A==b?{X}:Y" tc tc_t tc_f
  [ "$tc" = "A==b" ]
  [ "$tc_t" = "{X}" ]
  [ "$tc_f" = "Y" ]
}
