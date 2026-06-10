# shellcheck shell=sh
# shellcheck disable=SC3043
# POSIX logging API — shared by install.sh and logging.sh (bash).
#
# Pre-setup records append to _LOGGING__PENDING_FILE (buffer-only, no live stderr).
# When lib/logging.sh is loaded it sets _LOGGING__BASH_BACKEND=1 and provides
# _logging__bash_emit / _logging__bash_structured (source order vs logging.sh does not matter).
# Call logging__set_prefix or logging__setup --prefix once; structured messages become
# "<emoji> <prefix>: <text>" (feature prefix on pending replay when set at setup).
# With logging.sh loaded, logging__set_fn_prefix 1 / logging__setup --fn-prefix prepends
# the bash caller function: "<emoji> <prefix>: <fn>: <text>".
#
# Record format (one line per message): <min_level><TAB><emoji> <message>

_LOGGING__PENDING_FILE=${_LOGGING__PENDING_FILE:-}
_LOGGING__PENDING_HANDED_OFF=${_LOGGING__PENDING_HANDED_OFF:-0}
_LOGGING__PENDING_FLUSHED=${_LOGGING__PENDING_FLUSHED:-0}
_LOGGING__BASH_BACKEND=${_LOGGING__BASH_BACKEND:-0}
_LOGGING__PREFIX=${_LOGGING__PREFIX:-}
_LOGGING__FN_PREFIX=${_LOGGING__FN_PREFIX:-0}

# @brief logging__pending_init — Open pending journal and install EXIT trap.
logging__pending_init() {
  _logging__pending_ensure
  trap '_logging__pending_on_exit $?' EXIT
  return 0
}

# @brief logging__set_prefix <id> — Prefix structured log messages (e.g. feature id).
logging__set_prefix() {
  _LOGGING__PREFIX=$(_logging__sanitize_line "${1-}")
  export _LOGGING__PREFIX
  return 0
}

# @brief logging__set_fn_prefix [0|1] — Prepend bash caller function to structured messages.
logging__set_fn_prefix() {
  case "${1:-1}" in
    0 | [Ff][Aa][Ll][Ss][Ee] | [Nn][Oo] | [Oo][Ff][Ff])
      _LOGGING__FN_PREFIX=0
      ;;
    *)
      _LOGGING__FN_PREFIX=1
      ;;
  esac
  export _LOGGING__FN_PREFIX
  return 0
}

# @brief logging__pending_handoff — Export journal for install.bash; disable fail dump.
logging__pending_handoff() {
  _LOGGING__PENDING_HANDED_OFF=1
  export _LOGGING__PENDING_HANDED_OFF
  _logging__pending_ensure
  export _LOGGING__PENDING_FILE
  return 0
}

# @brief logging__fatal <line>... — Always emitted. Prefix: ❌
logging__fatal() {
  [ $# -eq 0 ] && return 0
  _logging__emit_impl 0 '❌' "$@"
  return 0
}

# @brief logging__error <line>... — LOG_LEVEL ≥ error. Prefix: ⛔
logging__error() {
  [ $# -eq 0 ] && return 0
  _logging__structured 1 '⛔' "$@"
  return 0
}

# @brief logging__warn <line>... — LOG_LEVEL ≥ warn. Prefix: ⚠️
logging__warn() {
  [ $# -eq 0 ] && return 0
  _logging__structured 2 '⚠️' "$@"
  return 0
}

# @brief logging__success <line>... — LOG_LEVEL ≥ info. Prefix: ✅
logging__success() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '✅' "$@"
  return 0
}

# @brief logging__info <line>... — LOG_LEVEL ≥ info. Prefix: ℹ️
logging__info() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 'ℹ️' "$@"
  return 0
}

# @brief logging__debug <line>... — LOG_LEVEL ≥ debug. Prefix: 🐞
logging__debug() {
  [ $# -eq 0 ] && return 0
  _logging__structured 4 '🐞' "$@"
  return 0
}

# @brief logging__feature_entry <feature_name>... — LOG_LEVEL ≥ info.
logging__feature_entry() {
  _logging__structured 3 '↪️' "Script entry: $*"
  return 0
}

# @brief logging__feature_exit <feature_name>... — LOG_LEVEL ≥ info.
logging__feature_exit() {
  _logging__structured 3 '↩️' "Script exit: $*"
  return 0
}

# @brief logging__detect <line>... — LOG_LEVEL ≥ info. Prefix: 🛠️
logging__detect() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '🛠️' "$@"
  return 0
}

# @brief logging__inspect <line>... — LOG_LEVEL ≥ info. Prefix: 🔍
logging__inspect() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '🔍' "$@"
  return 0
}

