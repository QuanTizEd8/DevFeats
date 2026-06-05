# shellcheck shell=bash
# Structured logging with emoji prefixes, dual console/file thresholds, and ordered capture.
#
# Options (environment / CLI → installer variables):
#   LOG_LEVEL       — console minimum level (default: info)
#   LOG_FILE        — append session journal here on cleanup (default: empty)
#   LOG_FILE_LEVEL  — file minimum level when LOG_FILE is set (default: debug)
#
# Levels: silent=0, error=1, warn=2, info=3, debug=4, trace=5
#
# Call logging__set_level after parsing options (levels-only OK before setup).
# Call logging__setup once logging options are final; on EXIT call logging__cleanup then
# file__session_cleanup (installer template __exit__).
#
# Reserved fds after logging__setup: 3=stdout, 4=stderr, 5=mux writer (internal).
# Requires lib/file.sh (session scratch). Loaded by __init__.bash before this module.

if ! declare -f file__session_ensure > /dev/null 2>&1; then
  # shellcheck source=lib/file.sh
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/file.sh"
fi

_LOGGING__LIB_SETUP=false
_LOGGING__SYSSET_MASKED_VALUES=()
_LOGGING__PARSE_BUFFER=()

_LOGGING__LOG_FILE_TMP=
_LOGGING__CAPTURE_FILE=false
_LOGGING__MUX_FIFO=
_LOGGING__MUX_READER_PID=
_LOGGING__MUX_IN=5

# LOG_LEVEL / LOG_FILE_LEVEL numeric thresholds
_LOGGING__LEVEL=3
_LOGGING__FILE_LEVEL=4

# ---------------------------------------------------------------------------
# Level parsing
# ---------------------------------------------------------------------------

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

_logging__recompute_file_level() {
  case "${LOG_FILE_LEVEL:-debug}" in
    [Ss][Ii][Ll][Ee][Nn][Tt]) _LOGGING__FILE_LEVEL=0 ;;
    [Ee][Rr][Rr][Oo][Rr]) _LOGGING__FILE_LEVEL=1 ;;
    [Ww][Aa][Rr][Nn]) _LOGGING__FILE_LEVEL=2 ;;
    [Ii][Nn][Ff][Oo]) _LOGGING__FILE_LEVEL=3 ;;
    [Dd][Ee][Bb][Uu][Gg]) _LOGGING__FILE_LEVEL=4 ;;
    [Tt][Rr][Aa][Cc][Ee]) _LOGGING__FILE_LEVEL=5 ;;
    *)
      _LOGGING__FILE_LEVEL=4
      return 1
      ;;
  esac
  return 0
}

_logging__update_capture_file() {
  if [[ -n "${LOG_FILE:-}" ]]; then
    _LOGGING__CAPTURE_FILE=true
  else
    _LOGGING__CAPTURE_FILE=false
  fi
}

# Bootstrap warn (library load / before setup) — must not use buffered emit.
_logging__bootstrap_warn() {
  printf '⚠️ %s\n' "$*" >&2
}

# ---------------------------------------------------------------------------
# Ordered dispatch (single journal writer logic)
# ---------------------------------------------------------------------------

# Strip NUL bytes so journal lines stay text-safe.
_logging__sanitize_line() {
  local _s="${1-}"
  _s="${_s//$'\0'/}"
  printf '%s' "$_s"
}

# One FIFO line per record: tabs/newlines in payload would break DFLOG parsing.
_logging__encode_fifo_payload() {
  local _s
  _s="$(_logging__sanitize_line "${1-}")"
  _s="${_s//$'\t'/ }"
  _s="${_s//$'\n'/ }"
  _s="${_s//$'\r'/ }"
  printf '%s' "$_s"
}

# True when console or file sink wants structured output at min_level.
_logging__want_structured_at_level() {
  local _min="${1-}"
  if [[ "${_min}" -eq 0 ]]; then
    return 0
  fi
  [[ "${_LOGGING__LEVEL}" -ge "${_min}" ]] && return 0
  [[ "${_LOGGING__CAPTURE_FILE}" == true && "${_LOGGING__FILE_LEVEL}" -ge "${_min}" ]] && return 0
  return 1
}

_logging__want_console_at_level() {
  local _min="${1-}"
  [[ "${_min}" -eq 0 ]] && return 0
  [[ "${_LOGGING__LEVEL}" -ge "${_min}" ]] && return 0
  return 1
}

