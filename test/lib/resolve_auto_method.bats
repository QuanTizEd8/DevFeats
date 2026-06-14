#!/usr/bin/env bats
# Unit tests for __resolve_auto_method__() in features/install.tmpl.bash.
#
# __resolve_auto_method__ is extracted directly from the template at test time
# via awk. The OS lib functions it depends on (os__match_when, os__match_spec,
# ospkg__os_release_match, etc.) are loaded at suite startup; ospkg__os_release_match
# is overridden per-test via _stub() so no real OS detection is needed.

bats_require_minimum_version 1.5.0

setup_file() {
  load 'helpers/common'

  # Extract __resolve_auto_method__ from features/install.tmpl.bash.
  _RAM_FUNC="$(awk '/^__resolve_auto_method__\(\) \{/,/^\}$/' \
    "${REPO_ROOT}/features/install.tmpl.bash")"
  [[ -n "${_RAM_FUNC}" ]] || {
    echo "FATAL: could not extract __resolve_auto_method__ from install.tmpl.bash" >&2
    return 1
  }
  export _RAM_FUNC
}

setup() {
  load 'helpers/common'
  load 'helpers/stubs'

  # Define the function under test in the current shell.
  eval "${_RAM_FUNC}"

  # Default contract: empty (no methods).
  _FEAT_CONTRACT_METHODS=""
  _FEAT_CONTRACT_BINARY_WHEN=""
  _FEAT_CONTRACT_PACKAGE_WHEN=""
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN=""
  _FEAT_CONTRACT_PRIMARY_BIN=""
  BINARY_ASSET_URI=""
  VERSION="stable"
  VERSION_RESOLUTION=""
  _OSPKG__FAMILY=""
  _OSPKG__DETECTED=false

  # Default stubs: Linux/amd64/apt/privileged/debian.
  _stub linux amd64 apt privileged debian
}

# ──────────────────────────────────────────────────────────────────────────────
# Stub helpers
# ──────────────────────────────────────────────────────────────────────────────

# _stub <kernel> <arch> <pm> <privileged|unprivileged> [<platform/os-id>]
#
# Stores stub values in _STUB_* globals so that stub function bodies are
# visible inside subshells created by `run` and inside command substitutions
# in __resolve_auto_method__. The stub overrides ospkg__os_release_match so
# that os__match_spec / os__match_when (loaded from the lib at suite startup)
# use _STUB_* values rather than real OS detection.
_stub() {
  _STUB_KERNEL="${1:-linux}"
  _STUB_ARCH="${2:-amd64}"
  _STUB_PM="${3:-apt}"
  _STUB_PRIV="${4:-privileged}"
  _STUB_PLATFORM="${5:-debian}"

  os__release_kernel() { printf '%s\n' "${_STUB_KERNEL}"; }
  os__release_arch()   { printf '%s\n' "${_STUB_ARCH}"; }
  os__platform()       { printf '%s\n' "${_STUB_PLATFORM}"; }
  os__rust_triple()    { return 1; }  # no triple by default
  ospkg__detect()      { _OSPKG__FAMILY="${_STUB_PM}"; _OSPKG__DETECTED=true; }
  # Override ospkg__os_release_match so os__match_spec / os__match_when use
  # _STUB_* globals instead of _OSPKG__OS_RELEASE (which is never populated).
  ospkg__os_release_match() {
    local _key="$1" _val="${2,,}"
    case "${_key}" in
      kernel) [[ "${_STUB_KERNEL,,}" == "${_val}" ]] ;;
      arch)   [[ "${_STUB_ARCH,,}" == "${_val}" ]] ;;
      pm)     [[ "${_STUB_PM,,}" == "${_val}" ]] ;;
      id)     [[ "${_STUB_PLATFORM,,}" == "${_val}" ]] ;;
      *)      return 1 ;;
    esac
  }
  ospkg__has_available_version() { return 0; }
  logging__error() { printf 'ERROR: %s\n' "$*" >&2; }
  logging__debug() { :; }

  if [[ "${_STUB_PRIV}" == "privileged" ]]; then
    users__is_privileged() { return 0; }
  else
    users__is_privileged() { return 1; }
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# binary — arch constraint via when
# ──────────────────────────────────────────────────────────────────────────────

@test "binary: selected when arch matches when condition" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN="arch=amd64|arm64"
  run __resolve_auto_method__
  assert_success
  assert_output "binary"
}

@test "binary: skipped when arch not in when condition" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN="arch=amd64|arm64"
  _stub linux armv7 apt privileged
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "binary: selected when kernel:arch matches when condition (array form)" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'kernel=linux arch=amd64\nkernel=linux arch=arm64\nkernel=darwin arch=amd64\nkernel=darwin arch=arm64'
  run __resolve_auto_method__
  assert_success
  assert_output "binary"
}

