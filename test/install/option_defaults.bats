#!/usr/bin/env bats
# Guardrails for option variables that must not rely on redundant :- defaults in the template.

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

  KEEP_CACHE=false
  KEEP_BUILD_DEPS=false
  KEEP_REPOS=false
  VERSION="stable"
  NODE_VERSION="lts"
  PREFIX_BIN_DIR="bin"
  METHOD="npm-bundled"
  NPM_PACKAGE="@devfeats/test-pkg"
  _RESOLVED_PREFIX="/opt/test"
  logging__skip() { :; }
  logging__info() { :; }
  logging__debug() { :; }
  logging__warn() { :; }
  logging__error() { printf 'ERROR: %s\n' "$*" >&2; }
  export -f logging__skip logging__info logging__debug logging__warn logging__error
}

@test "exit cleanup: KEEP_CACHE false does not run ospkg__clean" {
  ospkg__clean() {
    printf 'clean-called\n'
    return 0
  }
  export -f ospkg__clean
  KEEP_CACHE=false
  run bash -c '
    source /dev/null
    KEEP_CACHE=false
    if [[ "${KEEP_CACHE}" != true ]]; then
      ospkg__clean
    fi
  '
  assert_success
  assert_output "clean-called"
}

@test "exit cleanup: KEEP_CACHE true skips ospkg__clean branch" {
  ospkg__clean() {
    printf 'clean-called\n'
    return 0
  }
  export -f ospkg__clean
  run bash -c '
    KEEP_CACHE=true
    if [[ "${KEEP_CACHE}" != true ]]; then
      ospkg__clean
    fi
  '
  assert_success
  assert_output ""
}

@test "sidecar resolution: empty spec is rejected before sidecar branch" {
  VERSION_RESOLUTION="sidecar"
  VERSION_URI="https://example.invalid/sidecar"
  VERSION_PATTERN='version="([^"]+)"'
  ver__resolve_from_sidecar() {
    printf 'should-not-run\n'
    return 0
  }
  export -f ver__resolve_from_sidecar
  run __feat_resolve_version_spec__ ""
  assert_failure
}

@test "sidecar resolution: passes spec through without stable fallback" {
  VERSION_RESOLUTION="sidecar"
  VERSION_URI="https://example.invalid/sidecar"
  VERSION_PATTERN='version="([^"]+)"'
  ver__resolve_from_sidecar() {
    [[ "$3" == "1.2.3" ]] || return 1
    printf '1.2.3\n'
    return 0
  }
  export -f ver__resolve_from_sidecar
  run __feat_resolve_version_spec__ "1.2.3"
  assert_success
  assert_output "1.2.3"
}

@test "auto method: VERSION_INPUT fallback uses VERSION when unset" {
  unset VERSION_INPUT
  VERSION="1.0.0"
  VERSION_RESOLUTION="none"
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN=""
  _stub linux amd64 apt privileged debian
  run_auto_method() {
    __ctx_sync_version__
    __ctx_sync_method__
    run __resolve_auto_method__
  }
  run_auto_method
  assert_success
  assert_output "package"
}

_stub() {
  _STUB_KERNEL="${1:-linux}"
  _STUB_ARCH="${2:-amd64}"
  _STUB_PM="${3:-apt}"
  _STUB_PRIV="${4:-privileged}"
  _STUB_PLATFORM="${5:-debian}"

  os__release_kernel() { printf '%s\n' "${_STUB_KERNEL}"; }
  os__release_arch() { printf '%s\n' "${_STUB_ARCH}"; }
  os__platform() { printf '%s\n' "${_STUB_PLATFORM}"; }
  os__rust_triple() { return 1; }
  ctx__reset
  ctx__set "plat.kernel=${_STUB_KERNEL}"
  ctx__set "plat.machine_release=${_STUB_ARCH}"
  ctx__set "plat.pm=${_STUB_PM}"
  ctx__set "os.id=${_STUB_PLATFORM}"
  _CTX__REGISTRY_INITIALIZED=true
  ospkg__has_available_version() { return 0; }
  users__is_privileged() { return 0; }
  export -f os__release_kernel os__release_arch os__platform os__rust_triple
  export -f ospkg__has_available_version users__is_privileged
}
