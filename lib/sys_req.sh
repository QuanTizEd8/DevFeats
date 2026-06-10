# shellcheck shell=bash
# System requirements guards for feature install scripts.

sys_req__require_platform() {
  # @brief sys_req__require_platform -- [key=val ...] [-- key=val ...] — Exits 1 if none of the spec groups match the current OS.
  #
  # Spec groups are separated by "--" and ORed: at least one group must match.
  # Within a group, key=val pairs are passed to os__match_spec (AND logic).
  # The error message is built automatically from the spec groups.
  #
  # Args:
  #   --          Separator before the first spec group (required).
  #   key=val ... One or more key=value pairs for os__match_spec.

  # Build human-readable description from all groups (for the error message).
  local _desc="" _group_desc _a
  local -a _grp_args=()
  for _a in "$@"; do
    if [[ "$_a" == "--" ]]; then
      if [[ "${#_grp_args[@]}" -gt 0 ]]; then
        printf -v _group_desc '%s, ' "${_grp_args[@]}"
        _desc+="${_desc:+ OR }(${_group_desc%, })"
        _grp_args=()
      fi
    else
      _grp_args+=("$_a")
    fi
  done
  if [[ "${#_grp_args[@]}" -gt 0 ]]; then
    printf -v _group_desc '%s, ' "${_grp_args[@]}"
    _desc+="${_desc:+ OR }(${_group_desc%, })"
  fi

  local _any_match=false
  local -a _current=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      if [[ "${#_current[@]}" -gt 0 ]] && os__match_spec "${_current[@]}"; then
        _any_match=true
        break
      fi
      _current=()
      continue
    fi
    _current+=("$1")
    shift
  done
  if [[ "$_any_match" != true && "${#_current[@]}" -gt 0 ]] && os__match_spec "${_current[@]}"; then
    _any_match=true
  fi
  if [[ "$_any_match" != true ]]; then
    logging__fatal "Unsupported platform. This feature requires: ${_desc}"
    exit 1
  fi
}

sys_req__require_root() {
  # @brief sys_req__require_root [-- [key=val ...] [-- key=val ...]] — Exits 1 if not running as root or with passwordless sudo.
  #
  # With no arguments: unconditional root check.
  # With "--"-separated spec groups: exits 1 only if the current platform matches
  # one of the groups (same spec format as sys_req__require_platform).
  if [[ $# -eq 0 ]]; then
    if ! users__is_privileged; then
      logging__fatal "This feature must be run as root (or with passwordless sudo)."
      exit 1
    fi
    return
  fi
  local _any_match=false
  local -a _current=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      if [[ "${#_current[@]}" -gt 0 ]] && os__match_spec "${_current[@]}"; then
        _any_match=true
        break
      fi
      _current=()
      continue
    fi
    _current+=("$1")
    shift
  done
  if [[ "$_any_match" != true && "${#_current[@]}" -gt 0 ]] && os__match_spec "${_current[@]}"; then
    _any_match=true
  fi
  if [[ "$_any_match" == true ]] && ! users__is_privileged; then
    logging__fatal "This feature must be run as root (or with passwordless sudo) on the current platform."
    exit 1
  fi
}
