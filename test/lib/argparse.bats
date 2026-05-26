#!/usr/bin/env bats
# Unit tests for lib/argparse.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# argparse__validate_bool
# ---------------------------------------------------------------------------

@test "argparse__validate_bool: accepts true" {
  export MY_VAR=true
  run argparse__validate_bool MY_VAR
  assert_success
}

@test "argparse__validate_bool: accepts false" {
  export MY_VAR=false
  run argparse__validate_bool MY_VAR
  assert_success
}

@test "argparse__validate_bool: rejects other values" {
  export MY_VAR=yes
  run --separate-stderr argparse__validate_bool MY_VAR
  assert_failure
  [[ "${stderr}" =~ "MY_VAR" ]]
  [[ "${stderr}" =~ "expected: true, false" ]]
}

@test "argparse__validate_bool: rejects empty string" {
  export MY_VAR=""
  run argparse__validate_bool MY_VAR
  assert_failure
}

# ---------------------------------------------------------------------------
# argparse__validate_enum
# ---------------------------------------------------------------------------

@test "argparse__validate_enum: accepts a valid value" {
  export MY_VAR=beta
  run argparse__validate_enum MY_VAR alpha beta gamma
  assert_success
}

@test "argparse__validate_enum: accepts first value" {
  export MY_VAR=alpha
  run argparse__validate_enum MY_VAR alpha beta gamma
  assert_success
}

@test "argparse__validate_enum: rejects an invalid value" {
  export MY_VAR=delta
  run --separate-stderr argparse__validate_enum MY_VAR alpha beta gamma
  assert_failure
  [[ "${stderr}" =~ "MY_VAR" ]]
  [[ "${stderr}" =~ "delta" ]]
  [[ "${stderr}" =~ "alpha" ]]
}

@test "argparse__validate_enum: includes all valid values in error" {
  export MY_VAR=bad
  run --separate-stderr argparse__validate_enum MY_VAR x y z
  assert_failure
  [[ "${stderr}" =~ "x" ]]
  [[ "${stderr}" =~ "y" ]]
  [[ "${stderr}" =~ "z" ]]
}

@test "argparse__validate_enum: accepts empty string as valid value" {
  export MY_VAR=""
  run argparse__validate_enum MY_VAR "" other
  assert_success
}

# ---------------------------------------------------------------------------
# argparse__validate_enum_array
# ---------------------------------------------------------------------------

@test "argparse__validate_enum_array: accepts all valid elements" {
  declare -a MY_ARR=(alpha gamma)
  export MY_ARR
  run argparse__validate_enum_array MY_ARR alpha beta gamma
  assert_success
}

@test "argparse__validate_enum_array: accepts empty array" {
  declare -a MY_ARR=()
  export MY_ARR
  run argparse__validate_enum_array MY_ARR alpha beta
  assert_success
}

@test "argparse__validate_enum_array: rejects invalid element" {
  declare -a MY_ARR=(alpha bad)
  export MY_ARR
  run --separate-stderr argparse__validate_enum_array MY_ARR alpha beta gamma
  assert_failure
  [[ "${stderr}" =~ "bad" ]]
  [[ "${stderr}" =~ "MY_ARR" ]]
}

@test "argparse__validate_enum_array: reports first invalid element" {
  declare -a MY_ARR=(beta nope alpha)
  export MY_ARR
  run --separate-stderr argparse__validate_enum_array MY_ARR alpha beta
  assert_failure
  [[ "${stderr}" =~ "nope" ]]
}

# ---------------------------------------------------------------------------
# argparse__validate_integer
# ---------------------------------------------------------------------------

@test "argparse__validate_integer: accepts positive integer" {
  export MY_VAR=42
  run argparse__validate_integer MY_VAR
  assert_success
}

@test "argparse__validate_integer: accepts zero" {
  export MY_VAR=0
  run argparse__validate_integer MY_VAR
  assert_success
}

@test "argparse__validate_integer: accepts negative integer" {
  export MY_VAR=-5
  run argparse__validate_integer MY_VAR
  assert_success
}

@test "argparse__validate_integer: rejects non-integer string" {
  export MY_VAR=abc
  run --separate-stderr argparse__validate_integer MY_VAR
  assert_failure
  [[ "${stderr}" =~ "MY_VAR" ]]
}

@test "argparse__validate_integer: rejects float" {
  export MY_VAR=3.14
  run argparse__validate_integer MY_VAR
  assert_failure
}

@test "argparse__validate_integer: rejects empty string" {
  export MY_VAR=""
  run argparse__validate_integer MY_VAR
  assert_failure
}

# ---------------------------------------------------------------------------
# argparse__validate_integer_min
# ---------------------------------------------------------------------------

@test "argparse__validate_integer_min: accepts value equal to min" {
  export MY_VAR=5
  run argparse__validate_integer_min MY_VAR 5
  assert_success
}

@test "argparse__validate_integer_min: accepts value above min" {
  export MY_VAR=10
  run argparse__validate_integer_min MY_VAR 5
  assert_success
}

