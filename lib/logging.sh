# shellcheck shell=bash
# Structured logging with emoji prefixes and configurable verbosity levels.
#
# Log level is controlled via the `LOG_LEVEL` environment variable
# (`silent` | `error` | `warn` | `info` | `debug` | `trace`; defaults to `info`).
# Call `logging__setup` at script start and `logging__cleanup` at the end to
# capture all output to a log file.

_LOGGING__LIB_SETUP=false
_LOGGING__SYSSET_TMPDIR=
_LOGGING__SYSSET_MASKED_VALUES=()

# LOG_LEVEL: silent | error | warn | info (default) | debug | trace
# Numeric: silent=0 (only logging__fatal), error=1, warn=2, info=3, debug=4, trace=5
_LOGGING__LEVEL=3

# Internal: set _LOGGING__LEVEL from $LOG_LEVEL. Returns 1 if value was invalid (defaults to info).
_logging__recompute_level() {
  case "${LOG_LEVEL:-info}" in
    [Ss][Ii][Ll][Ee][Nn][Tt]) _LOGGING__LEVEL=0 ;;
    [Ee][Rr][Rr][Oo][Rr]) _LOGGING__LEVEL=1 ;;
    [Ww][Aa][Rr][Nn]) _LOGGING__LEVEL=2 ;;
    [Ii][Nn][Ff][Oo]) _LOGGING__LEVEL=3 ;;
    [Dd][Ee][Bb][Uu][Gg]) _LOGGING__LEVEL=4 ;;
    [Tt][Rr][Aa][Cc][Ee]) _LOGGING__LEVEL=5 ;;
    *)
      _LOGGING__LEVEL=3
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
  [[ "${_LOGGING__LEVEL}" -ge 1 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '⛔' "$@"
  return 0
}

# @brief logging__warn <line>... — LOG_LEVEL ≥ warn. Prefix: ⚠️
logging__warn() {
  [[ "${_LOGGING__LEVEL}" -ge 2 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '⚠️' "$@"
  return 0
}

# @brief logging__success <line>... — LOG_LEVEL ≥ info. Prefix: ✅
logging__success() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '✅' "$@"
  return 0
}

# @brief logging__info <line>... — LOG_LEVEL ≥ info. Prefix: ℹ️
logging__info() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit 'ℹ️' "$@"
  return 0
}

# @brief logging__debug <line>... — LOG_LEVEL ≥ debug. Prefix: 🐞
logging__debug() {
  [[ "${_LOGGING__LEVEL}" -ge 4 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🐞' "$@"
  return 0
}

# @brief logging__feature_entry <feature_name>... — LOG_LEVEL ≥ info. One line: ↪️ Script entry: …
logging__feature_entry() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  _logging__emit '↪️' "Script entry: $*"
  return 0
}

# @brief logging__detect <line>... — LOG_LEVEL ≥ info. Prefix: 🛠️
logging__detect() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🛠️' "$@"
  return 0
}

# @brief logging__inspect <line>... — LOG_LEVEL ≥ info (dry-run / probes). Prefix: 🔍
logging__inspect() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🔍' "$@"
  return 0
}

# @brief logging__install <line>... — LOG_LEVEL ≥ info. Prefix: 📦
logging__install() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '📦' "$@"
  return 0
}

# @brief logging__download <line>... — LOG_LEVEL ≥ info. Prefix: 📥
logging__download() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '📥' "$@"
  return 0
}

# @brief logging__build <line>... — LOG_LEVEL ≥ info. Prefix: 🔨
logging__build() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🔨' "$@"
  return 0
}

# @brief logging__remove <line>... — LOG_LEVEL ≥ info. Prefix: 🗑️
logging__remove() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🗑️' "$@"
  return 0
}

# @brief logging__clean <line>... — LOG_LEVEL ≥ info. Prefix: 🧹
logging__clean() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🧹' "$@"
  return 0
}

# @brief logging__launch <line>... — LOG_LEVEL ≥ info. Prefix: 🚀
logging__launch() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '🚀' "$@"
  return 0
}

# @brief logging__read <line>... — LOG_LEVEL ≥ info (env var echo). Prefix: 📩
logging__read() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit '📩' "$@"
  return 0
}

# @brief logging__fn_entry <detail>... — LOG_LEVEL ≥ info. Prefix: ↪️ ("Function entry: …")
logging__fn_entry() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  _logging__emit '↪️' "Function entry: $*"
  return 0
}