# @brief logging__install <line>... — LOG_LEVEL ≥ info. Prefix: 📦
logging__install() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '📦' "$@"
  return 0
}

# @brief logging__download <line>... — LOG_LEVEL ≥ info. Prefix: 📥
logging__download() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '📥' "$@"
  return 0
}

# @brief logging__build <line>... — LOG_LEVEL ≥ info. Prefix: 🔨
logging__build() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '🔨' "$@"
  return 0
}

# @brief logging__remove <line>... — LOG_LEVEL ≥ info. Prefix: 🗑️
logging__remove() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '🗑️' "$@"
  return 0
}

# @brief logging__clean <line>... — LOG_LEVEL ≥ info. Prefix: 🧹
logging__clean() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '🧹' "$@"
  return 0
}

# @brief logging__launch <line>... — LOG_LEVEL ≥ info. Prefix: 🚀
logging__launch() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '🚀' "$@"
  return 0
}

# @brief logging__read <line>... — LOG_LEVEL ≥ info. Prefix: 📩
logging__read() {
  [ $# -eq 0 ] && return 0
  _logging__structured 3 '📩' "$@"
  return 0
}

# @brief logging__skip <line>... — LOG_LEVEL ≥ debug. Prefix: ⏭️ (intentional no-op / early return).
logging__skip() {
  [ $# -eq 0 ] && return 0
  _logging__structured 4 '⏭️' "$@"
  return 0
}

_logging__sanitize_line() {
  local _log_san_in="${1-}"
  # shellcheck disable=SC3060
  _log_san_in=$(printf '%s' "$_log_san_in" | tr -d '\000')
  printf '%s' "$_log_san_in"
}

_logging__encode_payload() {
  local _log_enc_in
  _log_enc_in=$(_logging__sanitize_line "${1-}")
  _log_enc_in=$(printf '%s' "$_log_enc_in" | tr '\t' ' ')
  _log_enc_in=$(printf '%s' "$_log_enc_in" | tr '\n' ' ')
  _log_enc_in=$(printf '%s' "$_log_enc_in" | tr '\r' ' ')
  printf '%s' "$_log_enc_in"
}

_logging__apply_msg_prefix() {
  local _log_am_in
  _log_am_in=$(_logging__sanitize_line "${1-}")
  if [ -z "${_LOGGING__PREFIX:-}" ]; then
    printf '%s' "$_log_am_in"
    return 0
  fi
  case "$_log_am_in" in
    "${_LOGGING__PREFIX}: "* | "${_LOGGING__PREFIX}:"*)
      printf '%s' "$_log_am_in"
      return 0
      ;;
  esac
  printf '%s: %s' "$_LOGGING__PREFIX" "$_log_am_in"
  return 0
}

_logging__prefix_payload() {
  local _log_pl_payload _log_pl_emoji _log_pl_msg
  _log_pl_payload=$(_logging__sanitize_line "${1-}")
  if [ -z "${_LOGGING__PREFIX:-}" ]; then
    printf '%s' "$_log_pl_payload"
    return 0
  fi
  _log_pl_emoji="${_log_pl_payload%% *}"
  _log_pl_msg="${_log_pl_payload#* }"
  if [ "$_log_pl_msg" = "$_log_pl_payload" ]; then
    printf '%s' "$_log_pl_payload"
    return 0
  fi
  case "$_log_pl_msg" in
    "${_LOGGING__PREFIX}: "* | "${_LOGGING__PREFIX}:"*)
      printf '%s' "$_log_pl_payload"
      return 0
      ;;
  esac
  printf '%s %s: %s' "$_log_pl_emoji" "$_LOGGING__PREFIX" "$_log_pl_msg"
  return 0
}

_logging__format_msg() {
  local _log_fm_in
  _log_fm_in=$(_logging__sanitize_line "${1-}")
  if [ "${_LOGGING__FN_PREFIX:-0}" = 1 ]; then
    if command -v _logging__decorate_fn_prefix > /dev/null 2>&1; then
      _log_fm_in=$(_logging__decorate_fn_prefix "$_log_fm_in")
    fi
  fi
  _log_fm_in=$(_logging__apply_msg_prefix "$_log_fm_in")
  printf '%s' "$_log_fm_in"
  return 0
}