@test "argparse__validate_integer_min: rejects value below min" {
  export MY_VAR=4
  run --separate-stderr argparse__validate_integer_min MY_VAR 5
  assert_failure
  [[ "${stderr}" =~ "MY_VAR" ]]
  [[ "${stderr}" =~ ">= 5" ]]
}

# ---------------------------------------------------------------------------
# argparse__validate_integer_max
# ---------------------------------------------------------------------------

@test "argparse__validate_integer_max: accepts value equal to max" {
  export MY_VAR=10
  run argparse__validate_integer_max MY_VAR 10
  assert_success
}

@test "argparse__validate_integer_max: accepts value below max" {
  export MY_VAR=3
  run argparse__validate_integer_max MY_VAR 10
  assert_success
}

@test "argparse__validate_integer_max: rejects value above max" {
  export MY_VAR=11
  run --separate-stderr argparse__validate_integer_max MY_VAR 10
  assert_failure
  [[ "${stderr}" =~ "MY_VAR" ]]
  [[ "${stderr}" =~ "<= 10" ]]
}

# ---------------------------------------------------------------------------
# argparse__validate_path
# ---------------------------------------------------------------------------

@test "argparse__validate_path: skips empty value" {
  export MY_VAR=""
  run argparse__validate_path MY_VAR -d
  assert_success
}

@test "argparse__validate_path: accepts existing directory for -d" {
  export MY_VAR="/tmp"
  run argparse__validate_path MY_VAR -d
  assert_success
}

@test "argparse__validate_path: rejects non-directory for -d" {
  export MY_VAR="/no/such/directory"
  run --separate-stderr argparse__validate_path MY_VAR -d
  assert_failure
  [[ "${stderr}" =~ "MY_VAR" ]]
  [[ "${stderr}" =~ "-d" ]]
}

@test "argparse__validate_path: accepts existing file for -f" {
  local _tmpfile
  _tmpfile="$(mktemp)"
  export MY_VAR="${_tmpfile}"
  run argparse__validate_path MY_VAR -f
  assert_success
  rm -f "${_tmpfile}"
}

@test "argparse__validate_path: accepts existing path for -e" {
  export MY_VAR="/tmp"
  run argparse__validate_path MY_VAR -e
  assert_success
}

@test "argparse__validate_path: rejects missing path for -e" {
  export MY_VAR="/no/such/path"
  run argparse__validate_path MY_VAR -e
  assert_failure
}

# ---------------------------------------------------------------------------
# argparse__default
# ---------------------------------------------------------------------------

@test "argparse__default: sets variable when unset" {
  unset MY_VAR
  argparse__default MY_VAR "hello"
  assert [ "${MY_VAR}" = "hello" ]
}

@test "argparse__default: leaves variable unchanged when already set" {
  MY_VAR="existing"
  argparse__default MY_VAR "default"
  assert [ "${MY_VAR}" = "existing" ]
}

@test "argparse__default: sets variable to empty string when default is empty" {
  unset MY_VAR
  argparse__default MY_VAR ""
  assert [ "${MY_VAR+set}" = "set" ]
  assert [ "${MY_VAR}" = "" ]
}

@test "argparse__default: treats variable set to empty as already set" {
  MY_VAR=""
  argparse__default MY_VAR "default"
  assert [ "${MY_VAR}" = "" ]
}

# ---------------------------------------------------------------------------
# argparse__default_array
# ---------------------------------------------------------------------------

@test "argparse__default_array: sets undeclared array to empty" {
  unset MY_ARR
  argparse__default_array MY_ARR
  declare -p MY_ARR &>/dev/null
  assert [ "${#MY_ARR[@]}" -eq 0 ]
}

@test "argparse__default_array: leaves already-declared array unchanged" {
  declare -a MY_ARR=(a b c)
  argparse__default_array MY_ARR
  assert [ "${#MY_ARR[@]}" -eq 3 ]
  assert [ "${MY_ARR[0]}" = "a" ]
}

@test "argparse__default_array: leaves empty declared array unchanged" {
  declare -a MY_ARR=()
  argparse__default_array MY_ARR
  assert [ "${#MY_ARR[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# argparse__default_array_value
# ---------------------------------------------------------------------------

@test "argparse__default_array_value: sets undeclared array from multi-line value" {
  unset MY_ARR
  argparse__default_array_value MY_ARR $'line1\nline2\nline3'
  assert [ "${#MY_ARR[@]}" -eq 3 ]
  assert [ "${MY_ARR[0]}" = "line1" ]
  assert [ "${MY_ARR[1]}" = "line2" ]
  assert [ "${MY_ARR[2]}" = "line3" ]
}

@test "argparse__default_array_value: leaves already-declared array unchanged" {
  declare -a MY_ARR=(existing)
  argparse__default_array_value MY_ARR $'other\nvalue'
  assert [ "${#MY_ARR[@]}" -eq 1 ]
  assert [ "${MY_ARR[0]}" = "existing" ]
}

@test "argparse__default_array_value: skips blank lines in value" {
  unset MY_ARR
  argparse__default_array_value MY_ARR $'a\n\nb\n'
  assert [ "${#MY_ARR[@]}" -eq 2 ]
  assert [ "${MY_ARR[0]}" = "a" ]
  assert [ "${MY_ARR[1]}" = "b" ]
}
