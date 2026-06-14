# shellcheck shell=bash
# String and path utilities: safe identifiers, prefix operations, version extraction.
#
# Provides helpers for safe identifier conversion, basename extraction, prefix
# stripping, and version suffix parsing. All functions write results to stdout,
# one item per line.

str__basename_each() {
  # @brief str__basename_each [<path-token>...] — For each argument, strip spaces and print basename on its own line.
  #
  # Intended for path-like tokens (e.g. `owner/repo` slugs). Built-in names
  # without `/` still pass through basename (e.g. `git` → `git`).
  #
  # Args:
  #   <path-token>...  One token per argument; pass a bash array as `"${arr[@]}"`.
  #
  # Stdout: one basename per line.
  local _tok
  for _tok in "$@"; do
    _tok="${_tok// /}"
    [ -n "$_tok" ] && basename "$_tok"
  done
  return 0
}

str__safe_id() {
  # @brief str__safe_id <s> — Convert a feature option key to an env var name: uppercase, `_` preserved, `-` → `_`.
  #
  # Args:
  #   <s>  Input string (e.g. `my-option`).
  #
  # Stdout: uppercased env var name (e.g. `MY_OPTION`).
  local s="${1-}"
  s="${s//-/_}"
  echo "${s^^}"
  return 0
}

str__has_any_prefix() {
  # @brief str__has_any_prefix <s> <prefix>... — Return 0 if `<s>` starts with any of the given prefixes.
  #
  # Args:
  #   <s>         String to test.
  #   <prefix>... One or more prefix strings to check.
  local s="${1-}"
  shift || {
    logging__error "at least one prefix is required."
    return 1
  }
  local _p
  for _p in "$@"; do
    if [[ -n "$_p" && "$s" == "$_p"* ]]; then
      return 0
    fi
  done
  return 1
}

str__strip_any_prefix() {
  # @brief str__strip_any_prefix <s> <prefix>... — Print `<s>` with the first-matching leading prefix removed; if none match, print `<s>` unchanged.
  #
  # Args:
  #   <s>         Input string.
  #   <prefix>... One or more prefix strings to try removing.
  #
  # Stdout: the modified or original string.
  local s="${1-}"
  shift
  local _p
  for _p in "$@"; do
    if [[ -n "$_p" && "$s" == "$_p"* ]]; then
      echo "${s#"${_p}"}"
      return 0
    fi
  done
  echo "$s"
  return 0
}

str__rsplit_once() {
  # @brief str__rsplit_once <s> <sep> — Print two lines: text before the last occurrence of `<sep>`, then text after it.
  #
  # If `<sep>` is absent from `<s>`, prints `<s>` on the first line and an empty line.
  #
  # Args:
  #   <s>    Input string.
  #   <sep>  Separator string.
  #
  # Stdout: two lines — the head and the tail.
  local s="${1-}" sep="${2-}" _head _rest _sfx
  if [[ -z "$sep" ]]; then
    printf '%s\n' "$s"
    echo ""
    return 0
  fi
  if [[ "$s" != *"$sep"* ]]; then
    printf '%s\n' "$s"
    echo ""
    return 0
  fi
  # Avoid nested "${s%"$sep"*"}" (breaks shell quote parsing in some versions).
  _sfx="${sep}*"
  # shellcheck disable=SC2295  # unquoted intentionally — see comment above
  _head="${s%$_sfx}"
  # shellcheck disable=SC2295
  _rest="${s#$_head}"
  _rest="${_rest#"$sep"}"
  printf '%s\n' "$_head"
  printf '%s\n' "$_rest"
  return 0
}

str__substitute_tokens() {
  # @brief str__substitute_tokens <pattern> <KEY=VALUE>... — Replace `{KEY}` placeholders in `<pattern>` with their values.
  #
  # Token syntax is `{KEY}` (curly braces, no dollar sign). Tokens not present
  # in the substitution list are left unchanged.
  #
  # Args:
  #   <pattern>      Input string containing zero or more `{KEY}` tokens.
  #   <KEY=VALUE>... One or more substitution pairs in `KEY=VALUE` form.
  #
  # Stdout: the pattern with all matching tokens replaced.
  local _result="$1"
  shift
  local _pair
  for _pair in "$@"; do
    _result="${_result//\{${_pair%%=*}\}/${_pair#*=}}"
  done
  printf '%s\n' "$_result"
  return 0
}

