#!/usr/bin/env bats
# Unit tests for source build env filtering/export and source auto-install in the install framework.
# shellcheck disable=SC2034  # framework state vars are consumed by sourced functions called via `run`

bats_require_minimum_version 1.5.0

setup_file() {
  load 'helpers/bootstrap_tools'
  test_bootstrap__setup_file_jq_yq
}

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  load 'helpers/bootstrap_tools'
  test_bootstrap__require_jq_yq
  test_bootstrap__wire_tools_for_run
  load 'helpers/stubs'
  load 'helpers/ctx'

  VERSION="3.7.1"
  METHOD="source"
  _FEAT_RESOLVED_TAG="v3.7.1"
  SOURCE_BUILD_ENV=()
  SOURCE_INSTALL_BINS=()
  ctx__reset
  ctx__set feat.version=3.7.1
  ctx__set feat.version_input=3.7.1
  ctx__set feat.tag=v3.7.1
  ctx__set feat.method=source
  _CTX__REGISTRY_INITIALIZED=true
}

_publish_feat_ctx() {
  ctx__set feat.version="${VERSION}"
  ctx__set feat.version_input="${VERSION_INPUT:-${VERSION}}"
  ctx__set feat.tag="${_FEAT_RESOLVED_TAG:-}"
  ctx__set feat.method="${METHOD:-source}"
}

@test "__feat_filter_source_install_bins__: plain path passes through" {
  SOURCE_INSTALL_BINS=("bin/git-lfs")
  run __feat_filter_source_install_bins__
  assert_success
  assert_output "bin/git-lfs"
}

@test "__feat_filter_source_install_bins__: tab-when line included when condition matches" {
  local _when=$'plat.kernel: linux'
  ctx__set plat.kernel=linux
  SOURCE_INSTALL_BINS=("bin/git-lfs	${_when}")
  run __feat_filter_source_install_bins__
  assert_success
  assert_output "bin/git-lfs"
}

@test "__feat_filter_source_install_bins__: tab-when line excluded when condition fails" {
  local _when=$'plat.kernel: darwin'
  ctx__set plat.kernel=linux
  SOURCE_INSTALL_BINS=("bin/git-lfs	${_when}")
  run __feat_filter_source_install_bins__
  assert_success
  assert_output ""
}

@test "__feat_filter_source_build_env__: tab-when line included when condition matches" {
  local _when=$'plat.kernel: linux'
  ctx__set plat.kernel=linux
  SOURCE_BUILD_ENV=("GOTOOLCHAIN=auto	${_when}")
  run __feat_filter_source_build_env__
  assert_success
  assert_output "GOTOOLCHAIN=auto"
}

@test "__install_run_source_auto_build__: exports SOURCE_BUILD_ENV into make recipes" {
  local _src_dir="${BATS_TEST_TMPDIR}/src-build-env"
  mkdir -p "${_src_dir}"
  cat > "${_src_dir}/Makefile" << 'EOF'
all:
	test "$$FEATURE_TEST_ENV" = expected
	printf '%s\n' "$$FEATURE_TEST_ENV" > build-env.out
EOF
  SOURCE_BUILD_SYSTEM="make"
  SOURCE_BUILD_ENV=("FEATURE_TEST_ENV=expected")
  SOURCE_MAKE_FLAGS=()
  SOURCE_MAKE_TARGETS=("all")

  run __install_run_source_auto_build__ "${_src_dir}"
  assert_success
  run cat "${_src_dir}/build-env.out"
  assert_output "expected"
}

@test "__install_run_source_export_build_env__: rejects invalid assignments" {
  SOURCE_BUILD_ENV=("not-an-assignment")

  run __install_run_source_export_build_env__
  assert_failure
  assert_output --partial "not a valid NAME=value assignment"
}

@test "__install_run_source_auto_install_bins__: copies built binaries into PREFIX/bin" {
  local _src_dir="${BATS_TEST_TMPDIR}/src"
  local _prefix="${BATS_TEST_TMPDIR}/prefix"
  mkdir -p "${_src_dir}/bin" "${_prefix}"
  printf '#!/bin/sh\nexit 0\n' > "${_src_dir}/bin/git-lfs"
  chmod 0644 "${_src_dir}/bin/git-lfs"
  _RESOLVED_PREFIX="${_prefix}"
  SOURCE_INSTALL_BINS=("bin/git-lfs")

  run __install_run_source_auto_install_bins__ "${_src_dir}"
  assert_success
  assert_output --partial "Installing binary"
  test -x "${_prefix}/bin/git-lfs"
}

@test "__install_run_source_auto_install_bins__: fails when all entries are filtered out" {
  local _src_dir="${BATS_TEST_TMPDIR}/src"
  local _prefix="${BATS_TEST_TMPDIR}/prefix"
  mkdir -p "${_src_dir}/bin" "${_prefix}"
  printf '#!/bin/sh\nexit 0\n' > "${_src_dir}/bin/git-lfs"
  chmod 0755 "${_src_dir}/bin/git-lfs"
  _RESOLVED_PREFIX="${_prefix}"
  ctx__set plat.kernel=linux
  SOURCE_INSTALL_BINS=($'bin/git-lfs\tplat.kernel: darwin')

  run __install_run_source_auto_install_bins__ "${_src_dir}"
  assert_failure
  assert_output --partial "No source_install_bins entries matched"
}
