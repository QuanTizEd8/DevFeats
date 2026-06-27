#!/usr/bin/env bats
# Integration tests for lib/users.sh — exercises real user/group management.
#
# users__create_group, users__delete_group, users__create_user,
# users__delete_user, users__add_to_group, users__create_system_user, and
# users__set_login_shell have no tests of any kind in the unit suite.
# These functions call groupadd/useradd/userdel/groupdel directly and require
# root, which Docker integration containers provide.

bats_require_minimum_version 1.5.0

# Unique names derived from the tmpdir suffix to avoid collision with real
# system accounts across parallel or repeated runs.
_IG_NAMES_FILE=""

setup_file() {
  load '../helpers/common'
  reload_lib

  bootstrap__shadow_utils

  local _suffix="${BATS_FILE_TMPDIR##*/}"
  local _g="df-ig-grp-${_suffix}"
  local _u="df-ig-usr-${_suffix}"
  local _s="df-ig-sys-${_suffix}"
  printf '%s\n%s\n%s\n' "$_g" "$_u" "$_s" > "${BATS_FILE_TMPDIR}/names"
}

teardown_file() {
  load '../helpers/common'
  reload_lib
  local _g _u _s
  {
    read -r _g
    read -r _u
    read -r _s
  } < "${BATS_FILE_TMPDIR}/names"
  userdel -f "$_u" 2> /dev/null || true
  userdel -f "$_s" 2> /dev/null || true
  groupdel "$_g" 2> /dev/null || true
}

setup() {
  load '../helpers/common'
  reload_lib
  local _g _u _s
  {
    read -r _g
    read -r _u
    read -r _s
  } < "${BATS_FILE_TMPDIR}/names"
  _IG_GROUP="$_g"
  _IG_USER="$_u"
  _IG_SYS_USER="$_s"
}

# ── Group lifecycle ───────────────────────────────────────────────────────────

@test "users__create_group: creates a new group" {
  run users__create_group "$_IG_GROUP"
  assert_success
  getent group "$_IG_GROUP" > /dev/null 2>&1
}

@test "users__create_group: respects --gid" {
  local _gid_group="${_IG_GROUP}-gid"
  run users__create_group "$_gid_group" --gid 60100
  assert_success
  getent group "$_gid_group" | grep -q ':60100:'
  groupdel "$_gid_group" 2> /dev/null || true
}

# ── User lifecycle ────────────────────────────────────────────────────────────

@test "users__create_user: creates a regular user" {
  run users__create_user "$_IG_USER"
  assert_success
  id "$_IG_USER" > /dev/null 2>&1
}

@test "users__add_to_group: adds user to a supplementary group" {
  run users__add_to_group "$_IG_USER" "$_IG_GROUP"
  assert_success
  id "$_IG_USER" | grep -q "$_IG_GROUP"
}

@test "users__create_system_user: creates a system user" {
  run users__create_system_user "$_IG_SYS_USER"
  assert_success
  getent passwd "$_IG_SYS_USER" > /dev/null 2>&1
}

@test "users__set_login_shell: changes the login shell" {
  command -v chsh > /dev/null 2>&1 || skip "chsh not available"
  run users__set_login_shell "$_IG_USER" /bin/sh
  assert_success
  getent passwd "$_IG_USER" | grep -q ':/bin/sh$'
}

# ── Deletion ─────────────────────────────────────────────────────────────────

@test "users__delete_user: removes the user" {
  run users__delete_user "$_IG_USER"
  assert_success
  run id "$_IG_USER"
  assert_failure
}

@test "users__delete_group: removes the group" {
  run users__delete_group "$_IG_GROUP"
  assert_success
  run getent group "$_IG_GROUP"
  assert_failure
}
