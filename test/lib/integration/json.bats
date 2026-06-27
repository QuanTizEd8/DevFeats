#!/usr/bin/env bats
# Integration tests for lib/json.sh — exercises real jq.
#
# json__query calls bootstrap__jq, which installs jq via ospkg if absent.
# All json function tests require a real jq binary and belong here.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  reload_lib
}

@test "json__root_scalar_stdin prints string and numeric keys from stdin JSON" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"tag_name\":\"v1\",\"id\":42}" | json__root_scalar_stdin tag_name' _ "${LIB_ROOT}"
  assert_output "v1"
  assert_success
  run bash -c '. "$1/__init__.bash" && printf %s "{\"tag_name\":\"v1\",\"id\":42}" | json__root_scalar_stdin id' _ "${LIB_ROOT}"
  assert_output "42"
  assert_success
}

@test "json__root_scalar_stdin fails when key is missing" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"name\":\"x\"}" | json__root_scalar_stdin tag_name' _ "${LIB_ROOT}"
  assert_failure
}

@test "json__array_field_lines_stdin prints one line per array element field" {
  run bash -c '. "$1/__init__.bash" && printf %s "[{\"tag_name\":\"a\"},{\"tag_name\":\"b\"}]" | json__array_field_lines_stdin tag_name' _ "${LIB_ROOT}"
  assert_output "a
b"
  assert_success
}

@test "json__root_scalar_stdin reuses cached parser across calls in one shell" {
  run bash -ec '. "$1/__init__.bash"; printf %s "{\"a\":1}" | json__root_scalar_stdin a; printf %s "{\"b\":2}" | json__root_scalar_stdin b' _ "${LIB_ROOT}"
  assert_output $'1\n2'
  assert_success
}

@test "json__object_array_field_lines_stdin plucks field from nested array" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"assets\":[{\"browser_download_url\":\"https://a.tgz\"},{\"browser_download_url\":\"https://b.zip\"}]}" | json__object_array_field_lines_stdin assets browser_download_url' _ "${LIB_ROOT}"
  assert_output "https://a.tgz
https://b.zip"
  assert_success
}

@test "json__object_map_string_values_stdin prints string values under envs" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"envs\":{\"base\":\"/opt/conda\",\"myenv\":\"/opt/conda/envs/my\"}}" | json__object_map_string_values_stdin envs' _ "${LIB_ROOT}"
  assert_output "/opt/conda
/opt/conda/envs/my"
  assert_success
}

@test "json__object_key_string_lines_stdin handles array or object of strings" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"items\":[\"/a\",\"/b\"]}" | json__object_key_string_lines_stdin items' _ "${LIB_ROOT}"
  assert_output "/a
/b"
  assert_success
  run bash -c '. "$1/__init__.bash" && printf %s "{\"items\":{\"x\":\"/a\",\"y\":\"/b\"}}" | json__object_key_string_lines_stdin items' _ "${LIB_ROOT}"
  assert_output "/a
/b"
  assert_success
}

@test "json__object_keys_stdin lists top-level keys" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"z\":1,\"a\":2}" | json__object_keys_stdin' _ "${LIB_ROOT}"
  assert_output "a
z"
  assert_success
}

@test "json__value_stdin prints compact sub-value" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"x\":[\"p\"]}" | json__value_stdin .x' _ "${LIB_ROOT}"
  assert_output '["p"]'
  assert_success
}

@test "json__coerce_scalar_stdin maps boolean to string" {
  run bash -c '. "$1/__init__.bash" && printf %s "true" | json__coerce_scalar_stdin' _ "${LIB_ROOT}"
  assert_output "true"
  assert_success
}

@test "json__coerce_scalar_stdin fails on object" {
  run bash -c '. "$1/__init__.bash" && printf %s "{}" | json__coerce_scalar_stdin' _ "${LIB_ROOT}"
  assert_failure
}

@test "json__query passes arguments through to jq" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"x\":42}" | json__query -r ".x"' _ "${LIB_ROOT}"
  assert_output "42"
  assert_success
}

@test "json__query forwards multi-arg jq filter" {
  run bash -c '. "$1/__init__.bash" && printf %s "[1,2,3]" | json__query -r ".[]"' _ "${LIB_ROOT}"
  assert_output "$(printf '1\n2\n3')"
  assert_success
}
