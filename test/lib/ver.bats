#!/usr/bin/env bats
# Unit tests for lib/ver.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib ver.sh
}

# ---------------------------------------------------------------------------
# ver__semver_ge
# ---------------------------------------------------------------------------

@test "ver__semver_ge returns true for equal versions" {
  run ver__semver_ge "1.2.3" "1.2.3"
  assert_success
}

@test "ver__semver_ge returns true for greater version" {
  run ver__semver_ge "1.10.0" "1.9.0"
  assert_success
}

@test "ver__semver_ge returns false for lesser version" {
  run ver__semver_ge "1.2.0" "1.10.0"
  assert_failure
}

@test "ver__semver_ge strips leading v before comparing" {
  run ver__semver_ge "v2.0.0" "v1.9.9"
  assert_success
}

# ---------------------------------------------------------------------------
# ver__extract_version (default mode)
# ---------------------------------------------------------------------------

@test "ver__extract_version strips leading non-numeric prefix" {
  run ver__extract_version "jq-1.7.1"
  assert_output "1.7.1"
  assert_success
}

@test "ver__extract_version strips leading v" {
  run ver__extract_version "v3.7.0"
  assert_output "3.7.0"
  assert_success
}

@test "ver__extract_version extracts from prose output" {
  run ver__extract_version "gh version 2.46.0 (2024-01-15)"
  assert_output "2.46.0"
  assert_success
}

@test "ver__extract_version drops pre-release suffix by default" {
  run ver__extract_version "v1.2.3-rc1"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version drops inline alpha suffix by default" {
  run ver__extract_version "3.13.0a4"
  assert_output "3.13.0"
  assert_success
}

