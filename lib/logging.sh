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
# Call logging__feature_entry before argument parsing; call logging__setup once options
# are final (re-reads levels, starts mux, replays pending journal). logging__set_level
# remains available for mid-run level changes after setup. On EXIT call logging__cleanup
# then file__session_cleanup (installer template __exit__ calls logging__on_early_exit first).
#
# Reserved fds after logging__setup: 3=stdout, 4=stderr, 5=process mux, 6=xtrace pipe (when trace on).
# Requires lib/file.sh and lib/logging-api.sh (loaded by __init__.bash; order vs api does not matter).
# Registers the bash logging backend for logging-api.sh dispatch hooks.

_LOGGING__BASH_BACKEND=1
_LOGGING__FN_PREFIX=${_LOGGING__FN_PREFIX:-1}
_LOGGING__LIB_SETUP=false
_LOGGING__SYSSET_MASKED_VALUES=()

_LOGGING__LOG_FILE_TMP=
_LOGGING__CAPTURE_FILE=false
_LOGGING__MUX_FIFO=
_LOGGING__MUX_READER_PID=
_LOGGING__MUX_IN=5
_LOGGING__PROC_MUX=0
_LOGGING__XTRACE_PIPE=
_LOGGING__ERR_IN_TRAP=0

# LOG_LEVEL / LOG_FILE_LEVEL numeric thresholds
_LOGGING__LEVEL=3
_LOGGING__FILE_LEVEL=4

# ---------------------------------------------------------------------------
# Function-name message prefix (bash caller stack)
# ---------------------------------------------------------------------------

_logging__caller_fn() {
  local _i _fn
  for ((_i = 1; _i < ${#FUNCNAME[@]}; _i++)); do
    _fn="${FUNCNAME[_i]}"
    case "$_fn" in
      logging__* | _logging__* | '')
        continue
        ;;
      *)
        printf '%s' "$_fn"
        return 0
        ;;
    esac
  done
  return 1
}

_logging__decorate_fn_prefix() {
  local _msg="${1-}" _fn
  [[ "${_LOGGING__FN_PREFIX:-0}" == 1 ]] || {
    printf '%s' "$_msg"
    return 0
  }
  _fn="$(_logging__caller_fn)" || {
    printf '%s' "$_msg"
    return 0
  }
  case "$_msg" in
    "${_fn}: "* | "${_fn}:"*)
      printf '%s' "$_msg"
      return 0
      ;;
  esac
  printf '%s: %s' "$_fn" "$_msg"
  return 0
}

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

_logging__encode_fifo_payload() {
  _logging__encode_payload "${1-}"
}

# Forward one DFLOG record directly to the mux fifo.
# Writing to fd 1 (process-ingress) instead would race with large subprocess writes
# (apt-get, curl) that exceed PIPE_BUF, interleaving DFLOG bytes mid-line — exactly
# the same reason the xtrace coprocess was changed to write to _LOGGING__MUX_IN directly.
# Payload is capped at 4081 bytes: "DFLOG\tS\t4\t" (12 bytes) + 4081 + "\n" (1) = 4094 ≤ PIPE_BUF.
_logging__mux_forward_dflog() {
  local _kind="$1" _min="$2" _payload="$3"
  printf 'DFLOG\t%s\t%s\t%.4081s\n' "$_kind" "$_min" "$_payload" >&"${_LOGGING__MUX_IN}"
  return 0
}