# @brief _logging__dispatch_payload <min_level> <payload_line>
# Write one line to console and/or session journal per sink thresholds.
_logging__dispatch_payload() {
  local _min="${1-}" _payload="${2-}"
  _payload="$(_logging__sanitize_line "$_payload")"
  [[ -z "$_payload" ]] && return 0

  local _to_console=false _to_file=false

  if [[ "${_min}" -eq 0 ]]; then
    _to_console=true
    [[ "${_LOGGING__CAPTURE_FILE}" == true ]] && _to_file=true
  else
    [[ "${_LOGGING__LEVEL}" -ge "${_min}" ]] && _to_console=true
    if [[ "${_LOGGING__CAPTURE_FILE}" == true && "${_LOGGING__FILE_LEVEL}" -ge "${_min}" ]]; then
      _to_file=true
    fi
  fi

  if [[ "${_to_console}" == true ]]; then
    printf '%s\n' "$_payload" >&4
  fi
  if [[ "${_to_file}" == true && -n "${_LOGGING__LOG_FILE_TMP:-}" ]]; then
    printf '%s\n' "$_payload" >> "$_LOGGING__LOG_FILE_TMP"
  fi
  return 0
}

# Parse DFLOG\\tkind\\tmin\\tpayload or infer kind from line shape.
_logging__dispatch_fifo_line() {
  local _line
  _line="$(_logging__sanitize_line "${1-}")"
  [[ -z "$_line" ]] && return 0

  local _kind _min _payload
  if [[ "$_line" == DFLOG$'\t'* ]]; then
    _kind="${_line#DFLOG$'\t'}"
    _kind="${_kind%%$'\t'*}"
    _line="${_line#DFLOG$'\t'}"
    _line="${_line#"${_kind}"$'\t'}"
    _min="${_line%%$'\t'*}"
    _payload="${_line#"${_min}"$'\t'}"
  elif [[ "$_line" == +* ]]; then
    _kind=X
    _min=5
    _payload="$_line"
  else
    _kind=P
    _min=4
    _payload="$_line"
  fi

  _logging__dispatch_payload "$_min" "$_payload"
  return 0
}

# ---------------------------------------------------------------------------
# Emit path
# ---------------------------------------------------------------------------

_logging__emit_at_level() {
  local _min="${1-}" _emoji="${2-}" _msg
  shift 2
  [[ $# -eq 0 ]] && return 0

  if [[ "${_LOGGING__LIB_SETUP-}" != true ]]; then
    for _msg in "$@"; do
      local _formatted="${_emoji} ${_msg}"
      _formatted="$(_logging__encode_fifo_payload "$_formatted")"
      if [[ "${_min}" -le 1 ]]; then
        if _logging__want_console_at_level "${_min}"; then
          printf '%s\n' "$_formatted" >&2
          [[ -n "${LOG_FILE:-}" ]] && _LOGGING__PARSE_BUFFER+=("${_min}"$'\t'"c"$'\t'"${_formatted}")
        elif [[ -n "${LOG_FILE:-}" ]]; then
          _LOGGING__PARSE_BUFFER+=("${_min}"$'\t'"${_formatted}")
        fi
      elif [[ -n "${LOG_FILE:-}" ]]; then
        _LOGGING__PARSE_BUFFER+=("${_min}"$'\t'"${_formatted}")
      elif _logging__want_console_at_level "${_min}"; then
        printf '%s\n' "$_formatted" >&2
      fi
    done
    return 0
  fi

  for _msg in "$@"; do
    local _formatted="${_emoji} ${_msg}"
    _formatted="$(_logging__encode_fifo_payload "$_formatted")"
    printf 'DFLOG\tS\t%s\t%s\n' "$_min" "$_formatted" >&"${_LOGGING__MUX_IN}"
  done
  return 0
}

# @brief logging__fatal <line>... — Always emitted. Prefix: ❌
logging__fatal() {
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 0 '❌' "$@"
  return 0
}

# @brief logging__error <line>... — LOG_LEVEL ≥ error. Prefix: ⛔
logging__error() {
  _logging__want_structured_at_level 1 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 1 '⛔' "$@"
  return 0
}

# @brief logging__warn <line>... — LOG_LEVEL ≥ warn. Prefix: ⚠️
logging__warn() {
  _logging__want_structured_at_level 2 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 2 '⚠️' "$@"
  return 0
}

# @brief logging__success <line>... — LOG_LEVEL ≥ info. Prefix: ✅
logging__success() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '✅' "$@"
  return 0
}

# @brief logging__info <line>... — LOG_LEVEL ≥ info. Prefix: ℹ️
logging__info() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 'ℹ️' "$@"
  return 0
}

# @brief logging__debug <line>... — LOG_LEVEL ≥ debug. Prefix: 🐞
logging__debug() {
  _logging__want_structured_at_level 4 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 4 '🐞' "$@"
  return 0
}

# @brief logging__feature_entry <feature_name>... — LOG_LEVEL ≥ info.
logging__feature_entry() {
  _logging__want_structured_at_level 3 || return 0
  _logging__emit_at_level 3 '↪️' "Script entry: $*"
  return 0
}

