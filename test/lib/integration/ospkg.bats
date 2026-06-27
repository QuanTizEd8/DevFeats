#!/usr/bin/env bats
# Integration tests for lib/ospkg.sh — exercises real package-manager operations.
#
# Requires a real package manager and typically runs as root inside a container.
# Skipped when the canary package is already installed on the system.

bats_require_minimum_version 1.5.0

# Small, widely-available package unlikely to be pre-installed in minimal containers.
_OSPKG_INT_PKG=bc

# _pkg_force_remove <name> — unconditionally remove <name>; errors are ignored.
_pkg_force_remove() {
  case "$_OSPKG__PKG_MNGR" in
    apt-get) DEBIAN_FRONTEND=noninteractive apt-get -y --purge remove "$1" > /dev/null 2>&1 || true ;;
    apk) apk del "$1" > /dev/null 2>&1 || true ;;
    dnf) dnf -y remove "$1" > /dev/null 2>&1 || true ;;
    yum) yum -y remove "$1" > /dev/null 2>&1 || true ;;
    microdnf) microdnf remove "$1" > /dev/null 2>&1 || true ;;
    zypper) zypper --non-interactive remove "$1" > /dev/null 2>&1 || true ;;
    pacman) pacman -R --noconfirm "$1" > /dev/null 2>&1 || true ;;
  esac
}

setup() {
  load '../helpers/common'
  reload_lib
  # Isolate sidecar / snapshot files in the per-test tmpdir so tests do not share state.
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  # Skip when the canary is already installed — we cannot safely use it as a marker.
  # ospkg__is_installed auto-detects the package manager.
  if ospkg__is_installed "$_OSPKG_INT_PKG"; then
    skip "'${_OSPKG_INT_PKG}' is already installed on this system; cannot use it as a canary"
  fi
}

teardown() {
  if [[ -n "${_OSPKG__PKG_MNGR:-}" ]]; then
    ospkg__cleanup_all_build_groups 2> /dev/null || true
    ospkg__is_installed "$_OSPKG_INT_PKG" && _pkg_force_remove "$_OSPKG_INT_PKG" || true
  fi
}

# ── PM detection ─────────────────────────────────────────────────────────────

@test "ospkg__pm_key identifies a known package manager key" {
  local _key
  _key="$(ospkg__pm_key)"
  [[ -n "${_key}" ]]
  case "${_key}" in
    apt | apk | dnf | yum | zypper | pacman | brew) ;;
    *) fail "unexpected package manager key: '${_key}'" ;;
  esac
}

# ── Install and sidecar tracking ─────────────────────────────────────────────

@test "ospkg__install_tracked installs package and writes a sidecar file" {
  run ospkg__install_tracked "ospkg-inttest" "$_OSPKG_INT_PKG"
  assert_success

  # Package must be present on the system.
  ospkg__is_installed "$_OSPKG_INT_PKG"

  # At least one non-dot sidecar file must exist in the build-deps directory.
  local _bd_dir="${BATS_TEST_TMPDIR}/ospkg/build-deps"
  local _found=false
  local _f
  for _f in "${_bd_dir}"/*; do
    [[ -f "$_f" ]] || continue
    [[ "$(basename "$_f")" == .* ]] && continue
    _found=true
    break
  done
  [[ "$_found" == true ]]
}

# ── Cleanup removes tracked packages ─────────────────────────────────────────

@test "ospkg__cleanup_all_build_groups removes the tracked package" {
  ospkg__install_tracked "ospkg-inttest" "$_OSPKG_INT_PKG"
  ospkg__is_installed "$_OSPKG_INT_PKG" # sanity: confirm installed before cleanup

  run ospkg__cleanup_all_build_groups
  assert_success

  run ospkg__is_installed "$_OSPKG_INT_PKG"
  assert_failure # package must be gone
}

# ── Snapshot protection ───────────────────────────────────────────────────────

@test "cleanup does not remove pre-existing packages (snapshot protection)" {
  # Homebrew on macOS can autonomously update/remove packages during the test,
  # making the snapshot assertion unreliable outside Linux containers.
  [[ "$(uname)" == Linux ]] || skip "Homebrew auto-updates make snapshot check unreliable on macOS"
  # Record every package installed before the test touches anything.
  local _snapshot="${BATS_TEST_TMPDIR}/pretest_pkgs.txt"
  _ospkg__snapshot_packages "$_snapshot"

  ospkg__install_tracked "ospkg-inttest" "$_OSPKG_INT_PKG"
  ospkg__cleanup_all_build_groups

  # Every package in the pre-test snapshot must still be installed.
  local _missing=0 _pkg
  while IFS= read -r _pkg; do
    [[ -z "$_pkg" ]] && continue
    if ! ospkg__is_installed "$_pkg"; then
      echo "MISSING after cleanup: ${_pkg}" >&3
      ((_missing++)) || true
    fi
  done < "$_snapshot"
  [[ "$_missing" -eq 0 ]]
}

# ── User-package protection ───────────────────────────────────────────────────

@test "package promoted via ospkg__install_user survives cleanup" {
  # Step 1: install and track as a build dep.
  ospkg__install_tracked "ospkg-inttest" "$_OSPKG_INT_PKG"

  # Step 2: promote to user-installed (marks manual / evicts from sidecar).
  run ospkg__install_user "$_OSPKG_INT_PKG"
  assert_success

  # Step 3: cleanup should now leave the package in place.
  run ospkg__cleanup_all_build_groups
  assert_success

  ospkg__is_installed "$_OSPKG_INT_PKG" # must survive
}

# ── Additional PM operations ──────────────────────────────────────────────────

@test "ospkg__update: refreshes package index without error" {
  run ospkg__update --force
  assert_success
}

@test "ospkg__resolve_version: returns PM version string for a known package" {
  # Use the running bash's own major version as the spec so the test is valid
  # on all distros (e.g. bash 4.x on openSUSE Leap, 5.x on Ubuntu/Fedora/…).
  local _major
  _major="${BASH_VERSINFO[0]}"
  run ospkg__resolve_version bash "$_major"
  assert_success
  [[ -n "$output" ]]
}

@test "ospkg__has_available_version: returns 0 for bash with matching major-version spec" {
  local _major
  _major="${BASH_VERSINFO[0]}"
  run ospkg__has_available_version bash "$_major"
  assert_success
}

@test "ospkg__register_dummy: registers a dummy package on apt systems" {
  [[ "$(ospkg__pm_key)" == "apt" ]] || skip "apt only"
  run ospkg__register_dummy devfeats-inttest-dummy 1.0.0
  assert_success
  # Package must appear as installed after registration.
  ospkg__is_installed devfeats-inttest-dummy
  # Unregister; non-fatal if removal is partial.
  ospkg__unregister_dummy devfeats-inttest-dummy 2> /dev/null || true
}
