# shellcheck shell=bash
# JSON query and manipulation helpers using jq (auto-installed via ospkg if absent).
#
# Functions read from stdin and write to stdout.

# _json__ensure_json_lib_dir (internal) — kept for backward compat; _JSON__LIB_DIR is always set at load time.
_json__ensure_json_lib_dir() {
  return 0
}

# _json__ensure_jq (internal) — ensure jq is on PATH; install via ospkg if absent.
_json__ensure_jq() {
  command -v jq > /dev/null 2>&1 && return 0
  logging__info "jq not found — installing."
  ospkg__install_tracked "lib-json" jq >&2 || true
  command -v jq > /dev/null 2>&1 || {
    logging__error "json.sh: jq could not be installed."
    return 1
  }
}

# @brief json__query — jq passthrough; ensures jq is available (installs via ospkg if needed).
#
# All arguments are forwarded to `jq` unchanged.
#
# Stdout: jq output.
#
# Returns: jq exit code.
json__query() {
  _json__ensure_jq || return 1
  jq "$@"
}

# @brief json__root_scalar_stdin <key> — Read one JSON object from stdin; print `.[key]` when it is a string or number.
#
# Args:
#   <key>  Top-level object key to extract.
#
# Stdout: string value of `.[key]`.
#
# Returns: 0 on success, 1 if jq is unavailable, stdin is empty, or the value is missing or non-scalar.
json__root_scalar_stdin() {
  local _key="$1" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_jq || return 1
  _out="$(printf '%s\n' "$_json" | jq -r --arg k "$_key" \
    '.[$k] | if type == "number" or type == "string" then tostring elif . == null then empty else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ] && [ "$_out" != "null" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

# @brief json__array_field_lines_stdin <field> — Read JSON from stdin (expected: top-level array); print one line per element's `.[field]` when string or number.
#
# Args:
#   <field>  Field name to extract from each array element.
#
# Stdout: one value per line.
#
# Returns: 0 on success, 1 if no values found or jq is unavailable.
json__array_field_lines_stdin() {
  local _field="$1" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_jq || return 1
  _out="$(printf '%s\n' "$_json" | jq -r --arg f "$_field" \
    'if type == "array" then .[] | .[$f] // empty | if type == "string" or type == "number" then tostring else empty end else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

# @brief json__object_array_field_lines_stdin <arrayKey> <field> — Read one JSON object from stdin; print one line per element of `.[arrayKey][].[field]` when string or number.
#
# Requires root to be an object and `.[arrayKey]` to be an array of objects.
#
# Args:
#   <arrayKey>  Key whose value is the array to iterate.
#   <field>     Field to extract from each array element.
#
# Stdout: one value per line.
#
# Returns: 0 on success, 1 if no values found or jq is unavailable.
json__object_array_field_lines_stdin() {
  local _ak="$1" _field="$2" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_jq || return 1
  _out="$(printf '%s\n' "$_json" | jq -r --arg ak "$_ak" --arg f "$_field" \
    '(.[$ak] | if type == "array" then .[] else empty end) | .[$f] // empty | if type == "string" or type == "number" then tostring else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

# @brief json__object_map_string_values_stdin [<objectKey>] — Read one JSON object from stdin; print all string values from the root object or from `.[objectKey]`.
#
# When `.[key]` may be an array of strings instead, use `json__object_key_string_lines_stdin`.
#
# Args:
#   [<objectKey>]  Optional sub-key to descend into (defaults to root object).
#
# Stdout: one string value per line.
#
# Returns: 0 on success, 1 if no values found or jq is unavailable.
json__object_map_string_values_stdin() {
  local _sub="${1-}" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_jq || return 1
  _out="$(printf '%s\n' "$_json" | jq -r --arg sk "$_sub" \
    'if ($sk | length) == 0 then
      (if type == "object" then to_entries[].value | select(type == "string") else empty end)
    else
      (.[$sk] | if type == "object" then to_entries[].value | select(type == "string") else empty end)
    end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

# @brief json__object_key_string_lines_stdin <key> — Read one JSON object from stdin; print each string from `.[key]` when that value is a JSON array of strings or an object whose values are strings (one line per string).
#
# Args:
#   <key>  Object key to read (e.g. `envs` for `conda env list --json`).
#
# Stdout: one string per line.
json__object_key_string_lines_stdin() {
  local _key="${1-}" _json _out
  [ -z "$_key" ] && return 1
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_jq || return 1
  _out="$(printf '%s\n' "$_json" | jq -r --arg k "$_key" '
    .[$k]
    | if type == "array" then .[] | strings
      elif type == "object" then .[] | strings
      else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

# @brief json__nodejs_index_version_stdin <op> [arg] — Read nodejs.org-style dist index.json (array of objects); print one version string.
#
# Args:
#   <op>   Operation: `lts-first` (first LTS entry), `head` (first entry), `major` (arg = major e.g. `22`), `exact` (arg = full version e.g. `v22.0.0`).
#   [arg]  Required for `major` and `exact` ops.
#
# Stdout: version string (e.g. `v22.0.0`).
#
# Returns: 0 on success, 1 if no matching entry found or jq is unavailable.
json__nodejs_index_version_stdin() {
  local _op="$1" _arg="${2-}" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  [ -z "$_op" ] && return 1
  _json__ensure_jq || return 1
  case "$_op" in
    lts-first)
      _out="$(printf '%s\n' "$_json" | jq -r '[.[] | select(.lts != false)][0].version // empty | strings' 2> /dev/null)" || _out=""
      ;;
    head)
      _out="$(printf '%s\n' "$_json" | jq -r '.[0].version // empty | strings' 2> /dev/null)" || _out=""
      ;;
    major)
      [ -z "$_arg" ] && return 1
      _out="$(printf '%s\n' "$_json" | jq -r --arg p "v${_arg}." \
        '.[] | select(.version | type == "string" and startswith($p)) | .version' 2> /dev/null | head -n 1)" || _out=""
      ;;
    exact)
      [ -z "$_arg" ] && return 1
      _out="$(printf '%s\n' "$_json" | jq -r --arg v "$_arg" \
        '.[] | select(.version == $v) | .version // empty' 2> /dev/null | head -n 1)" || _out=""
      ;;
    *)
      return 1
      ;;
  esac
  case "$_out" in '' | 'null') return 1 ;; esac
  printf '%s\n' "$_out"
  return 0
}

