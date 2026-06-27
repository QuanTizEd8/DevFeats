#!/usr/bin/env bats
# Integration tests for lib/github.sh — exercises real GitHub API calls.
#
# All github.sh functions are tested in unit tests only with canned JSON
# responses from stubbed net__fetch_url_stdout. These tests confirm the
# real API interaction works end-to-end.
#
# Uses jqlang/jq as a stable test subject with a predictable release history.
# GITHUB_TOKEN is passed to integration containers and provides 5000 req/hr.

bats_require_minimum_version 1.5.0

_GITHUB_TEST_REPO="jqlang/jq"

setup() {
  load '../helpers/common'
  reload_lib
}

@test "github__latest_tag: returns a semver tag for a known repo" {
  run github__latest_tag "$_GITHUB_TEST_REPO"
  assert_success
  [[ "$output" == v[0-9]* ]]
}

@test "github__release_tags: returns a non-empty list of tags" {
  run github__release_tags "$_GITHUB_TEST_REPO"
  assert_success
  [[ -n "$output" ]]
  # At least one line starts with v
  grep -q '^v' <<< "$output"
}

@test "github__fetch_release_json: returns JSON with tag_name field" {
  local _json
  _json="$(github__fetch_release_json "$_GITHUB_TEST_REPO")"
  run json__query -r '.tag_name' <<< "$_json"
  assert_success
  [[ "$output" == v[0-9]* ]]
}

@test "github__release_json_tag_name: extracts tag from release JSON" {
  local _json
  _json="$(github__fetch_release_json "$_GITHUB_TEST_REPO")"
  run github__release_json_tag_name "$_json"
  assert_success
  [[ "$output" == v[0-9]* ]]
}

@test "github__resolve_version: resolves stable to a tag" {
  run github__resolve_version "$_GITHUB_TEST_REPO" "stable"
  assert_success
  [[ "$output" == v[0-9]* ]]
}

@test "github__release_asset_urls: returns non-empty URL list for stable tag" {
  local _tag
  _tag="$(github__resolve_version "$_GITHUB_TEST_REPO" "stable")"
  run github__release_asset_urls "$_GITHUB_TEST_REPO" "$_tag"
  assert_success
  [[ -n "$output" ]]
  grep -q 'https://' <<< "$output"
}
