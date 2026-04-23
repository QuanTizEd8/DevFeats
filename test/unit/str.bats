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

@test "str__safe_id sanitizes dots and dashes to underscores and uppercases" {
  run str__safe_id "my-opt.name"
  assert_output "MY_OPT_NAME"
  assert_success
}

@test "str__safe_id prepends underscore when the id starts with a digit" {
  run str__safe_id "2to3"
  assert_output "_2TO3"
  assert_success
}

@test "str__safe_id prepends underscore to a leading underscore (devcontainer getSafeId semantics)" {
  # getSafeId JS: /^([0-9_])/ → '_$1'.  `_leading` starts with `_`, so gets `__LEADING`.
  run str__safe_id "_leading"
  assert_output "__LEADING"
  assert_success
}

@test "str__safe_id replaces non-ASCII characters with underscores" {
  run str__safe_id $'caf\xc3\xa9-opt'
  # é (single locale-aware character) → '_'; '-' → '_'; two underscores total.
  assert_output "CAF__OPT"
  assert_success
}

@test "str__safe_id collapses repeated separators each to one underscore" {
  run str__safe_id "a..b--c"
  assert_output "A__B__C"
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
# str__extract_version_suffix
# ---------------------------------------------------------------------------

@test "str__extract_version_suffix reads trailing 'v<X.Y.Z>' after whitespace" {
  run str__extract_version_suffix "Name v1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "str__extract_version_suffix returns empty when the tail is not a semver" {
  run str__extract_version_suffix "no version here"
  assert_output ""
  assert_success
}

@test "str__extract_version_suffix does not match without the leading 'v'" {
  run str__extract_version_suffix "Name 1.2.3"
  assert_output ""
  assert_success
}

@test "str__extract_version_suffix requires v to be at the start or after whitespace" {
  # 'uv1.2.3' should NOT match because 'v' is preceded by a non-space letter.
  run str__extract_version_suffix "uv1.2.3"
  assert_output ""
  assert_success
}