_logging__pending_ensure() {
  if [ -z "${_LOGGING__PENDING_FILE:-}" ]; then
    _LOGGING__PENDING_FILE=$(mktemp "${TMPDIR:-/tmp}/df-pending.XXXXXX")
  fi
}

_logging__pending_emit() {
  local _log_min _log_emoji _log_msg _log_fmt
  _log_min=$1
  _log_emoji=$2
  shift 2
  [ $# -eq 0 ] && return 0
  _logging__pending_ensure
  _LOGGING__PENDING_FLUSHED=0
  for _log_msg in "$@"; do
    _log_msg=$(_logging__format_msg "$_log_msg")
    _log_fmt="${_log_emoji} ${_log_msg}"
    _log_fmt=$(_logging__encode_payload "$_log_fmt")
    printf '%s\t%s\n' "$_log_min" "$_log_fmt" >> "$_LOGGING__PENDING_FILE"
  done
  return 0
}

_logging__emit_impl() {
  local _log_min _log_emoji
  _log_min=$1
  _log_emoji=$2
  shift 2
  [ $# -eq 0 ] && return 0
  if [ "${_LOGGING__BASH_BACKEND:-0}" = 1 ] && [ "${_LOGGING__LIB_SETUP:-false}" = true ]; then
    _logging__bash_emit "$_log_min" "$_log_emoji" "$@"
  else
    _logging__pending_emit "$_log_min" "$_log_emoji" "$@"
  fi
  return 0
}

_logging__structured() {
  local _log_min _log_emoji
  _log_min=$1
  _log_emoji=$2
  shift 2
  [ $# -eq 0 ] && return 0
  if [ "${_LOGGING__BASH_BACKEND:-0}" = 1 ] && [ "${_LOGGING__LIB_SETUP:-false}" = true ]; then
    _logging__bash_structured "$_log_min" "$_log_emoji" "$@"
  else
    _logging__emit_impl "$_log_min" "$_log_emoji" "$@"
  fi
  return 0
}

_logging__pending_console_level() {
  if [ -n "${_LOGGING__LEVEL:-}" ]; then
    printf '%s' "$_LOGGING__LEVEL"
    return 0
  fi
  case "${LOG_LEVEL:-info}" in
    [Ss][Ii][Ll][Ee][Nn][Tt]) printf '0' ;;
    [Ee][Rr][Rr][Oo][Rr]) printf '1' ;;
    [Ww][Aa][Rr][Nn]) printf '2' ;;
    [Ii][Nn][Ff][Oo]) printf '3' ;;
    [Dd][Ee][Bb][Uu][Gg]) printf '4' ;;
    [Tt][Rr][Aa][Cc][Ee]) printf '5' ;;
    *) printf '3' ;;
  esac
  return 0
}

_logging__pending_dump_stderr() {
  local _log_console _log_min _log_payload
  if [ -z "${_LOGGING__PENDING_FILE:-}" ] || [ ! -f "$_LOGGING__PENDING_FILE" ]; then
    return 0
  fi
  _log_console=$(_logging__pending_console_level)
  while IFS= read -r _log_line || [ -n "$_log_line" ]; do
    _log_min=$(printf '%s\n' "$_log_line" | cut -f1)
    [ "$_log_console" -ge "$_log_min" ] || continue
    _log_payload=$(printf '%s\n' "$_log_line" | cut -f2-)
    _log_payload=$(_logging__prefix_payload "$_log_payload")
    [ -n "$_log_payload" ] && printf '%s\n' "$_log_payload" >&2
  done < "$_LOGGING__PENDING_FILE"
  return 0
}

_logging__pending_on_exit() {
  local _log_exit_code="$1"
  if [ "$_LOGGING__PENDING_HANDED_OFF" = 1 ]; then
    return 0
  fi
  if [ "$_log_exit_code" -ne 0 ]; then
    _logging__pending_dump_stderr
  fi
  if [ -n "${_LOGGING__PENDING_FILE:-}" ] && [ -f "$_LOGGING__PENDING_FILE" ]; then
    rm -f "$_LOGGING__PENDING_FILE"
    _LOGGING__PENDING_FILE=
  fi
  return 0
}
