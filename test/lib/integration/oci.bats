#!/usr/bin/env bats
# Integration tests for lib/oci.sh — exercises real ORAS and OCI registry.
#
# All oci.sh functions are tested in unit tests only with a stubbed oras
# function. These tests confirm the real ORAS binary and OCI registry
# interaction work end-to-end.
#
# Uses ghcr.io/quantized8/devfeats/install-jq as a stable, published test
# subject. GITHUB_TOKEN is available in integration containers for auth.

bats_require_minimum_version 1.5.0

_OCI_TEST_REF="ghcr.io/quantized8/devfeats/install-jq"

setup() {
  load '../helpers/common'
  reload_lib
}

@test "oci__ensure_oras: installs oras if absent and makes it available" {
  run oci__ensure_oras
  assert_success
  command -v oras > /dev/null 2>&1 || {
    # oras may be installed to a non-PATH location; check via oras itself
    oras version > /dev/null 2>&1
  }
}

@test "oci__list_tags: returns non-empty tag list for a known feature" {
  run oci__list_tags "$_OCI_TEST_REF"
  assert_success
  [[ -n "$output" ]]
}

@test "oci__resolve_version: resolves stable to a version tag" {
  run oci__resolve_version "$_OCI_TEST_REF" "stable"
  assert_success
  [[ "$output" == [0-9]* || "$output" == v[0-9]* ]]
}

@test "oci__pull_feature_tgz: pulls and validates a feature tgz" {
  local _tag _dest="${BATS_TEST_TMPDIR}/feat.tgz"
  _tag="$(oci__resolve_version "$_OCI_TEST_REF" "stable")"
  run oci__pull_feature_tgz "${_OCI_TEST_REF}:${_tag}" "$_dest"
  assert_success
  # Validate that the pulled file is a real tar archive containing install.sh.
  tar -tzf "$_dest" | grep -q 'install.sh'
}
