#!/usr/bin/env bats
# Unit tests for lib/json.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib json.sh
}

@test "json__root_scalar_stdin prints string and numeric keys from stdin JSON" {
  run sh -c '. "$1" && printf %s "{\"tag_name\":\"v1\",\"id\":42}" | json__root_scalar_stdin tag_name' _ "${LIB_ROOT}/json.sh"
  assert_output "v1"
  assert_success
  run sh -c '. "$1" && printf %s "{\"tag_name\":\"v1\",\"id\":42}" | json__root_scalar_stdin id' _ "${LIB_ROOT}/json.sh"
  assert_output "42"
  assert_success
}

@test "json__root_scalar_stdin fails when key is missing" {
  run sh -c '. "$1" && printf %s "{\"name\":\"x\"}" | json__root_scalar_stdin tag_name' _ "${LIB_ROOT}/json.sh"
  assert_failure
}

@test "json__array_field_lines_stdin prints one line per array element field" {
  run sh -c '. "$1" && printf %s "[{\"tag_name\":\"a\"},{\"tag_name\":\"b\"}]" | json__array_field_lines_stdin tag_name' _ "${LIB_ROOT}/json.sh"
  assert_output "a
b"
  assert_success
}

@test "json__root_scalar_stdin reuses cached parser across calls in one shell" {
  run bash -ec '. "$1"; printf %s "{\"a\":1}" | json__root_scalar_stdin a; printf %s "{\"b\":2}" | json__root_scalar_stdin b' _ "${LIB_ROOT}/json.sh"
  assert_output $'1\n2'
  assert_success
}

@test "json__object_array_field_lines_stdin plucks field from nested array" {
  run sh -c '. "$1" && printf %s "{\"assets\":[{\"browser_download_url\":\"https://a.tgz\"},{\"browser_download_url\":\"https://b.zip\"}]}" | json__object_array_field_lines_stdin assets browser_download_url' _ "${LIB_ROOT}/json.sh"
  assert_output "https://a.tgz
https://b.zip"
  assert_success
}

@test "json__object_map_string_values_stdin prints string values under envs" {
  run sh -c '. "$1" && printf %s "{\"envs\":{\"base\":\"/opt/conda\",\"myenv\":\"/opt/conda/envs/my\"}}" | json__object_map_string_values_stdin envs' _ "${LIB_ROOT}/json.sh"
  assert_output "/opt/conda
/opt/conda/envs/my"
  assert_success
}

@test "json__object_key_string_lines_stdin handles array or object of strings" {
  run sh -c '. "$1" && printf %s "{\"items\":[\"/a\",\"/b\"]}" | json__object_key_string_lines_stdin items' _ "${LIB_ROOT}/json.sh"
  assert_output "/a
/b"
  assert_success
  run sh -c '. "$1" && printf %s "{\"items\":{\"x\":\"/a\",\"y\":\"/b\"}}" | json__object_key_string_lines_stdin items' _ "${LIB_ROOT}/json.sh"
  assert_output "/a
/b"
  assert_success
}

@test "json__nodejs_index_version_stdin lts-first head major exact" {
  _fixture='[{"version":"v1.0.0","lts":false},{"version":"v22.1.0","lts":true},{"version":"v22.0.0","lts":true}]'
  run sh -c '. "$1" && printf %s "$2" | json__nodejs_index_version_stdin lts-first' _ "${LIB_ROOT}/json.sh" "$_fixture"
  assert_output "v22.1.0"
  assert_success
  run sh -c '. "$1" && printf %s "$2" | json__nodejs_index_version_stdin head' _ "${LIB_ROOT}/json.sh" "$_fixture"
  assert_output "v1.0.0"
  assert_success
  run sh -c '. "$1" && printf %s "$2" | json__nodejs_index_version_stdin major 22' _ "${LIB_ROOT}/json.sh" "$_fixture"
  assert_output "v22.1.0"
  assert_success
  run sh -c '. "$1" && printf %s "$2" | json__nodejs_index_version_stdin exact v22.0.0' _ "${LIB_ROOT}/json.sh" "$_fixture"
  assert_output "v22.0.0"
  assert_success
}

# ---------------------------------------------------------------------------
# JSONC / jq helpers (bash-sourced; jsonc.py + jq)
# ---------------------------------------------------------------------------

@test "json__strip_jsonc_stdin accepts comments and trailing commas" {
  run bash -c '. "$1" && printf %s "{\"a\":1,} /*c*/" | json__strip_jsonc_stdin | jq -c .' _ "${LIB_ROOT}/json.sh"
  assert_output '{"a":1}'
  assert_success
}