# @brief logging__feature_exit <feature_name>... — LOG_LEVEL ≥ info.
logging__feature_exit() {
  _logging__want_structured_at_level 3 || return 0
  _logging__emit_at_level 3 '↩️' "Script exit: $*"
  return 0
}

# @brief logging__detect <line>... — LOG_LEVEL ≥ info. Prefix: 🛠️
logging__detect() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '🛠️' "$@"
  return 0
}

# @brief logging__inspect <line>... — LOG_LEVEL ≥ info. Prefix: 🔍
logging__inspect() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '🔍' "$@"
  return 0
}

# @brief logging__install <line>... — LOG_LEVEL ≥ info. Prefix: 📦
logging__install() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '📦' "$@"
  return 0
}

# @brief logging__download <line>... — LOG_LEVEL ≥ info. Prefix: 📥
logging__download() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '📥' "$@"
  return 0
}

# @brief logging__build <line>... — LOG_LEVEL ≥ info. Prefix: 🔨
logging__build() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '🔨' "$@"
  return 0
}

# @brief logging__remove <line>... — LOG_LEVEL ≥ info. Prefix: 🗑️
logging__remove() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '🗑️' "$@"
  return 0
}

# @brief logging__clean <line>... — LOG_LEVEL ≥ info. Prefix: 🧹
logging__clean() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '🧹' "$@"
  return 0
}

# @brief logging__launch <line>... — LOG_LEVEL ≥ info. Prefix: 🚀
logging__launch() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '🚀' "$@"
  return 0
}