@test "ver__extract_version returns empty for non-version string" {
  run ver__extract_version "latest"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# ver__extract_version --keep-suffix
# ---------------------------------------------------------------------------

@test "ver__extract_version --keep-suffix preserves dash pre-release" {
  run ver__extract_version --keep-suffix "v1.2.3-rc1"
  assert_output "1.2.3-rc1"
  assert_success
}

@test "ver__extract_version --keep-suffix strips package-name prefix, keeps suffix" {
  run ver__extract_version --keep-suffix "jq-1.7.1-rc1"
  assert_output "1.7.1-rc1"
  assert_success
}

@test "ver__extract_version --keep-suffix captures inline alpha label" {
  run ver__extract_version --keep-suffix "3.13.0a4"
  assert_output "3.13.0a4"
  assert_success
}

@test "ver__extract_version --keep-suffix captures dot-separated suffix" {
  run ver__extract_version --keep-suffix "1.2.3.post1"
  assert_output "1.2.3.post1"
  assert_success
}

@test "ver__extract_version --keep-suffix returns unchanged bare version" {
  run ver__extract_version --keep-suffix "1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version --keep-suffix returns empty for non-version string" {
  run ver__extract_version --keep-suffix "latest"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# ver__extract_version --full-match
# ---------------------------------------------------------------------------

@test "ver__extract_version --full-match accepts bare semver" {
  run ver__extract_version --full-match "v1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version --full-match drops suffix when --keep-suffix absent" {
  run ver__extract_version --full-match "v1.2.3-rc1"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version --full-match rejects package-prefixed string" {
  run ver__extract_version --full-match "jq-1.7.1"
  assert_output ""
  assert_success
}

@test "ver__extract_version --full-match rejects non-numeric-prefixed OCI tag" {
  run ver__extract_version --full-match "arm64-1.0.0"
  assert_output ""
  assert_success
}

@test "ver__extract_version --full-match rejects non-version string" {
  run ver__extract_version --full-match "latest"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# ver__extract_version --full-match --keep-suffix
# ---------------------------------------------------------------------------

@test "ver__extract_version --full-match --keep-suffix preserves pre-release" {
  run ver__extract_version --full-match --keep-suffix "v1.2.3-rc1"
  assert_output "1.2.3-rc1"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix captures inline alpha label" {
  run ver__extract_version --full-match --keep-suffix "3.13.0a4"
  assert_output "3.13.0a4"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix rejects non-numeric-prefixed tag" {
  run ver__extract_version --full-match --keep-suffix "arm64-1.0.0"
  assert_output ""
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix accepts bare semver" {
  run ver__extract_version --full-match --keep-suffix "1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix rejects non-version string" {
  run ver__extract_version --full-match --keep-suffix "latest"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# Major-only (X) version format and fallback behaviour
# ---------------------------------------------------------------------------

@test "ver__extract_version accepts major-only version" {
  run ver__extract_version "1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version --keep-suffix accepts major-only version" {
  run ver__extract_version --keep-suffix "1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version --full-match accepts major-only version" {
  run ver__extract_version --full-match "1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix accepts major-only version" {
  run ver__extract_version --full-match --keep-suffix "1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix accepts major-only with v prefix" {
  run ver__extract_version --full-match --keep-suffix "v1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version prefers X.Y match in prose over bare digits" {
  run ver__extract_version "step 1 of 3: version 2.46.0"
  assert_output "2.46.0"
  assert_success
}

@test "ver__extract_version handles two-part version" {
  run ver__extract_version "1.2"
  assert_output "1.2"
  assert_success
}

@test "ver__extract_version --full-match accepts two-part version" {
  run ver__extract_version --full-match "1.2"
  assert_output "1.2"
  assert_success
}

@test "ver__semver_ge returns false when a is zero and b is real version" {
  run ver__semver_ge "0" "1.2.0"
  assert_failure
}

# ---------------------------------------------------------------------------
# ver__semver_is_final
# ---------------------------------------------------------------------------

@test "ver__semver_is_final returns true for stable three-part version" {
  run ver__semver_is_final "1.2.3"
  assert_success
}

@test "ver__semver_is_final returns true for major-only version" {
  run ver__semver_is_final "1"
  assert_success
}

@test "ver__semver_is_final returns true for two-part version" {
  run ver__semver_is_final "1.2"
  assert_success
}

@test "ver__semver_is_final returns false for version with hyphen pre-release suffix" {
  run ver__semver_is_final "1.2.3-rc1"
  assert_failure
}

@test "ver__semver_is_final returns false for version with beta suffix" {
  run ver__semver_is_final "1.0.0-beta.1"
  assert_failure
}

@test "ver__semver_is_final returns false for version with inline alpha label" {
  run ver__semver_is_final "3.13.0a4"
  assert_failure
}

@test "ver__semver_is_final returns false for empty string" {
  run ver__semver_is_final ""
  assert_failure
}

@test "ver__semver_is_final returns true for version with build metadata only" {
  run ver__semver_is_final "1.2.3+build.1"
  assert_success
}

@test "ver__semver_is_final returns false for pre-release version with build metadata" {
  run ver__semver_is_final "1.2.3-rc1+build"
  assert_failure
}

# ---------------------------------------------------------------------------
# ver__first_matching_prefix
# ---------------------------------------------------------------------------

@test "ver__first_matching_prefix matches exact version" {
  run ver__first_matching_prefix "1.2.3" <<< "1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "ver__first_matching_prefix matches prefix followed by dot" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "1.3.0" "1.2.5" "1.2.0" "1.1.0")"
  assert_output "1.2.5"
  assert_success
}

@test "ver__first_matching_prefix matches prefix followed by dash" {
  run ver__first_matching_prefix "1.2.0" <<< "$(printf '%s\n' "1.2.0-rc1" "1.1.0")"
  assert_output "1.2.0-rc1"
  assert_success
}

@test "ver__first_matching_prefix returns first match from list" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "2.0.0" "1.2.5" "1.2.3" "1.2.0")"
  assert_output "1.2.5"
  assert_success
}

@test "ver__first_matching_prefix strips leading non-numeric prefix from input lines" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "v2.0.0" "v1.2.5" "v1.1.0")"
  assert_output "v1.2.5"
  assert_success
}

@test "ver__first_matching_prefix does not match longer prefix" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "1.20.0" "1.21.0")"
  assert_failure
}

@test "ver__first_matching_prefix returns failure when no match" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "2.0.0" "3.1.0")"
  assert_failure
}

@test "ver__first_matching_prefix matches major-only spec" {
  run ver__first_matching_prefix "1" <<< "$(printf '%s\n' "2.1.0" "1.9.0" "1.8.0")"
  assert_output "1.9.0"
  assert_success
}