# @brief logging__fn_exit <detail>... — LOG_LEVEL ≥ info. Prefix: ↩️ ("Function exit: …")
logging__fn_exit() {
  [[ "${_LOGGING__LEVEL}" -ge 3 ]] || return 0
  _logging__emit '↩️' "Function exit: $*"
  return 0
}

# @brief logging__set_level — Re-read LOG_LEVEL into _LOGGING__LEVEL (call after CLI/env parsing).
#
# Enables xtrace for LOG_LEVEL=trace and disables it otherwise.
logging__set_level() {
  if ! _logging__recompute_level; then
    logging__warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."
  fi
  if [[ "${_LOGGING__LEVEL}" -ge 5 ]]; then
    set -x
  else
    set +x
  fi
  return 0
}

_logging__recompute_level || logging__warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."

# @brief logging__setup — Redirect stdout+stderr through `tee` into a temp log file; save original fds.
#
# On first call: creates _LOGGING__SYSSET_TMPDIR (a process-lifetime temp dir) and
# _LOGGING__LOG_FILE_TMP (the captured log file, inside _LOGGING__SYSSET_TMPDIR). Saves the
# original stdout as fd 3 and stderr as fd 4 via `exec`.
#
# Does NOT install an EXIT trap — the caller is responsible. Pair with:
#   trap 'logging__cleanup' EXIT
#
# Cleanup deletes _LOGGING__SYSSET_TMPDIR and all file__tmpdir subdirectories.
# Auto-registers GITHUB_TOKEN (if set) as a masked secret.
logging__setup() {
  if declare -f file__tmpdir > /dev/null 2>&1; then
    _LOGGING__SYSSET_TMPDIR="$(file__tmpdir)"
  else
    [[ -z "${_LOGGING__SYSSET_TMPDIR:-}" ]] && _LOGGING__SYSSET_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/devfeats_XXXXXX")"
  fi
  _LOGGING__LOG_FILE_TMP="$(mktemp "${_LOGGING__SYSSET_TMPDIR}/log_XXXXXX")"
  exec 3>&1 4>&2
  exec > >(tee -a "$_LOGGING__LOG_FILE_TMP" >&3) 2>&1
  _LOGGING__LIB_SETUP=true
  # Auto-mask well-known secrets present at setup time.
  [[ -n "${GITHUB_TOKEN:-}" ]] && logging__mask_secret "$GITHUB_TOKEN"
  return 0
}

# @brief logging__mask_secret <value> — Register a secret value to be redacted when `logging__cleanup` writes to `$LOG_FILE`.
#
# Args:
#   <value>  The secret string to mask. No-op if empty.
logging__mask_secret() {
  [[ -n "${1:-}" ]] && _LOGGING__SYSSET_MASKED_VALUES+=("$1")
  return 0
}

# @brief logging__cleanup — Restore original fds, flush the temp log to `$LOG_FILE` if set, and delete `_LOGGING__SYSSET_TMPDIR`.
#
# No-op if logging__setup was never called. If $LOG_FILE is set, appends the
# captured output (with any registered secrets masked) to that file. Deletes
# _LOGGING__SYSSET_TMPDIR (which contains _LOGGING__LOG_FILE_TMP and any file__tmpdir
# subdirectories) and restores the original stdout (fd 3) and stderr (fd 4).
logging__cleanup() {
  [[ "${_LOGGING__LIB_SETUP-}" == true ]] || return 0
  exec 1>&3 2>&4
  wait 2> /dev/null
  exec 3>&- 4>&-
  local _LOG_FILE_DEST="${LOG_FILE-}"
  if [ -n "${_LOG_FILE_DEST}" ]; then
    logging__info "Write logs to file '${_LOG_FILE_DEST}'"
    mkdir -p "$(dirname "$_LOG_FILE_DEST")"
    if [[ ${#_LOGGING__SYSSET_MASKED_VALUES[@]} -gt 0 ]]; then
      local _log _v
      _log="$(cat "$_LOGGING__LOG_FILE_TMP")"
      for _v in "${_LOGGING__SYSSET_MASKED_VALUES[@]}"; do
        [[ -n "$_v" ]] && _log="${_log//"$_v"/***}"
      done
      printf '%s' "$_log" >> "$_LOG_FILE_DEST"
    else
      cat "$_LOGGING__LOG_FILE_TMP" >> "$_LOG_FILE_DEST"
    fi
  fi
  rm -rf "${_LOGGING__SYSSET_TMPDIR-}"
  _LOGGING__SYSSET_TMPDIR=
  _LOGGING__SYSSET_MASKED_VALUES=()
  _LOGGING__LIB_SETUP=false
  return 0
}