@test "binary: skipped when kernel:arch not in when condition (array form)" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'kernel=linux arch=amd64\nkernel=linux arch=arm64\nkernel=darwin arch=amd64'
  _stub darwin arm64 brew privileged macos
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "binary: selected with no when condition (unconstrained)" {
  _FEAT_CONTRACT_METHODS="binary"
  # No when, no RUST_TRIPLE in URI → always feasible
  run __resolve_auto_method__
  assert_success
  assert_output "binary"
}

# ──────────────────────────────────────────────────────────────────────────────
# binary — RUST_TRIPLE fallback (independent of when)
# ──────────────────────────────────────────────────────────────────────────────

@test "binary: selected via RUST_TRIPLE when no when declared" {
  _FEAT_CONTRACT_METHODS="binary script"
  BINARY_ASSET_URI="https://example.com/tool-{RUST_TRIPLE}.tar.gz"
  os__rust_triple() { printf 'x86_64-unknown-linux-musl\n'; }
  run __resolve_auto_method__
  assert_success
  assert_output "binary"
}

@test "binary: skipped via RUST_TRIPLE when triple unavailable" {
  _FEAT_CONTRACT_METHODS="binary script"
  BINARY_ASSET_URI="https://example.com/tool-{RUST_TRIPLE}.tar.gz"
  # os__rust_triple returns failure by default in _stub
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

# ──────────────────────────────────────────────────────────────────────────────
# upstream-package
# ──────────────────────────────────────────────────────────────────────────────

@test "upstream-package: selected when PM matches when condition and VERSION=stable" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=apt|dnf"
  run __resolve_auto_method__
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package: skipped when PM not in when condition" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=apt|dnf"
  _stub linux amd64 apk privileged
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "upstream-package: skipped for VERSION=latest" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=apt"
  VERSION="latest"
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "upstream-package: skipped for specific VERSION" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=apt"
  VERSION="1.2.3"
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "upstream-package: skipped on linux when not privileged" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=apt"
  _stub linux amd64 apt unprivileged
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "upstream-package: selected on macOS without privilege" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=brew"
  _stub darwin arm64 brew unprivileged
  run __resolve_auto_method__
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package: selected with no when condition (all PMs)" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _stub linux amd64 apk privileged
  run __resolve_auto_method__
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package when: selected on Ubuntu (id=ubuntu matches)" {
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="id=ubuntu"
  _stub linux amd64 apt privileged ubuntu
  run __resolve_auto_method__
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package when: skipped on Debian even though PM=apt" {
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="id=ubuntu"
  _stub linux amd64 apt privileged debian
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

# ──────────────────────────────────────────────────────────────────────────────
# package
# ──────────────────────────────────────────────────────────────────────────────

@test "package: selected when PM matches when condition and VERSION=stable" {
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt|brew"
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "package: skipped when PM not in when condition" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt|brew"
  _stub linux amd64 apk privileged
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "package: selected with no when condition (all PMs)" {
  _FEAT_CONTRACT_METHODS="package"
  _stub linux amd64 apk privileged
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "package: skipped for VERSION=latest" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt"
  VERSION="latest"
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "package: selected for specific version when PM has it" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt"
  _FEAT_CONTRACT_PRIMARY_BIN="mytool"
  VERSION="2.3.0"
  ospkg__has_available_version() { return 0; }
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "package: skipped for specific version when PM lacks it" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt"
  _FEAT_CONTRACT_PRIMARY_BIN="mytool"
  VERSION="9.9.9"
  ospkg__has_available_version() { return 1; }
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "package: skipped on linux when not privileged" {
  _FEAT_CONTRACT_METHODS="package source"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt"
  _stub linux amd64 apt unprivileged
  run __resolve_auto_method__
  assert_success
  assert_output "source"
}

@test "package: selected on macOS without privilege" {
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=brew"
  _stub darwin arm64 brew unprivileged
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

# ──────────────────────────────────────────────────────────────────────────────
# script / source — always feasible
# ──────────────────────────────────────────────────────────────────────────────

@test "script: always selected when in methods list" {
  _FEAT_CONTRACT_METHODS="script"
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "source: always selected when in methods list" {
  _FEAT_CONTRACT_METHODS="source"
  run __resolve_auto_method__
  assert_success
  assert_output "source"
}

# ──────────────────────────────────────────────────────────────────────────────
# npm-bundled
# ──────────────────────────────────────────────────────────────────────────────

@test "npm-bundled: selected on linux/amd64 non-alpine" {
  _FEAT_CONTRACT_METHODS="npm-bundled"
  _stub linux amd64 apt privileged debian
  run __resolve_auto_method__
  assert_success
  assert_output "npm-bundled"
}

@test "npm-bundled: skipped on alpine, falls through to npm" {
  _FEAT_CONTRACT_METHODS="npm-bundled npm"
  _stub linux amd64 apk privileged alpine
  create_fake_bin npm
  prepend_fake_bin_path
  run __resolve_auto_method__
  assert_success
  assert_output "npm"
}

@test "npm-bundled: skipped on unsupported arch (armv7), falls through to npm" {
  _FEAT_CONTRACT_METHODS="npm-bundled npm"
  _stub linux armv7 apt privileged debian
  create_fake_bin npm
  prepend_fake_bin_path
  run __resolve_auto_method__
  assert_success
  assert_output "npm"
}

@test "npm-bundled: selected on darwin/arm64" {
  _FEAT_CONTRACT_METHODS="npm-bundled"
  _stub darwin arm64 brew privileged macos
  run __resolve_auto_method__
  assert_success
  assert_output "npm-bundled"
}

# ──────────────────────────────────────────────────────────────────────────────
# npm / cargo / git-clone — command availability
# ──────────────────────────────────────────────────────────────────────────────

@test "npm: selected when npm is on PATH" {
  _FEAT_CONTRACT_METHODS="npm"
  create_fake_bin npm
  prepend_fake_bin_path
  run __resolve_auto_method__
  assert_success
  assert_output "npm"
}

@test "npm: skipped when npm not on PATH" {
  _FEAT_CONTRACT_METHODS="npm source"
  begin_path_isolation
  run __resolve_auto_method__
  end_path_isolation
  assert_success
  assert_output "source"
}

@test "cargo: selected when cargo is on PATH" {
  _FEAT_CONTRACT_METHODS="cargo"
  create_fake_bin cargo
  prepend_fake_bin_path
  run __resolve_auto_method__
  assert_success
  assert_output "cargo"
}

@test "cargo: skipped when cargo not on PATH" {
  _FEAT_CONTRACT_METHODS="cargo source"
  begin_path_isolation
  run __resolve_auto_method__
  end_path_isolation
  assert_success
  assert_output "source"
}

@test "git-clone: selected when git is on PATH" {
  _FEAT_CONTRACT_METHODS="git-clone"
  create_fake_bin git
  prepend_fake_bin_path
  run __resolve_auto_method__
  assert_success
  assert_output "git-clone"
}

@test "git-clone: skipped when git not on PATH" {
  _FEAT_CONTRACT_METHODS="git-clone source"
  begin_path_isolation
  run __resolve_auto_method__
  end_path_isolation
  assert_success
  assert_output "source"
}

# ──────────────────────────────────────────────────────────────────────────────
# Priority order
# ──────────────────────────────────────────────────────────────────────────────

@test "priority: binary beats package when both feasible" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN="arch=amd64"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt"
  run __resolve_auto_method__
  assert_success
  assert_output "binary"
}

@test "priority: upstream-package beats package when both feasible" {
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=apt"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt"
  run __resolve_auto_method__
  assert_success
  assert_output "upstream-package"
}

@test "priority: package beats script when both feasible" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apt"
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "priority: falls through to script when binary arch unsupported" {
  _FEAT_CONTRACT_METHODS="binary script"
  _FEAT_CONTRACT_BINARY_WHEN="arch=amd64|arm64"
  _stub linux ppc64le apt privileged
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

# ──────────────────────────────────────────────────────────────────────────────
# Error cases
# ──────────────────────────────────────────────────────────────────────────────

@test "error: returns 1 when no feasible method found" {
  _FEAT_CONTRACT_METHODS="binary"
  _FEAT_CONTRACT_BINARY_WHEN="arch=arm64"  # current arch is amd64
  run __resolve_auto_method__
  assert_failure
}

@test "error: returns 1 with empty methods contract" {
  _FEAT_CONTRACT_METHODS=""
  run __resolve_auto_method__
  assert_failure
}

# ──────────────────────────────────────────────────────────────────────────────
# VERSION_RESOLUTION=none bypasses version-based skipping
# ──────────────────────────────────────────────────────────────────────────────

@test "package: VERSION=latest with VERSION_RESOLUTION=none → selected (not skipped)" {
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apk"
  _stub linux amd64 apk privileged alpine
  VERSION="latest"
  VERSION_RESOLUTION="none"
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "package: VERSION=2024 with VERSION_RESOLUTION=none → selected (no ospkg check)" {
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apk"
  _stub linux amd64 apk privileged alpine
  VERSION="2024"
  VERSION_RESOLUTION="none"
  ospkg__has_available_version() { return 1; }  # would reject if called
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "upstream-package: VERSION=latest with VERSION_RESOLUTION=none → selected" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=apk"
  _stub linux amd64 apk privileged alpine
  VERSION="latest"
  VERSION_RESOLUTION="none"
  run __resolve_auto_method__
  assert_success
  assert_output "upstream-package"
}

@test "package: VERSION=latest without VERSION_RESOLUTION=none → still skipped" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apk"
  _stub linux amd64 apk privileged alpine
  VERSION="latest"
  # VERSION_RESOLUTION unset / empty
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

# ──────────────────────────────────────────────────────────────────────────────
# Realistic feature scenarios
# ──────────────────────────────────────────────────────────────────────────────

@test "scenario: install-fzf on amd64 linux → binary" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN="arch=amd64|arm64|armv7|armv6|armv5|ppc64le|riscv64|s390x|loong64"
  run __resolve_auto_method__
  assert_success
  assert_output "binary"
}

@test "scenario: install-shellcheck on darwin:arm64 → package (no darwin:arm64 binary)" {
  _FEAT_CONTRACT_METHODS="binary package script"
  _FEAT_CONTRACT_BINARY_WHEN=$'kernel=linux arch=amd64\nkernel=linux arch=arm64\nkernel=darwin arch=amd64'
  _stub darwin arm64 brew privileged macos
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "scenario: install-yq on amd64 linux with apt → binary (apt excluded from package)" {
  _FEAT_CONTRACT_METHODS="binary package script"
  _FEAT_CONTRACT_BINARY_WHEN="arch=amd64|arm64"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=dnf|apk|zypper|brew|pacman"
  # apt (default stub) is not in package when → package skipped; binary wins
  run __resolve_auto_method__
  assert_success
  assert_output "binary"
}

@test "scenario: install-yq on i386 privileged apt → script (no binary, apt excluded)" {
  _FEAT_CONTRACT_METHODS="binary package script"
  _FEAT_CONTRACT_BINARY_WHEN="arch=amd64|arm64"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=dnf|apk|zypper|brew|pacman"
  _stub linux i386 apt privileged
  run __resolve_auto_method__
  assert_success
  assert_output "script"
}

@test "scenario: install-uv on dnf privileged → package" {
  _FEAT_CONTRACT_METHODS="binary package script"
  BINARY_ASSET_URI="https://example.com/uv-{RUST_TRIPLE}.tar.gz"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=brew|dnf|apk|pacman|zypper"
  _stub linux amd64 dnf privileged
  # Ensure rust triple is unavailable on this stub (no binary)
  os__rust_triple() { return 1; }
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "scenario: install-claude on armv7 unprivileged → npm (no binary, no pkg priv)" {
  _FEAT_CONTRACT_METHODS="binary upstream-package npm-bundled npm"
  _FEAT_CONTRACT_BINARY_WHEN="arch=amd64|arm64"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="pm=apt|dnf|apk|brew"
  _stub linux armv7 apt unprivileged debian
  create_fake_bin npm
  prepend_fake_bin_path
  run __resolve_auto_method__
  assert_success
  assert_output "npm"
}

@test "scenario: install-git on Ubuntu/apt privileged → upstream-package (Ubuntu PPA)" {
  _FEAT_CONTRACT_METHODS="upstream-package package source"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="id=ubuntu"
  _stub linux amd64 apt privileged ubuntu
  run __resolve_auto_method__
  assert_success
  assert_output "upstream-package"
}

@test "scenario: install-git on Debian/apt privileged → package (no Ubuntu PPA)" {
  _FEAT_CONTRACT_METHODS="upstream-package package source"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="id=ubuntu"
  _stub linux amd64 apt privileged debian
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "scenario: install-git on Alpine/apk privileged → package (native apk)" {
  _FEAT_CONTRACT_METHODS="upstream-package package source"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN="id=ubuntu"
  _stub linux amd64 apk privileged alpine
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "scenario: install-texlive (VERSION_RESOLUTION=none) on Alpine → package" {
  _FEAT_CONTRACT_METHODS="package source"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apk"
  _stub linux amd64 apk privileged alpine
  VERSION="latest"
  VERSION_RESOLUTION="none"
  run __resolve_auto_method__
  assert_success
  assert_output "package"
}

@test "scenario: install-texlive (VERSION_RESOLUTION=none) on Debian → source (no apt package)" {
  _FEAT_CONTRACT_METHODS="package source"
  _FEAT_CONTRACT_PACKAGE_WHEN="pm=apk"
  _stub linux amd64 apt privileged debian
  VERSION="latest"
  VERSION_RESOLUTION="none"
  run __resolve_auto_method__
  assert_success
  assert_output "source"
}