# @brief json__object_keys_stdin [<objectKey>] — Print keys of the root object or of `.[objectKey]`; one key per line.
#
# Args:
#   [<objectKey>]  Optional sub-key to descend into (defaults to root object).
#
# Stdout: one key per line.
#
# Returns: 0 on success, 1 if jq is unavailable or input is not an object.
json__object_keys_stdin() {
  local _sub="${1-}" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_jq || return 1
  if [ -z "$_sub" ]; then
    _out="$(printf '%s\n' "$_json" | jq -r 'keys[]' 2> /dev/null)" || return 1
  else
    _out="$(printf '%s\n' "$_json" | jq -r --arg sk "$_sub" '.[$sk] | if type == "object" then keys[] else empty end' 2> /dev/null)" || return 1
  fi
  [ -n "$_out" ] && printf '%s\n' "$_out"
  return 0
}

# @brief json__value_stdin <jq-expr> — Read JSON from stdin; print compact value at `<jq-expr>`.
#
# Args:
#   <jq-expr>  jq expression to evaluate (e.g. `.name`, `.features`).
#
# Stdout: compact JSON value at the given path.
#
# Returns: 0 on success, 1 if jq is unavailable or expression is empty.
json__value_stdin() {
  local _expr="${1-}" _json
  [ -z "$_expr" ] && return 1
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_jq || return 1
  printf '%s\n' "$_json" | jq -c "$_expr" 2> /dev/null
}

# @brief json__coerce_scalar_stdin — Read one JSON scalar from stdin; print its string form for use in environment variables.
#
# Booleans and numbers are converted via `jq tostring`; strings are printed raw; null prints an empty line. Objects and arrays return 1.
#
# Stdout: string representation of the scalar value.
#
# Returns: 0 on success, 1 for objects, arrays, or jq errors.
json__coerce_scalar_stdin() {
  local _json _t
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_jq || return 1
  _t="$(printf '%s\n' "$_json" | jq -r 'type' 2> /dev/null)" || return 1
  case "$_t" in
    string)
      printf '%s\n' "$_json" | jq -r '.'
      return 0
      ;;
    number | boolean)
      printf '%s\n' "$_json" | jq -r 'tostring'
      return 0
      ;;
    "null")
      printf '\n'
      return 0
      ;;
    object | array) return 1 ;;
    *) return 1 ;;
  esac
}
