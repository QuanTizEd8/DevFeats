#!/usr/bin/env bats
# Unit tests for lib/json.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/json_assert'
  load 'helpers/stubs'
  reload_lib json.sh
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

@test "json__nodejs_index_version_stdin lts-first head major exact" {
  _fixture='[{"version":"v1.0.0","lts":false},{"version":"v22.1.0","lts":true},{"version":"v22.0.0","lts":true}]'
  run bash -c '. "$1/__init__.bash" && printf %s "$2" | json__nodejs_index_version_stdin lts-first' _ "${LIB_ROOT}" "$_fixture"
  assert_output "v22.1.0"
  assert_success
  run bash -c '. "$1/__init__.bash" && printf %s "$2" | json__nodejs_index_version_stdin head' _ "${LIB_ROOT}" "$_fixture"
  assert_output "v1.0.0"
  assert_success
  run bash -c '. "$1/__init__.bash" && printf %s "$2" | json__nodejs_index_version_stdin major 22' _ "${LIB_ROOT}" "$_fixture"
  assert_output "v22.1.0"
  assert_success
  run bash -c '. "$1/__init__.bash" && printf %s "$2" | json__nodejs_index_version_stdin exact v22.0.0' _ "${LIB_ROOT}" "$_fixture"
  assert_output "v22.0.0"
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

# ---------------------------------------------------------------------------
# json__query — jq passthrough
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# bootstrap__jq — auto-installs jq when absent
# ---------------------------------------------------------------------------

@test "bootstrap__jq: succeeds when jq is already available" {
  # Integration-only: this test validates pass-through to a real jq binary.
  if [[ "${SYSSET_RUN_INTEGRATION_DEPS:-0}" != "1" ]]; then
    skip "set SYSSET_RUN_INTEGRATION_DEPS=1 to run real-jq integration checks"
  fi
  create_pass_through_bin "jq"
  prepend_fake_bin_path
  command -v jq > /dev/null 2>&1 || skip "real jq is not available on this host"
  run bootstrap__jq
  assert_success
}

@test "bootstrap__jq: calls ospkg__install_tracked when jq absent" {
  reload_lib json.sh

  local _install_log="${BATS_TEST_TMPDIR}/install.log"
  local _fake_jq="${BATS_TEST_TMPDIR}/bin/jq"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  ospkg__update() { return 0; }
  export -f ospkg__update

  # Stub installs a fake jq so the post-install command -v check passes.
  ospkg__install_tracked() {
    echo "install_tracked $*" >> "$_install_log"
    printf '#!/bin/sh\nexit 0\n' > "$_fake_jq"
    chmod +x "$_fake_jq"
    return 0
  }
  export -f ospkg__install_tracked

  begin_path_isolation
  run bootstrap__jq
  local _rc=$?
  end_path_isolation

  [[ $_rc -eq 0 ]]
  assert_file_exists "$_install_log"
  grep -q "jq" "$_install_log"
}
