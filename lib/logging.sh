#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_LOGGING__LIB_LOADED-}" ]] && return 0
_LOGGING__LIB_LOADED=1

_LIB_LOGGING_SETUP=false
_SYSSET_TMPDIR=
_SYSSET_MASKED_VALUES=()

# LOG_LEVEL: silent | error | warn | info (default) | debug | trace
# Numeric: silent=0 (only logging__fatal), error=1, warn=2, info=3, debug=4, trace=5
_LOGGING_LEVEL=3

# Internal: set _LOGGING_LEVEL from $LOG_LEVEL. Returns 1 if value was invalid (defaults to info).
_logging__recompute_level() {
  case "${LOG_LEVEL:-info}" in
    [Ss][Ii][Ll][Ee][Nn][Tt]) _LOGGING_LEVEL=0 ;;
    [Ee][Rr][Rr][Oo][Rr]) _LOGGING_LEVEL=1 ;;
    [Ww][Aa][Rr][Nn]) _LOGGING_LEVEL=2 ;;
    [Ii][Nn][Ff][Oo]) _LOGGING_LEVEL=3 ;;
    [Dd][Ee][Bb][Uu][Gg]) _LOGGING_LEVEL=4 ;;
    [Tt][Rr][Aa][Cc][Ee]) _LOGGING_LEVEL=5 ;;
    *)
      _LOGGING_LEVEL=3
      return 1
      ;;
  esac
  return 0
}

# Internal: print each line as "<emoji> <line>" on stderr.
_logging__emit() {
  local _emoji="${1-}"
  shift
  [[ $# -eq 0 ]] && return 0
  local _msg
  for _msg in "$@"; do
    printf '%s %s\n' "$_emoji" "$_msg" >&2
  done
  return 0
}

# @brief logging__fatal <line>... — Always printed (even LOG_LEVEL=silent). Prefix: ❌
logging__fatal() {
  [[ $# -eq 0 ]] && return 0
  _logging__emit '❌' "$@"
  return 0
}

# @brief logging__error <line>... — LOG_LEVEL ≥ error. Prefix: ⛔
logging__error() {
  [[ "${_LOGGING_LEVEL}" -ge 1 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '⛔' "$@"
  return 0
}

# @brief logging__warn <line>... — LOG_LEVEL ≥ warn. Prefix: ⚠️
logging__warn() {
  [[ "${_LOGGING_LEVEL}" -ge 2 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '⚠️' "$@"
  return 0
}

# @brief logging__success <line>... — LOG_LEVEL ≥ info. Prefix: ✅
logging__success() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '✅' "$@"
  return 0
}

# @brief logging__info <line>... — LOG_LEVEL ≥ info. Prefix: ℹ️
logging__info() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit 'ℹ️' "$@"
  return 0
}

# @brief logging__debug <line>... — LOG_LEVEL ≥ debug. Prefix: 🐞
logging__debug() {
  [[ "${_LOGGING_LEVEL}" -ge 4 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🐞' "$@"
  return 0
}

# @brief logging__entry <feature_name>... — LOG_LEVEL ≥ info. One line: ↪️ Script entry: …
logging__entry() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  _logging__emit '↪️' "Script entry: $*"
  return 0
}

# @brief logging__detect <line>... — LOG_LEVEL ≥ info. Prefix: 🛠️
logging__detect() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🛠️' "$@"
  return 0
}

# @brief logging__inspect <line>... — LOG_LEVEL ≥ info (dry-run / probes). Prefix: 🔍
logging__inspect() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🔍' "$@"
  return 0
}

# @brief logging__install <line>... — LOG_LEVEL ≥ info. Prefix: 📦
logging__install() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '📦' "$@"
  return 0
}

# @brief logging__download <line>... — LOG_LEVEL ≥ info. Prefix: 📥
logging__download() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '📥' "$@"
  return 0
}

# @brief logging__build <line>... — LOG_LEVEL ≥ info. Prefix: 🔨
logging__build() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🔨' "$@"
  return 0
}

# @brief logging__remove <line>... — LOG_LEVEL ≥ info. Prefix: 🗑️
logging__remove() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🗑️' "$@"
  return 0
}

# @brief logging__clean <line>... — LOG_LEVEL ≥ info. Prefix: 🧹
logging__clean() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🧹' "$@"
  return 0
}

# @brief logging__launch <line>... — LOG_LEVEL ≥ info. Prefix: 🚀
logging__launch() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🚀' "$@"
  return 0
}

# @brief logging__read <line>... — LOG_LEVEL ≥ info (env var echo). Prefix: 📩
logging__read() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '📩' "$@"
  return 0
}

# @brief logging__fn_entry <detail>... — LOG_LEVEL ≥ info. Prefix: ↪️ ("Function entry: …")
logging__fn_entry() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  _logging__emit '↪️' "Function entry: $*"
  return 0
}

