#!/usr/bin/env bash
# shellcheck shell=bash
# helpers/json_assert.bash — lightweight JSON-output assertions without jq.
#
# This helper intentionally does not parse JSON; it provides deterministic
# string-based checks for tests that already control expected formatting.

# assert_json_compact_equals <actual> <expected>
# Succeeds when both inputs are identical after trimming trailing newlines.
assert_json_compact_equals() {
  local _actual="${1-}"
  local _expected="${2-}"
  _actual="${_actual%"${_actual##*[!$'\n']}"}"
  _expected="${_expected%"${_expected##*[!$'\n']}"}"
  [ "$_actual" = "$_expected" ]
}
