#!/usr/bin/env bash
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_INSTALL_COMMON__LIB_LOADED-}" ]] && return 0
_INSTALL_COMMON__LIB_LOADED=1

_INSTALL_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/logging.sh
. "${_INSTALL_COMMON_LIB_DIR}/../logging.sh"

# @brief _install__sanitize_key <raw> — Convert arbitrary tool/group identifiers to safe lowercase key fragments.
_install__sanitize_key() {
  local _raw="${1-}"
  _raw="${_raw,,}"
  _raw="${_raw//\//_}"
  _raw="${_raw//[^a-z0-9._-]/_}"
  printf '%s\n' "$_raw"
}

# @brief install__state_dir — Print installer state directory path under `_SYSSET_TMPDIR` (creates it if missing).
install__state_dir() {
  logging__tmpdir "install-state"
}

# @brief install__state_file <tool> — Print state file path for a tool key.
install__state_file() {
  local _tool="${1-}" _key
  _key="$(_install__sanitize_key "$_tool")"
  printf '%s/%s.state\n' "$(install__state_dir)" "$_key"
}

# @brief install__state_context <tool> — Read `context` field from tool state file.
install__state_context() {
  local _tool="${1-}" _f _ctx
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _ctx="$(sed -n 's/^context=//p' "$_f" | head -n1)"
  [[ -n "$_ctx" ]] || return 1
  printf '%s\n' "$_ctx"
}

# @brief install__state_install_path <tool> — Read `install_path` field from tool state file.
install__state_install_path() {
  local _tool="${1-}" _f _p
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _p="$(sed -n 's/^install_path=//p' "$_f" | head -n1)"
  [[ -n "$_p" ]] || return 1
  printf '%s\n' "$_p"
}

# @brief install__state_owner_group <tool> — Read `owner_group` field from tool state file.
install__state_owner_group() {
  local _tool="${1-}" _f _g
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _g="$(sed -n 's/^owner_group=//p' "$_f" | head -n1)"
  [[ -n "$_g" ]] || return 1
  printf '%s\n' "$_g"
}

# @brief install__state_record <tool> <context> <method> <install_path> <owner_group> — Persist ownership metadata for a tool install.
install__state_record() {
  local _tool="${1-}" _context="${2-}" _method="${3-}" _install_path="${4-}" _owner_group="${5-}"
  local _f
  [[ -n "$_tool" && -n "$_context" ]] || return 1
  _f="$(install__state_file "$_tool")"
  cat > "$_f" << EOF
tool=${_tool}
context=${_context}
method=${_method}
install_path=${_install_path}
owner_group=${_owner_group}
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2> /dev/null || true)
EOF
  return 0
}

# @brief install__track_internal_path <group-id> <path> — Register internal non-PM artifact path for cleanup via ospkg resource tracking.
install__track_internal_path() {
  local _group="${1-}" _path="${2-}"
  [[ -n "$_group" && -n "$_path" ]] || return 0
  command -v ospkg__track_resource > /dev/null 2>&1 || return 0
  ospkg__track_resource "$_group" "$_path" || true
  return 0
}

# @brief install__promote_path_to_user <group-id> <path> — Remove a previously tracked internal artifact path from cleanup tracking.
install__promote_path_to_user() {
  local _group="${1-}" _path="${2-}"
  [[ -n "$_path" ]] || return 0
  command -v ospkg__untrack_resource > /dev/null 2>&1 || return 0
  ospkg__untrack_resource "$_group" "$_path" || true
  return 0
}
