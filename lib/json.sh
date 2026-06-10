# shellcheck shell=bash
# JSON query and manipulation helpers using jq (auto-installed via ospkg if absent).
#
# Functions read from stdin and write to stdout.

_json__ensure_json_lib_dir() {
  # _json__ensure_json_lib_dir (internal) — kept for backward compat; _JSON__LIB_DIR is always set at load time.
  return 0
}

json__query() {
  # @brief json__query — jq passthrough; ensures jq is available (installs via ospkg if needed).
  #
  # All arguments are forwarded to `jq` unchanged.
  #
  # Stdout: jq output.
  #
  # Returns: jq exit code.
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required for JSON query."
    return "$_rc"
  }
  jq "$@"
}

_json__root_scalar_stdin() {
  # _json__root_scalar_stdin (internal) — silent probe; no logging on failure.
  local _key="$1" _json _out
  _json="$(cat)" || return 1
  [ -n "$_json" ] || return 1
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || return "$_rc"
  _out="$(printf '%s\n' "$_json" | jq -r --arg k "$_key" \
    '.[$k] | if type == "number" or type == "string" then tostring elif . == null then empty else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ] && [ "$_out" != "null" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

json__root_scalar_stdin() {
  # @brief json__root_scalar_stdin <key> — Read one JSON object from stdin; print `.[key]` when it is a string or number.
  #
  # Args:
  #   <key>  Top-level object key to extract.
  #
  # Stdout: string value of `.[key]`.
  #
  # Returns: 0 on success, 1 if jq is unavailable, stdin is empty, or the value is missing or non-scalar.
  local _key="$1"
  _json__root_scalar_stdin "$_key"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "root scalar '${_key}' not found or not a string/number."
    return "$_rc"
  }
}

json__array_field_lines_stdin() {
  # @brief json__array_field_lines_stdin <field> — Read JSON from stdin (expected: top-level array); print one line per element's `.[field]` when string or number.
  #
  # Args:
  #   <field>  Field name to extract from each array element.
  #
  # Stdout: one value per line.
  #
  # Returns: 0 on success, 1 if no values found or jq is unavailable.
  local _field="$1" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read array field '${_field}'."
    return "$_rc"
  }
  _out="$(printf '%s\n' "$_json" | jq -r --arg f "$_field" \
    'if type == "array" then .[] | .[$f] // empty | if type == "string" or type == "number" then tostring else empty end else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  logging__error "no values found for array field '${_field}'."
  return 1
}

json__object_array_field_lines_stdin() {
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
  local _ak="$1" _field="$2" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read '${_ak}[].${_field}'."
    return "$_rc"
  }
  _out="$(printf '%s\n' "$_json" | jq -r --arg ak "$_ak" --arg f "$_field" \
    '(.[$ak] | if type == "array" then .[] else empty end) | .[$f] // empty | if type == "string" or type == "number" then tostring else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  logging__error "no values found for '${_ak}[].${_field}'."
  return 1
}

json__object_map_string_values_stdin() {
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
  local _sub="${1-}" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read object string values."
    return "$_rc"
  }
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
  logging__error "no string values found in JSON object."
  return 1
}

json__object_key_string_lines_stdin() {
  # @brief json__object_key_string_lines_stdin <key> — Read one JSON object from stdin; print each string from `.[key]` when that value is a JSON array of strings or an object whose values are strings (one line per string).
  #
  # Args:
  #   <key>  Object key to read (e.g. `envs` for `conda env list --json`).
  #
  # Stdout: one string per line.
  local _key="${1-}" _json _out
  [ -z "$_key" ] && {
    logging__error "object key is required."
    return 1
  }
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read object key '${_key}'."
    return "$_rc"
  }
  _out="$(printf '%s\n' "$_json" | jq -r --arg k "$_key" '
    .[$k]
    | if type == "array" then .[] | strings
      elif type == "object" then .[] | strings
      else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  logging__error "no string values found for object key '${_key}'."
  return 1
}