str__find_close_brace() {
  # @brief str__find_close_brace <str> — Print the 0-based index of the `}` that closes
  # the `{` preceding `<str>` (i.e. `<str>` begins just after an opening `{`).
  # Returns 1 if no matching brace is found.
  #
  # Args:
  #   <str>  The substring beginning immediately after the opening `{`.
  #
  # Stdout: decimal index of the matching `}` within `<str>`.
  # Returns: 0 on success, 1 if the brace is unmatched.
  local _s="$1" _depth=1 _i=0
  while [[ ${_i} -lt ${#_s} ]]; do
    case "${_s:${_i}:1}" in
      '{') _depth=$((_depth + 1)) ;;
      '}')
        _depth=$((_depth - 1))
        [[ ${_depth} -eq 0 ]] && {
          printf '%d' "${_i}"
          return 0
        }
        ;;
    esac
    _i=$((_i + 1))
  done
  return 1
}

str__split_conditional() {
  # @brief str__split_conditional <token> <cond_var> <true_var> <false_var>
  # Split a `COND?TRUE:FALSE` string at the first depth-0 `?` and subsequent depth-0 `:`.
  # Populates the three caller-supplied name-ref variables.
  # Returns 1 if no depth-0 `?` exists (token is not a conditional).
  #
  # Args:
  #   <token>     Token content (without surrounding `{}`).
  #   <cond_var>  Name of caller variable to receive the condition string.
  #   <true_var>  Name of caller variable to receive the true branch.
  #   <false_var> Name of caller variable to receive the false branch.
  #
  # Returns: 0 if a conditional was found and parsed; 1 otherwise.
  local _tok="$1"
  local -n _sc_cond="$2" _sc_true="$3" _sc_false="$4"
  local _i=0 _depth=0 _qpos=-1 _cpos=-1
  while [[ ${_i} -lt ${#_tok} ]]; do
    case "${_tok:${_i}:1}" in
      '{') _depth=$((_depth + 1)) ;;
      '}') _depth=$((_depth - 1)) ;;
      '?') [[ ${_depth} -eq 0 ]] && {
        _qpos=${_i}
        break
      } ;;
    esac
    _i=$((_i + 1))
  done
  [[ ${_qpos} -eq -1 ]] && return 1
  _sc_cond="${_tok:0:${_qpos}}"
  local _rest="${_tok:$((_qpos + 1))}"
  _i=0
  _depth=0
  while [[ ${_i} -lt ${#_rest} ]]; do
    case "${_rest:${_i}:1}" in
      '{') _depth=$((_depth + 1)) ;;
      '}') _depth=$((_depth - 1)) ;;
      ':') [[ ${_depth} -eq 0 ]] && {
        _cpos=${_i}
        break
      } ;;
    esac
    _i=$((_i + 1))
  done
  [[ ${_cpos} -eq -1 ]] && return 1
  _sc_true="${_rest:0:${_cpos}}"
  _sc_false="${_rest:$((_cpos + 1))}"
  return 0
}

_str__eval_condition() {
  # _str__eval_condition <COND> <KEY=VALUE>... — Evaluate one condition against the key-value list.
  # Supported: KEY==VALUE, KEY!=VALUE, KEY>=VALUE, KEY<VALUE.
  # Returns 0 if the condition is true, 1 if false or if the key is unknown.
  # For >= and <, values are compared with ver__semver_ge.
  local _cond="$1"
  shift
  [[ "${_cond}" =~ ^([^=!<>]+)(==|!=|>=|<)(.+)$ ]] || return 1
  local _key="${BASH_REMATCH[1]}" _op="${BASH_REMATCH[2]}" _val="${BASH_REMATCH[3]}"
  local _pair _actual="" _found=false
  for _pair in "$@"; do
    if [[ "${_pair%%=*}" == "${_key}" ]]; then
      _actual="${_pair#*=}"
      _found=true
      break
    fi
  done
  [[ "${_found}" == true ]] || return 1
  case "${_op}" in
    '==') [[ "${_actual}" == "${_val}" ]] ;;
    '!=') [[ "${_actual}" != "${_val}" ]] ;;
    '>=') ver__semver_ge "${_actual}" "${_val}" ;;
    '<')  ! ver__semver_ge "${_actual}" "${_val}" ;;
  esac
}

_str__eval_token() {
  # _str__eval_token <TOKEN> <KEY=VALUE>... — Expand one {…} block against the key-value list.
  # Handles COND?TRUE:FALSE conditionals (with recursive branch expansion) and plain lookups.
  # Unknown tokens are emitted as '{TOKEN}' (unchanged).
  local _tok="$1"
  shift
  local _cond _tbranch _fbranch
  if str__split_conditional "${_tok}" _cond _tbranch _fbranch; then
    if _str__eval_condition "${_cond}" "$@"; then
      str__expand_pattern "${_tbranch}" "$@"
    else
      str__expand_pattern "${_fbranch}" "$@"
    fi
    return
  fi
  local _pair
  for _pair in "$@"; do
    if [[ "${_pair%%=*}" == "${_tok}" ]]; then
      printf '%s' "${_pair#*=}"
      return 0
    fi
  done
  printf '{%s}' "${_tok}"
  return 0
}

str__expand_pattern() {
  # @brief str__expand_pattern <pattern> [<KEY=VALUE>...] — Expand `{KEY}` tokens and nestable conditionals in `<pattern>`.
  #
  # Token syntax: `{KEY}` for plain substitution; `{KEY OP VALUE?TRUE:FALSE}` for
  # conditionals where OP ∈ `==`, `!=`, `>=`, `<`. Branches may themselves contain any
  # token form (fully nestable). For `>=` and `<`, values are compared with `ver__semver_ge`.
  # Unknown keys in plain tokens are emitted unchanged as `{KEY}`. Unknown keys in conditions
  # are treated as false. Unmatched `{` characters pass through literally.
  #
  # Args:
  #   <pattern>      Input string containing zero or more `{KEY}` tokens.
  #   <KEY=VALUE>... Substitution pairs; first match wins for a given KEY.
  #
  # Stdout: the fully expanded string without trailing newline.
  local _s="$1"
  shift
  local -a _kvs=("$@")
  local _result="" _i=0 _len="${#_s}"
  while [[ ${_i} -lt ${_len} ]]; do
    local _c="${_s:${_i}:1}"
    if [[ "${_c}" == '{' ]]; then
      local _after="${_s:$((_i + 1))}"
      local _cpos _brace_rc
      _cpos="$(str__find_close_brace "${_after}")"
      _brace_rc=$?
      if [[ ${_brace_rc} -ne 0 ]]; then
        _result+='{'
        _i=$((_i + 1))
        continue
      fi
      local _tok="${_after:0:${_cpos}}"
      local _expanded
      _expanded="$(_str__eval_token "${_tok}" "${_kvs[@]}")"
      _result+="${_expanded}"
      _i=$((_i + _cpos + 2))
    else
      _result+="${_c}"
      _i=$((_i + 1))
    fi
  done
  printf '%s' "${_result}"
  return 0
}