# Process-ingress coprocess: wrap plain lines as DFLOG O; pass DFLOG records through.
# The encoded payload is capped at 4081 bytes so the total printf write fits in one
# PIPE_BUF (4096 bytes on Linux), keeping the write atomic. Non-atomic writes on the
# mux FIFO race with concurrent S-record writes from the main shell and corrupt lines.
_logging__process_mux_ingress() {
  local _line="${1-}"
  if [[ "$_line" == DFLOG$'\t'* ]]; then
    # Cap at 4092 bytes total (DFLOG record including its own PIPE_BUF header).
    printf '%.4092s\n' "$_line" >&"${_LOGGING__MUX_IN}"
  else
    local _enc
    _enc="$(_logging__encode_fifo_payload "$_line")"
    printf 'DFLOG\tO\t4\t%.4081s\n' "$_enc" >&"${_LOGGING__MUX_IN}"
  fi
  return 0
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

# @brief _logging__dispatch_payload <min_level> <payload_line>
# Write one line to console and/or session journal per sink thresholds.
_logging__dispatch_payload() {
  local _min="${1-}" _payload="${2-}"
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
    if [[ "${_LOGGING__LIB_SETUP-}" == true ]]; then
      printf '%s\n' "$_payload" >&4
    else
      printf '%s\n' "$_payload" >&2
    fi
  fi
  if [[ "${_to_file}" == true && -n "${_LOGGING__LOG_FILE_TMP:-}" ]]; then
    printf '%s\n' "$_payload" >> "$_LOGGING__LOG_FILE_TMP"
  fi
  return 0
}

# Parse DFLOG\\tkind\\tmin\\tpayload on the process mux.
# Kinds: S=structured, X=xtrace, O=subprocess stdout/stderr (line-buffered).
# Legacy unprefixed lines are still accepted as process output (min=debug).
_logging__dispatch_mux_line() {
  local _line="${1-}"
  [[ -z "$_line" ]] && return 0

  local _kind _min _payload
  if [[ "$_line" == DFLOG$'\t'* ]]; then
    _kind="${_line#DFLOG$'\t'}"
    _kind="${_kind%%$'\t'*}"
    _line="${_line#DFLOG$'\t'}"
    _line="${_line#"${_kind}"$'\t'}"
    _min="${_line%%$'\t'*}"
    _payload="${_line#"${_min}"$'\t'}"
  else
    _min=4
    _payload="$_line"
  fi

  _logging__dispatch_payload "$_min" "$_payload"
  return 0
}

# Bash-specific override: replace tab/newline/CR with spaces using parameter
# expansion instead of tr pipelines. Avoids spawning subprocesses under set -x,
# which would generate extra xtrace records when trace level is active.
_logging__encode_payload() {
  local _log_enc_in="${1-}"
  _log_enc_in="${_log_enc_in//$'\t'/ }"
  _log_enc_in="${_log_enc_in//$'\n'/ }"
  _log_enc_in="${_log_enc_in//$'\r'/ }"
  printf '%s' "$_log_enc_in"
}

# ---------------------------------------------------------------------------
# Bash emit backend (hooks consumed by logging-api.sh; do not redefine api hooks)
# ---------------------------------------------------------------------------

_logging__bash_structured() {
  local _min="${1-}" _emoji="${2-}"
  shift 2
  [[ $# -eq 0 ]] && return 0
  _logging__want_structured_at_level "${_min}" || return 0
  _logging__bash_emit "${_min}" "${_emoji}" "$@"
  return 0
}

_logging__bash_emit() {
  local _min="${1-}" _emoji="${2-}" _msg _formatted
  shift 2
  [[ $# -eq 0 ]] && return 0
  if [[ "${_min}" -ne 0 ]]; then
    _logging__want_structured_at_level "${_min}" || return 0
  fi
  for _msg in "$@"; do
    _msg="$(_logging__format_msg "$_msg")"
    _formatted="${_emoji} ${_msg}"
    _formatted="$(_logging__encode_fifo_payload "$_formatted")"
    _logging__mux_forward_dflog S "$_min" "$_formatted"
  done
  return 0
}

# ---------------------------------------------------------------------------
# Mux reader / setup helpers (internal)
# ---------------------------------------------------------------------------

_logging__mux_reader_loop() {
  local _line
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    _logging__dispatch_mux_line "$_line" || true
  done
  return 0
}

_logging__replay_pending_line() {
  local _min="${1-}" _payload="${2-}"
  _payload="$(_logging__prefix_payload "$_payload")"
  if [[ "${_LOGGING__LIB_SETUP-}" == true ]]; then
    _logging__mux_forward_dflog S "$_min" "$(_logging__encode_fifo_payload "$_payload")"
  else
    _logging__dispatch_payload "$_min" "$_payload"
  fi
  return 0
}

_logging__foreach_pending_record() {
  local _line _min _rest _payload
  [[ -n "${_LOGGING__PENDING_FILE:-}" && -f "${_LOGGING__PENDING_FILE}" ]] || return 0
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    [[ -z "$_line" ]] && continue
    _min="${_line%%$'\t'*}"
    _rest="${_line#*$'\t'}"
    if [[ "$_rest" == c$'\t'* ]]; then
      _payload="${_rest#c$'\t'}"
      _payload="$(_logging__prefix_payload "$_payload")"
      if [[ "${_LOGGING__CAPTURE_FILE}" == true && -n "${_LOGGING__LOG_FILE_TMP:-}" ]]; then
        if [[ "${_min}" -eq 0 ]] || [[ "${_LOGGING__FILE_LEVEL}" -ge "${_min}" ]]; then
          printf '%s\n' "$_payload" >> "$_LOGGING__LOG_FILE_TMP"
        fi
      fi
    else
      _payload="${_rest}"
      _logging__replay_pending_line "$_min" "$_payload"
    fi
  done < "${_LOGGING__PENDING_FILE}"
  return 0
}

_logging__clear_pending_file() {
  if [[ -n "${_LOGGING__PENDING_FILE:-}" && -f "${_LOGGING__PENDING_FILE}" ]]; then
    rm -f "${_LOGGING__PENDING_FILE}"
  fi
  unset _LOGGING__PENDING_FILE
  _LOGGING__PENDING_FLUSHED=true
  return 0
}

_logging__flush_pending_buffer() {
  [[ "${_LOGGING__PENDING_FLUSHED:-}" == true ]] && return 0
  [[ -n "${_LOGGING__PENDING_FILE:-}" && -f "${_LOGGING__PENDING_FILE}" ]] || {
    _LOGGING__PENDING_FLUSHED=true
    return 0
  }
  _logging__foreach_pending_record
  _logging__clear_pending_file
  return 0
}

_logging__finalize_pending_buffer() {
  [[ "${_LOGGING__PENDING_FLUSHED:-}" == true ]] && return 0
  [[ -n "${_LOGGING__PENDING_FILE:-}" && -f "${_LOGGING__PENDING_FILE}" ]] || return 0

  logging__set_level
  file__session_ensure

  local _dest="${LOG_FILE-}"
  if [[ -n "${_dest}" ]]; then
    _LOGGING__LOG_FILE_TMP="$(mktemp "${_FILE__SESSION_ROOT}/log_XXXXXX")"
  fi

  _logging__foreach_pending_record
  _logging__clear_pending_file

  if [[ -n "${_dest}" && -f "${_LOGGING__LOG_FILE_TMP:-}" ]]; then
    mkdir -p "$(dirname "$_dest")" 2> /dev/null || true
    if [[ ${#_LOGGING__SYSSET_MASKED_VALUES[@]} -gt 0 ]]; then
      local _log _v
      _log="$(cat "$_LOGGING__LOG_FILE_TMP")"
      local _mask='***'
      for _v in "${_LOGGING__SYSSET_MASKED_VALUES[@]}"; do
        [[ -n "$_v" ]] && _log="${_log//${_v}/${_mask}}"
      done
      printf '%s' "$_log" >> "$_dest"
    else
      cat "$_LOGGING__LOG_FILE_TMP" >> "$_dest"
    fi
    _LOGGING__LOG_FILE_TMP=
  fi
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
    # Line-buffer subprocess output and frame as DFLOG O records. Structured logs
    # write directly to _LOGGING__MUX_IN to avoid racing with large subprocess writes.
    _LOGGING__PROC_MUX=1
    exec 1> >(
      while IFS= read -r _line || [[ -n "${_line}" ]]; do
        _logging__process_mux_ingress "$_line"
      done
    ) 2>&1
  else
    _LOGGING__PROC_MUX=0
    exec 1> /dev/null 2>&1
  fi
  return 0
}

_logging__close_xtrace_pipe() {
  set +x
  unset BASH_XTRACEFD
  if [[ -n "${_LOGGING__XTRACE_PIPE:-}" ]]; then
    exec {_LOGGING__XTRACE_PIPE}>&- 2> /dev/null || true
    _LOGGING__XTRACE_PIPE=
  fi
  return 0
}

_logging__configure_xtrace() {
  _logging__close_xtrace_pipe
  if _logging__want_xtrace; then
    PS4='+ '
    export PS4
    exec {_LOGGING__XTRACE_PIPE}> >(
      while IFS= read -r _line || [[ -n "${_line}" ]]; do
        # Write to the mux fifo directly — not process-ingress fd 1, which apt/PM
        # stderr shares; concurrent writers there interleave raw DFLOG into output.
        # Cap at 4081 bytes (PIPE_BUF=4096 minus 10-byte prefix minus \n) for atomicity.
        local _xenc
        _xenc="$(_logging__encode_fifo_payload "$_line")"
        printf 'DFLOG\tX\t5\t%.4081s\n' "$_xenc" >&"${_LOGGING__MUX_IN}"
      done
    )
    export BASH_XTRACEFD="${_LOGGING__XTRACE_PIPE}"
    set -x
  fi
  return 0
}

_logging__mux_stop() {
  _logging__close_xtrace_pipe
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
  if ! _logging__recompute_level; then
    if [[ "${_LOGGING__LIB_SETUP-}" == true ]]; then
      logging__warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."
    else
      _logging__bootstrap_warn "Unknown LOG_LEVEL '${LOG_LEVEL:-}'; defaulting to info."
    fi
  fi
  if ! _logging__recompute_file_level; then
    if [[ "${_LOGGING__LIB_SETUP-}" == true ]]; then
      logging__warn "Unknown LOG_FILE_LEVEL '${LOG_FILE_LEVEL:-}'; defaulting to debug."
    else
      _logging__bootstrap_warn "Unknown LOG_FILE_LEVEL '${LOG_FILE_LEVEL:-}'; defaulting to debug."
    fi
  fi
  _logging__update_capture_file

  if [[ "${_LOGGING__LIB_SETUP-}" == true ]]; then
    _logging__configure_process_redirect
    _logging__configure_xtrace
  fi
  return 0
}

# @brief logging__finalize_parse_buffer — Replay pending journal on early exit (no mux).
logging__finalize_parse_buffer() {
  _logging__finalize_pending_buffer
  return 0
}

# @brief logging__err_unhandled <rc> — ERR trap helper (called from install __err__).
#
# Log a generic line for unhandled non-__ command failures after logging__setup.
# Return 0: trap handler should return (intentional [[ predicate).
# Return 1: trap handler should exit with <rc>.
logging__err_unhandled() {
  local _rc="$1"
  if ((_LOGGING__ERR_IN_TRAP)); then
    return 1
  fi
  case "${BASH_COMMAND}" in
    *\[\[*)
      return 0
      ;;
    return\ * | *'__'*)
      return 1
      ;;
  esac
  _LOGGING__ERR_IN_TRAP=1
  logging__error "command failed (exit ${_rc}): ${BASH_COMMAND}"
  return 1
}

# @brief logging__on_early_exit — Finalize pending journal; return 0 if logging__setup ran.
logging__on_early_exit() {
  _logging__finalize_pending_buffer
  [[ "${_LOGGING__LIB_SETUP-}" == true ]]
}

# @brief logging__setup [--prefix <id>] [--fn-prefix] [--no-fn-prefix] — Start mux; replay pending journal.
logging__setup() {
  [[ "${_LOGGING__LIB_SETUP-}" == true ]] && return 0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix)
        shift
        logging__set_prefix "${1-}"
        shift
        ;;
      --fn-prefix)
        logging__set_fn_prefix 1
        shift
        ;;
      --no-fn-prefix)
        logging__set_fn_prefix 0
        shift
        ;;
      *)
        logging__warn "ignoring unknown option '${1}'"
        shift
        ;;
    esac
  done

  logging__set_level
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

  _LOGGING__LIB_SETUP=true
  _logging__configure_process_redirect
  _logging__flush_pending_buffer
  [[ -n "${GITHUB_TOKEN:-}" ]] && logging__mask_secret "$GITHUB_TOKEN"
  _logging__configure_xtrace
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

  _LOGGING__ERR_IN_TRAP=0

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
  _LOGGING__PENDING_FLUSHED=false
  _LOGGING__CAPTURE_FILE=false
  _LOGGING__LIB_SETUP=false
  _LOGGING__PROC_MUX=0
  _LOGGING__PREFIX=
  _LOGGING__FN_PREFIX=0
  return 0
}
