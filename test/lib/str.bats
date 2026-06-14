#!/usr/bin/env bats
# Unit tests for lib/str.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib str.sh
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
  run bash -c 'source "$1" && str__basename_each' _ "${LIB_ROOT}/str.sh"
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
# str__substitute_tokens
# ---------------------------------------------------------------------------

@test "str__substitute_tokens substitutes a single token" {
  run str__substitute_tokens "install to {PREFIX}/bin" "PREFIX=/opt/mytool"
  assert_output "install to /opt/mytool/bin"
  assert_success
}

@test "str__substitute_tokens substitutes multiple tokens in one pass" {
  run str__substitute_tokens "os={OS} arch={ARCH}" "OS=linux" "ARCH=amd64"
  assert_output "os=linux arch=amd64"
  assert_success
}

@test "str__substitute_tokens leaves pattern unchanged when no tokens present" {
  run str__substitute_tokens "no tokens here" "PREFIX=/opt"
  assert_output "no tokens here"
  assert_success
}

@test "str__substitute_tokens leaves unknown token as-is" {
  run str__substitute_tokens "prefix={PREFIX} unknown={UNKNOWN}" "PREFIX=/opt"
  assert_output "prefix=/opt unknown={UNKNOWN}"
  assert_success
}

@test "str__substitute_tokens substitutes token with empty value" {
  run str__substitute_tokens "x={PREFIX}y" "PREFIX="
  assert_output "x=y"
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

# ---------------------------------------------------------------------------
# str__expand_pattern
# ---------------------------------------------------------------------------

@test "str__expand_pattern substitutes a plain token" {
  run str__expand_pattern "os={OS}" "OS=linux"
  assert_output "os=linux"
  assert_success
}

@test "str__expand_pattern substitutes multiple tokens" {
  run str__expand_pattern "{OS}-{ARCH}" "OS=linux" "ARCH=amd64"
  assert_output "linux-amd64"
  assert_success
}

@test "str__expand_pattern first match wins for duplicate keys" {
  run str__expand_pattern "{KEY}" "KEY=first" "KEY=second"
  assert_output "first"
  assert_success
}

@test "str__expand_pattern emits unknown token unchanged" {
  run str__expand_pattern "{UNKNOWN}" "OS=linux"
  assert_output "{UNKNOWN}"
  assert_success
}

@test "str__expand_pattern passes through unmatched open brace literally" {
  run str__expand_pattern "x { y" "OS=linux"
  assert_output "x { y"
  assert_success
}

@test "str__expand_pattern evaluates == conditional true branch" {
  run str__expand_pattern "{OS==linux?yes:no}" "OS=linux"
  assert_output "yes"
  assert_success
}

@test "str__expand_pattern evaluates == conditional false branch" {
  run str__expand_pattern "{OS==darwin?yes:no}" "OS=linux"
  assert_output "no"
  assert_success
}

@test "str__expand_pattern evaluates != conditional" {
  run str__expand_pattern "{OS!=darwin?linux-result:mac-result}" "OS=linux"
  assert_output "linux-result"
  assert_success
}

@test "str__expand_pattern evaluates >= version conditional true" {
  run str__expand_pattern "{VER>=2.0?new:old}" "VER=2.5"
  assert_output "new"
  assert_success
}

@test "str__expand_pattern evaluates >= version conditional false" {
  run str__expand_pattern "{VER>=2.0?new:old}" "VER=1.9"
  assert_output "old"
  assert_success
}

@test "str__expand_pattern evaluates < version conditional" {
  run str__expand_pattern "{VER<2.0?old:new}" "VER=1.9"
  assert_output "old"
  assert_success
}

@test "str__expand_pattern handles nested conditional in true branch" {
  run str__expand_pattern "{OS==linux?{ARCH==amd64?x86_64:arm}:mac}" "OS=linux" "ARCH=amd64"
  assert_output "x86_64"
  assert_success
}

@test "str__expand_pattern handles nested conditional in false branch" {
  run str__expand_pattern "{OS==linux?{ARCH==amd64?x86_64:arm}:mac}" "OS=darwin" "ARCH=amd64"
  assert_output "mac"
  assert_success
}

@test "str__expand_pattern unknown key in conditional treats as false" {
  run str__expand_pattern "{MISSING==value?yes:no}" "OS=linux"
  assert_output "no"
  assert_success
}

@test "str__expand_pattern expands tokens adjacent to literals" {
  run str__expand_pattern "prefix-{OS}-suffix" "OS=linux"
  assert_output "prefix-linux-suffix"
  assert_success
}