@test "json__object_keys_stdin lists top-level keys" {
  run bash -c '. "$1" && printf %s "{\"z\":1,\"a\":2}" | json__object_keys_stdin' _ "${LIB_ROOT}/json.sh"
  assert_output "a
z"
  assert_success
}

@test "json__value_stdin prints compact sub-value" {
  run bash -c '. "$1" && printf %s "{\"x\":[\"p\"]}" | json__value_stdin .x' _ "${LIB_ROOT}/json.sh"
  assert_output '["p"]'
  assert_success
}

@test "json__coerce_scalar_stdin maps boolean to string" {
  run bash -c '. "$1" && printf %s "true" | json__coerce_scalar_stdin' _ "${LIB_ROOT}/json.sh"
  assert_output "true"
  assert_success
}

@test "json__coerce_scalar_stdin fails on object" {
  run bash -c '. "$1" && printf %s "{}" | json__coerce_scalar_stdin' _ "${LIB_ROOT}/json.sh"
  assert_failure
}

@test "json__detect_duplicate_keys_stdin fails on duplicate keys" {
  run bash -c '. "$1" && printf %s "{\"a\":1,\"a\":2}" | json__detect_duplicate_keys_stdin' _ "${LIB_ROOT}/json.sh"
  assert_failure
}

@test "json__detect_duplicate_keys_stdin passes for unique keys" {
  run bash -c '. "$1" && printf %s "{\"a\":1}" | json__detect_duplicate_keys_stdin' _ "${LIB_ROOT}/json.sh"
  assert_success
}

# ---------------------------------------------------------------------------
# _json__ensure_parse_tool — tool detection and caching
# ---------------------------------------------------------------------------

@test "_json__ensure_parse_tool: selects jq when available" {
  create_fake_bin "jq" ""
  prepend_fake_bin_path
  # Force a clean state before calling the private function.
  unset _JSON__ENSURE_PARSE_DONE _JSON__PARSE_TOOL
  # Source the library after clearing state.
  reload_lib json.sh

  _json__ensure_parse_tool
  [[ "${_JSON__PARSE_TOOL}" == "jq" ]]
}

@test "_json__ensure_parse_tool: result is cached on second call" {
  create_fake_bin "jq" ""
  prepend_fake_bin_path
  unset _JSON__ENSURE_PARSE_DONE _JSON__PARSE_TOOL
  reload_lib json.sh

  _json__ensure_parse_tool
  local _first="${_JSON__PARSE_TOOL}"
  # Remove jq from PATH — second call must use cached value.
  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/no_bin"
  _json__ensure_parse_tool
  local _second="${_JSON__PARSE_TOOL}"
  export PATH="$_saved"

  [[ "$_first" == "$_second" ]]
}

@test "_json__ensure_parse_tool: falls back to python when jq and yq absent" {
  unset _JSON__ENSURE_PARSE_DONE _JSON__PARSE_TOOL
  reload_lib json.sh
  # Restrict PATH to only python3.
  create_fake_bin "python3" ""
  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"

  _json__ensure_parse_tool
  local _result="${_JSON__PARSE_TOOL}"
  export PATH="$_saved"

  [[ "$_result" == "python" ]]
}

@test "_json__ensure_parse_tool: returns failure when no parser and ospkg unavailable" {
  unset _JSON__ENSURE_PARSE_DONE _JSON__PARSE_TOOL
  unset _OSPKG__LIB_LOADED
  reload_lib json.sh
  # Create empty bin dir BEFORE restricting PATH.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"  # empty bin dir — no tools

  run _json__ensure_parse_tool

  export PATH="$_saved"
  assert_failure
}

@test "_json__ensure_parse_tool: calls ospkg__install_tracked when ospkg is loaded and no parser found" {
  unset _JSON__ENSURE_PARSE_DONE _JSON__PARSE_TOOL
  reload_lib json.sh
  # Mark ospkg as loaded.
  export _OSPKG__LIB_LOADED=1

  local _install_log="${BATS_TEST_TMPDIR}/install.log"
  local _fake_jq="${BATS_TEST_TMPDIR}/bin/jq"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  ospkg__update() { return 0; }
  export -f ospkg__update

  # ospkg__install_tracked creates a fake jq so the second command -v jq check passes.
  ospkg__install_tracked() {
    echo "install_tracked $*" >> "$_install_log"
    printf '#!/bin/bash\nexit 0\n' > "$_fake_jq"
    chmod +x "$_fake_jq"
    return 0
  }
  export -f ospkg__install_tracked

  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"

  _json__ensure_parse_tool
  local _rc=$?
  export PATH="$_saved"

  [[ $_rc -eq 0 ]]
  assert_file_exists "$_install_log"
  grep -q "jq" "$_install_log"
  [[ "${_JSON__PARSE_TOOL}" == "jq" ]]
}
