#!/usr/bin/env bats
# Integration tests for lib/github.sh — exercises real GitHub API calls.
#
# All github.sh functions are tested in unit tests only with canned JSON
# responses from stubbed net__fetch_url_stdout. These tests confirm the
# real API interaction works end-to-end.
#
# Uses jqlang/jq as a stable test subject with a predictable release history.
# jq uses jq-N.N.N tag format (not v*).
# GITHUB_TOKEN is passed to integration containers and provides 5000 req/hr.

bats_require_minimum_version 1.5.0

_GITHUB_TEST_REPO="jqlang/jq"

setup() {
  load '../helpers/common'
  reload_lib
}

@test "github__latest_tag: returns a tag for a known repo" {
  run github__latest_tag "$_GITHUB_TEST_REPO"
  assert_success
  [[ -n "$output" ]]
}

@test "github__release_tags: returns a non-empty list of tags" {
  run github__release_tags "$_GITHUB_TEST_REPO"
  assert_success
  [[ -n "$output" ]]
}

@test "github__fetch_release_json: returns JSON with tag_name field" {
  local _json
  _json="$(github__fetch_release_json "$_GITHUB_TEST_REPO")"
  run json__query -r '.tag_name' <<< "$_json"
  assert_success
  [[ -n "$output" ]]
}

@test "github__release_json_tag_name: extracts tag from release JSON file" {
  local _file="${BATS_TEST_TMPDIR}/release.json"
  github__fetch_release_json "$_GITHUB_TEST_REPO" > "$_file"
  run github__release_json_tag_name "$_file"
  assert_success
  [[ -n "$output" ]]
}

@test "github__resolve_version: resolves latest to a tag" {
  run github__resolve_version "$_GITHUB_TEST_REPO" "latest"
  assert_success
  [[ -n "$output" ]]
}

@test "github__release_asset_urls: returns non-empty URL list for default (latest) release" {
  # Call without --tag to use the latest release endpoint directly.
  run github__release_asset_urls "$_GITHUB_TEST_REPO"
  assert_success
  [[ -n "$output" ]]
  grep -q 'https://' <<< "$output"
}
