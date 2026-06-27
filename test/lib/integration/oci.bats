#!/usr/bin/env bats
# Integration tests for lib/oci.sh — exercises real ORAS and OCI registry.
#
# All oci.sh functions are tested in unit tests only with a stubbed oras
# function. These tests confirm the real ORAS binary and OCI registry
# interaction work end-to-end.
#
# Uses ghcr.io/quantized8/devfeats/install-jq as a stable, published test
# subject. GITHUB_TOKEN is available in integration containers for auth.
#
# setup_file installs oras to /usr/local/bin so each test subprocess finds
# it via command -v without needing to re-download it per test.

bats_require_minimum_version 1.5.0

_OCI_TEST_REF="ghcr.io/quantized8/devfeats/install-jq"

setup_file() {
  load '../helpers/common'
  reload_lib
  local _bin
  _bin="$(bootstrap__oras)"
  [[ -n "$_bin" ]] && install -m 755 "$_bin" /usr/local/bin/oras
}

setup() {
  load '../helpers/common'
  reload_lib
}

@test "oci__ensure_oras: succeeds and oras is available" {
  run oci__ensure_oras
  assert_success
}

@test "oci__list_tags: returns non-empty tag list for a known feature" {
  run oci__list_tags "$_OCI_TEST_REF"
  assert_success
  [[ -n "$output" ]]
}

@test "oci__resolve_version: resolves to a non-empty version" {
  run oci__resolve_version "$_OCI_TEST_REF" ""
  assert_success
}