json__nodejs_index_version_stdin() {
  # @brief json__nodejs_index_version_stdin <op> [arg] — Read nodejs.org-style dist index.json (array of objects); print one version string.
  #
  # Args:
  #   <op>   Operation: `lts-first` (first LTS entry), `head` (first entry), `major` (arg = major e.g. `22`), `exact` (arg = full version e.g. `v22.0.0`).
  #   [arg]  Required for `major` and `exact` ops.
  #
  # Stdout: version string (e.g. `v22.0.0`).
  #
  # Returns: 0 on success, 1 if no matching entry found or jq is unavailable.
  local _op="$1" _arg="${2-}" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  [ -z "$_op" ] && {
    logging__error "nodejs index operation is required."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read nodejs index JSON."
    return "$_rc"
  }
  case "$_op" in
    lts-first)
      _out="$(printf '%s\n' "$_json" | jq -r '[.[] | select(.lts != false)][0].version // empty | strings' 2> /dev/null)" || _out=""
      ;;
    head)
      _out="$(printf '%s\n' "$_json" | jq -r '.[0].version // empty | strings' 2> /dev/null)" || _out=""
      ;;
    major)
      [ -z "$_arg" ] && {
        logging__error "major version argument is required for nodejs index lookup."
        return 1
      }
      _out="$(printf '%s\n' "$_json" | jq -r --arg p "v${_arg}." \
        '.[] | select(.version | type == "string" and startswith($p)) | .version' 2> /dev/null | head -n 1)" || _out=""
      ;;
    exact)
      [ -z "$_arg" ] && {
        logging__error "exact version argument is required for nodejs index lookup."
        return 1
      }
      _out="$(printf '%s\n' "$_json" | jq -r --arg v "$_arg" \
        '.[] | select(.version == $v) | .version // empty' 2> /dev/null | head -n 1)" || _out=""
      ;;
    *)
      logging__error "unsupported nodejs index operation '${_op}'."
      return 1
      ;;
  esac
  case "$_out" in '' | 'null')
    logging__error "no matching nodejs version found for operation '${_op}'."
    return 1
    ;;
  esac
  printf '%s\n' "$_out"
  return 0
}

json__object_keys_stdin() {
  # @brief json__object_keys_stdin [<objectKey>] — Print keys of the root object or of `.[objectKey]`; one key per line.
  #
  # Args:
  #   [<objectKey>]  Optional sub-key to descend into (defaults to root object).
  #
  # Stdout: one key per line.
  #
  # Returns: 0 on success, 1 if jq is unavailable or input is not an object.
  local _sub="${1-}" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read object keys."
    return "$_rc"
  }
  if [ -z "$_sub" ]; then
    _out="$(printf '%s\n' "$_json" | jq -r 'keys[]' 2> /dev/null)" || {
      logging__error "failed to read root object keys."
      return 1
    }
  else
    _out="$(printf '%s\n' "$_json" | jq -r --arg sk "$_sub" '.[$sk] | if type == "object" then keys[] else empty end' 2> /dev/null)" || {
      logging__error "failed to read keys for object '${_sub}'."
      return 1
    }
  fi
  [ -n "$_out" ] && printf '%s\n' "$_out"
  return 0
}

json__value_stdin() {
  # @brief json__value_stdin <jq-expr> — Read JSON from stdin; print compact value at `<jq-expr>`.
  #
  # Args:
  #   <jq-expr>  jq expression to evaluate (e.g. `.name`, `.features`).
  #
  # Stdout: compact JSON value at the given path.
  #
  # Returns: 0 on success, 1 if jq is unavailable or expression is empty.
  local _expr="${1-}" _json
  [ -z "$_expr" ] && {
    logging__error "jq expression is required."
    return 1
  }
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to evaluate expression '${_expr}'."
    return "$_rc"
  }
  printf '%s\n' "$_json" | jq -c "$_expr" 2> /dev/null
}

json__coerce_scalar_stdin() {
  # @brief json__coerce_scalar_stdin — Read one JSON scalar from stdin; print its string form for use in environment variables.
  #
  # Booleans and numbers are converted via `jq tostring`; strings are printed raw; null prints an empty line. Objects and arrays return 1.
  #
  # Stdout: string representation of the scalar value.
  #
  # Returns: 0 on success, 1 for objects, arrays, or jq errors.
  local _json _t
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to coerce JSON scalar."
    return "$_rc"
  }
  _t="$(printf '%s\n' "$_json" | jq -r 'type' 2> /dev/null)" || {
    logging__error "failed to determine JSON value type."
    return 1
  }
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
    object | array)
      logging__error "JSON value is not a scalar (type=${_t})."
      return 1
      ;;
    *)
      logging__error "unsupported JSON value type '${_t}'."
      return 1
      ;;
  esac
}
