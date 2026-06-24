#!/usr/bin/env bats
# Unit tests for __feat_pm_version_spec__ and __ctx_sync_pm_version__.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  load 'helpers/stubs'
  load 'helpers/ctx'

  VERSION="stable"
  VERSION_INPUT="stable"
  VERSION_RESOLUTION="github_release"
  METHOD="package"
  ctx__reset
  _CTX__REGISTRY_INITIALIZED=true
  logging__error() { :; }
  logging__debug() { :; }
  logging__warn() { :; }
}

@test "__feat_pm_version_spec__: stable channel yields empty PM spec" {
  VERSION="2.54.0"
  VERSION_INPUT="stable"
  run __feat_pm_version_spec__
  assert_success
  assert_output ""
}

@test "__feat_pm_version_spec__: latest channel yields empty PM spec" {
  VERSION="2.54.0"
  VERSION_INPUT="latest"
  run __feat_pm_version_spec__
  assert_success
  assert_output ""
}

@test "__feat_pm_version_spec__: semver prefix uses VERSION_INPUT" {
  VERSION="5.4.2"
  VERSION_INPUT="5.4"
  run __feat_pm_version_spec__
  assert_success
  assert_output "5.4"
}

@test "__feat_pm_version_spec__: exact semver uses VERSION_INPUT" {
  VERSION="2.47.0"
  VERSION_INPUT="2.47.0"
  run __feat_pm_version_spec__
  assert_success
  assert_output "2.47.0"
}

@test "__feat_pm_version_spec__: v-prefixed semver strips v" {
  VERSION="1.8.1"
  VERSION_INPUT="v1.8"
  run __feat_pm_version_spec__
  assert_success
  assert_output "1.8"
}

@test "__feat_pm_version_spec__: opaque dist-tag uses resolved VERSION after auto resolve" {
  VERSION="2.0.0-beta.1"
  VERSION_INPUT="beta"
  VERSION_RESOLUTION="npm"
  run __feat_pm_version_spec__
  assert_success
  assert_output "2.0.0-beta.1"
}

@test "__feat_pm_version_spec__: explicit package stable yields empty PM spec" {
  VERSION="stable"
  VERSION_INPUT="stable"
  METHOD="package"
  run __feat_pm_version_spec__
  assert_success
  assert_output ""
}

@test "__ctx_sync_pm_version__: publishes empty feat.pm_version for stable channel" {
  VERSION="2.54.0"
  VERSION_INPUT="stable"
  __ctx_sync_pm_version__
  [[ "$(ctx__get feat.pm_version)" == "" ]]
}

@test "__ctx_sync_pm_version__: publishes prefix for semver input" {
  VERSION="5.4.2"
  VERSION_INPUT="5.4"
  __ctx_sync_pm_version__
  [[ "$(ctx__get feat.pm_version)" == "5.4" ]]
}

@test "__feat_pm_version_spec__: non-semver string does not false-positive as semver" {
  VERSION="3rd-party"
  VERSION_INPUT="3rd-party"
  VERSION_RESOLUTION="github_release"
  __feat_resolve_version_spec__() { return 1; }
  run __feat_pm_version_spec__
  assert_success
  assert_output ""
}

@test "__feat_pm_version_spec__: git_ref resolution yields empty PM spec" {
  VERSION="master"
  VERSION_INPUT="master"
  VERSION_RESOLUTION="git_ref"
  run __feat_pm_version_spec__
  assert_success
  assert_output ""
}

@test "__feat_pm_version_spec__: failed lazy resolve yields empty PM spec" {
  VERSION="beta"
  VERSION_INPUT="beta"
  VERSION_RESOLUTION="npm"
  __feat_resolve_version_spec__() { return 1; }
  run __feat_pm_version_spec__
  assert_success
  assert_output ""
}

@test "__feat_pm_version_spec__: VERSION_RESOLUTION=none preserves opaque spec" {
  VERSION="foobar"
  VERSION_INPUT="foobar"
  VERSION_RESOLUTION="none"
  run __feat_pm_version_spec__
  assert_success
  assert_output "foobar"
}

@test "__feat_pm_version_spec__: calendar year spec is semver for PM pinning" {
  VERSION="2024"
  VERSION_INPUT="2024"
  VERSION_RESOLUTION="none"
  run __feat_pm_version_spec__
  assert_success
  assert_output "2024"
}
