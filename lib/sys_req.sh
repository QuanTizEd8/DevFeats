# shellcheck shell=bash
# System requirements guards for feature install scripts.

sys_req__require_platform() {
  # @brief sys_req__require_platform [<yaml-group> ...] — Exits 1 if none of the YAML when groups match.
  #
  # Each argument is a YAML AND-group (OR between arguments). Matching uses ctx__match_spec.
  local _desc="" _a
  for _a in "$@"; do
    _desc+="${_desc:+ OR }(${_a//$'\n'/; })"
  done

  local _any_match=false
  for _a in "$@"; do
    if ctx__match_spec "${_a}"; then
      _any_match=true
      break
    fi
  done
  if [[ "$_any_match" != true ]]; then
    logging__fatal "Unsupported platform. This feature requires: ${_desc}"
    exit 1
  fi
}

sys_req__require_root() {
  # @brief sys_req__require_root [<yaml-group> ...] — Exits 1 if not privileged when platform matches.
  #
  # With no arguments: unconditional root check.
  # With YAML when groups: exits 1 only if the current platform matches one of the groups.
  if [[ $# -eq 0 ]]; then
    if ! users__is_privileged; then
      logging__fatal "This feature must be run as root (or with passwordless sudo)."
      exit 1
    fi
    return
  fi
  local _any_match=false _a
  for _a in "$@"; do
    if ctx__match_spec "${_a}"; then
      _any_match=true
      break
    fi
  done
  if [[ "$_any_match" == true ]] && ! users__is_privileged; then
    logging__fatal "This feature must be run as root (or with passwordless sudo)."
    exit 1
  fi
}