# @brief logging__read <line>... — LOG_LEVEL ≥ info. Prefix: 📩
logging__read() {
  _logging__want_structured_at_level 3 || return 0
  [[ $# -eq 0 ]] && return 0
  _logging__emit_at_level 3 '📩' "$@"
  return 0
}

# @brief logging__fn_entry <detail>... — LOG_LEVEL ≥ info.
logging__fn_entry() {
  _logging__want_structured_at_level 3 || return 0
  _logging__emit_at_level 3 '↪️' "Function entry: $*"
  return 0
}

# @brief logging__fn_exit <detail>... — LOG_LEVEL ≥ info.
logging__fn_exit() {
  _logging__want_structured_at_level 3 || return 0
  _logging__emit_at_level 3 '↩️' "Function exit: $*"
  return 0
}

# ---------------------------------------------------------------------------
# Mux reader / setup helpers (internal)
# ---------------------------------------------------------------------------

_logging__mux_reader_loop() {
  local _line
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    _logging__dispatch_fifo_line "$_line" || true
  done
  return 0
}

_logging__flush_parse_buffer() {
  local _rec _min _payload _rest
  for _rec in "${_LOGGING__PARSE_BUFFER[@]}"; do
    _min="${_rec%%$'\t'*}"
    _rest="${_rec#*$'\t'}"
    if [[ "$_rest" == c$'\t'* ]]; then
      _payload="${_rest#c$'\t'}"
      if [[ "${_LOGGING__CAPTURE_FILE}" == true && -n "${_LOGGING__LOG_FILE_TMP:-}" ]]; then
        if [[ "${_min}" -eq 0 ]] || [[ "${_LOGGING__FILE_LEVEL}" -ge "${_min}" ]]; then
          printf '%s\n' "$(_logging__sanitize_line "$_payload")" >> "$_LOGGING__LOG_FILE_TMP"
        fi
      fi
    else
      _payload="${_rest}"
      _logging__dispatch_payload "$_min" "$_payload"
    fi
  done
  _LOGGING__PARSE_BUFFER=()
  return 0
}

_logging__want_process_output() {
  [[ "${_LOGGING__LEVEL}" -ge 4 ]] && return 0
  [[ "${_LOGGING__CAPTURE_FILE}" == true && "${_LOGGING__FILE_LEVEL}" -ge 4 ]] && return 0
  return 1
}

_logging__want_xtrace() {
  [[ "${_LOGGING__LEVEL}" -ge 5 ]] && return 0
  [[ "${_LOGGING__CAPTURE_FILE}" == true && "${_LOGGING__FILE_LEVEL}" -ge 5 ]] && return 0
  return 1
}

_logging__configure_process_redirect() {
  if _logging__want_process_output; then
    exec 1>&"${_LOGGING__MUX_IN}" 2>&1
  else
    exec 1> /dev/null 2>&1
  fi
  return 0
}

_logging__configure_xtrace() {
  if _logging__want_xtrace; then
    export BASH_XTRACEFD="${_LOGGING__MUX_IN}"
    set -x
  else
    set +x
    unset BASH_XTRACEFD
  fi
  return 0
}

_logging__mux_stop() {
  if [[ -n "${_LOGGING__MUX_READER_PID:-}" ]]; then
    exec {_LOGGING__MUX_IN}>&- 2> /dev/null || true
    wait "${_LOGGING__MUX_READER_PID}" 2> /dev/null || true
    _LOGGING__MUX_READER_PID=
  fi
  if [[ -n "${_LOGGING__MUX_FIFO:-}" ]]; then
    rm -f "${_LOGGING__MUX_FIFO}" 2> /dev/null || true
    _LOGGING__MUX_FIFO=
  fi
  return 0
}

# @brief logging__set_level — Re-read LOG_LEVEL / LOG_FILE_LEVEL.
logging__set_level() {
  local _bad=false
  if ! _logging__recompute_level; then
    if [[ "${_LOGGING__LIB_SETUP-}" == true ]]; then
      logging__warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."
    else
      _logging__bootstrap_warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."
    fi
    _bad=true
  fi
  if ! _logging__recompute_file_level; then
    if [[ "${_LOGGING__LIB_SETUP-}" == true ]]; then
      logging__warn "Unknown LOG_FILE_LEVEL '${LOG_FILE_LEVEL:-}'; defaulting to debug."
    else
      _logging__bootstrap_warn "Unknown LOG_FILE_LEVEL '${LOG_FILE_LEVEL:-}'; defaulting to debug."
    fi
    _bad=true
  fi
  _logging__update_capture_file

  if [[ "${_LOGGING__LIB_SETUP-}" == true ]]; then
    _logging__configure_process_redirect
    _logging__configure_xtrace
  fi
  return 0
}

if ! _logging__recompute_level; then
  _logging__bootstrap_warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."
fi
if ! _logging__recompute_file_level; then
  _logging__bootstrap_warn "Unknown LOG_FILE_LEVEL '${LOG_FILE_LEVEL:-}'; defaulting to debug."
fi
_logging__update_capture_file

# @brief logging__setup — Ordered journal + FIFO mux activation.
logging__setup() {
  [[ "${_LOGGING__LIB_SETUP-}" == true ]] && return 0

  file__session_ensure
  _LOGGING__LOG_FILE_TMP="$(mktemp "${_FILE__SESSION_ROOT}/log_XXXXXX")"

  exec 3>&1 4>&2

  _LOGGING__MUX_FIFO="${_FILE__SESSION_ROOT}/mux.fifo"
  rm -f "${_LOGGING__MUX_FIFO}"
  mkfifo "${_LOGGING__MUX_FIFO}"

  (
    _logging__mux_reader_loop
  ) < "${_LOGGING__MUX_FIFO}" &
  _LOGGING__MUX_READER_PID=$!

  exec {_LOGGING__MUX_IN}> "${_LOGGING__MUX_FIFO}"

  _logging__flush_parse_buffer
  _logging__configure_process_redirect
  _logging__configure_xtrace

  _LOGGING__LIB_SETUP=true

  [[ -n "${GITHUB_TOKEN:-}" ]] && logging__mask_secret "$GITHUB_TOKEN"
  return 0
}

# @brief logging__mask_secret <value> — Redact on cleanup when writing LOG_FILE.
logging__mask_secret() {
  [[ -n "${1:-}" ]] && _LOGGING__SYSSET_MASKED_VALUES+=("$1")
  return 0
}

# @brief logging__cleanup — Drain mux, append journal to LOG_FILE, restore fds.
logging__cleanup() {
  [[ "${_LOGGING__LIB_SETUP-}" == true ]] || return 0

  set +x
  unset BASH_XTRACEFD

  exec 1>&3 2>&4

  _logging__mux_stop

  exec 3>&- 4>&-

  local _LOG_FILE_DEST="${LOG_FILE-}"
  if [[ -n "${_LOG_FILE_DEST}" && -f "${_LOGGING__LOG_FILE_TMP:-}" ]]; then
    mkdir -p "$(dirname "$_LOG_FILE_DEST")" 2> /dev/null || true
    if [[ ${#_LOGGING__SYSSET_MASKED_VALUES[@]} -gt 0 ]]; then
      local _log _v
      _log="$(cat "$_LOGGING__LOG_FILE_TMP")"
      local _mask='***'
      for _v in "${_LOGGING__SYSSET_MASKED_VALUES[@]}"; do
        [[ -n "$_v" ]] && _log="${_log//${_v}/${_mask}}"
      done
      printf '%s' "$_log" >> "$_LOG_FILE_DEST"
    else
      cat "$_LOGGING__LOG_FILE_TMP" >> "$_LOG_FILE_DEST"
    fi
  fi

  _LOGGING__LOG_FILE_TMP=
  _LOGGING__SYSSET_MASKED_VALUES=()
  _LOGGING__PARSE_BUFFER=()
  _LOGGING__CAPTURE_FILE=false
  _LOGGING__LIB_SETUP=false
  return 0
}