# @brief logging__fn_exit <detail>... — LOG_LEVEL ≥ info. Prefix: ↩️ ("Function exit: …")
logging__fn_exit() {
  [[ "${_LOGGING_LEVEL}" -ge 3 ]] || return 0
  _logging__emit '↩️' "Function exit: $*"
  return 0
}

# @brief logging__set_level — Re-read LOG_LEVEL into _LOGGING_LEVEL (call after CLI/env parsing).
# Enables xtrace for LOG_LEVEL=trace and disables it otherwise.
logging__set_level() {
  if ! _logging__recompute_level; then
    logging__warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."
  fi
  if [[ "${_LOGGING_LEVEL}" -ge 5 ]]; then
    set -x
  else
    set +x
  fi
  return 0
}

_logging__recompute_level || logging__warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."

# @brief logging__setup — Redirect stdout+stderr through `tee` into a temp log file; save original fds.
#
# On first call: creates _SYSSET_TMPDIR (a process-lifetime temp dir) and
# _LOG_FILE_TMP (the captured log file, inside _SYSSET_TMPDIR). Saves the
# original stdout as fd 3 and stderr as fd 4 via `exec`.
#
# Does NOT install an EXIT trap — the caller is responsible. Pair with:
#   trap 'logging__cleanup' EXIT
#
# Cleanup deletes _SYSSET_TMPDIR and all logging__tmpdir subdirectories.
# Auto-registers GITHUB_TOKEN (if set) as a masked secret.
logging__setup() {
  [[ -z "${_SYSSET_TMPDIR:-}" ]] && _SYSSET_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/devfeats_XXXXXX")"
  _LOG_FILE_TMP="$(mktemp "${_SYSSET_TMPDIR}/log_XXXXXX")"
  exec 3>&1 4>&2
  exec > >(tee -a "$_LOG_FILE_TMP" >&3) 2>&1
  _LIB_LOGGING_SETUP=true
  # Auto-mask well-known secrets present at setup time.
  [[ -n "${GITHUB_TOKEN:-}" ]] && logging__mask_secret "$GITHUB_TOKEN"
  return 0
}

# @brief logging__mask_secret <value> — Register a secret value to be redacted when `logging__cleanup` writes to `$LOG_FILE`.
#
# Args:
#   <value>  The secret string to mask. No-op if empty.
logging__mask_secret() {
  [[ -n "${1:-}" ]] && _SYSSET_MASKED_VALUES+=("$1")
  return 0
}

# @brief logging__tmpdir <name> — Return (and create if needed) a named subdirectory of `_SYSSET_TMPDIR`. Lazy-initialises `_SYSSET_TMPDIR` if needed. Idempotent.
#
# Safe to call from library code that does not control the script entry
# point, even if logging__setup has not yet been called.
#
# Args:
#   <name>  Name of the subdirectory to create under _SYSSET_TMPDIR.
#
# Stdout: absolute path to the named subdirectory.
logging__tmpdir() {
  [[ -z "${_SYSSET_TMPDIR:-}" ]] && _SYSSET_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/devfeats_XXXXXX")"
  mkdir -p "${_SYSSET_TMPDIR}/${1}"
  echo "${_SYSSET_TMPDIR}/${1}"
  return 0
}

# @brief logging__cleanup — Restore original fds, flush the temp log to `$LOG_FILE` if set, and delete `_SYSSET_TMPDIR`.
#
# No-op if logging__setup was never called. If $LOG_FILE is set, appends the
# captured output (with any registered secrets masked) to that file. Deletes
# _SYSSET_TMPDIR (which contains _LOG_FILE_TMP and any logging__tmpdir
# subdirectories) and restores the original stdout (fd 3) and stderr (fd 4).
logging__cleanup() {
  [[ "${_LIB_LOGGING_SETUP-}" == true ]] || return 0
  exec 1>&3 2>&4
  wait 2> /dev/null
  exec 3>&- 4>&-
  local _LOG_FILE_DEST="${LOG_FILE-}"
  if [ -n "${_LOG_FILE_DEST}" ]; then
    logging__info "Write logs to file '${_LOG_FILE_DEST}'"
    mkdir -p "$(dirname "$_LOG_FILE_DEST")"
    if [[ ${#_SYSSET_MASKED_VALUES[@]} -gt 0 ]]; then
      local _log _v
      _log="$(cat "$_LOG_FILE_TMP")"
      for _v in "${_SYSSET_MASKED_VALUES[@]}"; do
        [[ -n "$_v" ]] && _log="${_log//"$_v"/***}"
      done
      printf '%s' "$_log" >> "$_LOG_FILE_DEST"
    else
      cat "$_LOG_FILE_TMP" >> "$_LOG_FILE_DEST"
    fi
  fi
  rm -rf "${_SYSSET_TMPDIR-}"
  _SYSSET_TMPDIR=
  _SYSSET_MASKED_VALUES=()
  _LIB_LOGGING_SETUP=false
  return 0
}
