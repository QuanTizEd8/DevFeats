# shellcheck shell=bash
# Unified condition context: flat registry (os.*, plat.*, feat.*), pattern expand, when eval via jq.

declare -gA _CTX__REGISTRY=()
declare -g _CTX__REGISTRY_INITIALIZED=false
declare -g _CTX__OS_RELEASE_FILE=""
declare -g _CTX__LIB_DIR
_CTX__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_ctx__quiet=false

_ctx__fail() {
  [[ "${_ctx__quiet}" == true ]] || logging__error "$1"
  return 1
}

ctx__reset() {
  _CTX__REGISTRY=()
  _CTX__REGISTRY_INITIALIZED=false
}

ctx__set() {
  # @brief ctx__set <qualified>=<value> … — Sole write API for the context registry.
  local _pair _k _v
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    _CTX__REGISTRY["${_k}"]="${_v}"
  done
}

ctx__parse_key() {
  # @brief ctx__parse_key <qualified> — Print namespace, key_part, case_flavor (pattern expand only).
  local _q="$1" _ns _rest _flavor=""
  [[ "${_q}" == *.* ]] || return 1
  _ns="${_q%%.*}"
  _rest="${_q#*.}"
  case "${_rest}" in
    *:upper | *:lower | *:title)
      _flavor="${_rest##*:}"
      _rest="${_rest%:*}"
      ;;
  esac
  printf '%s\n' "${_ns}" "${_rest}" "${_flavor}"
}

ctx__get() {
  # @brief ctx__get <base-qualified> — Lookup stored value; missing → empty. No flavor suffix.
  local _key="$1"
  case "${_key}" in
    *:upper | *:lower | *:title) return 0 ;;
  esac
  _ctx__ensure_registry
  printf '%s' "${_CTX__REGISTRY[$_key]:-}"
}

ctx__pairs() {
  local _k
  for _k in "${!_CTX__REGISTRY[@]}"; do
    printf '%s=%s\n' "${_k}" "${_CTX__REGISTRY[$_k]}"
  done
}

ctx__json() {
  _ctx__ensure_registry
  local _k _pairs=()
  for _k in "${!_CTX__REGISTRY[@]}"; do
    _pairs+=("${_k}" "${_CTX__REGISTRY[$_k]}")
  done
  if ((${#_pairs[@]} == 0)); then
    printf '{}'
    return 0
  fi
  # shellcheck disable=SC2016  # $i and $[] are jq variables, not bash
  printf '%s\n' "${_pairs[@]}" |
    json__query -Rn '[inputs] | [range(0; length; 2) as $i | {key: .[$i], value: .[$i + 1]}] | from_entries'
}

_ctx__id_like_tokens() {
  local _s="${1:-}" _tok
  _s="${_s#"${_s%%[![:space:]]*}"}"
  _s="${_s%"${_s##*[![:space:]]}"}"
  [[ -n "${_s}" ]] || return 0
  for _tok in ${_s}; do
    printf '%s\n' "${_tok,,}"
  done
}

_ctx__id_like_has() {
  local _want="${1,,}" _actual="$2" _tok
  while IFS= read -r _tok; do
    [[ -n "${_tok}" && "${_tok}" == "${_want}" ]] && return 0
  done < <(_ctx__id_like_tokens "${_actual}")
  return 1
}

_ctx__compare_eq() {
  local _key="$1" _expected="$2" _actual="$3"
  if [[ "${_key}" == "os.id_like" ]]; then
    if [[ "${_expected}" == *"|"* ]]; then
      local _alt _matched=false
      IFS='|' read -ra _alts <<< "${_expected}"
      for _alt in "${_alts[@]}"; do
        _ctx__id_like_has "${_alt}" "${_actual}" && {
          _matched=true
          break
        }
      done
      [[ "${_matched}" == true ]]
      return $?
    fi
    _ctx__id_like_has "${_expected}" "${_actual}"
    return $?
  fi
  if [[ "${_expected}" == *"|"* ]]; then
    local _alt
    IFS='|' read -ra _alts <<< "${_expected}"
    for _alt in "${_alts[@]}"; do
      [[ "${_actual,,}" == "${_alt,,}" ]] && return 0
    done
    return 1
  fi
  [[ "${_actual,,}" == "${_expected,,}" ]]
}

_ctx__compare_ne() {
  local _key="$1" _expected="$2" _actual="$3"
  if [[ "${_key}" == "os.id_like" ]]; then
    if [[ "${_expected}" == *"|"* ]]; then
      local _alt
      IFS='|' read -ra _alts <<< "${_expected}"
      for _alt in "${_alts[@]}"; do
        _ctx__id_like_has "${_alt}" "${_actual}" && return 1
      done
      return 0
    fi
    _ctx__id_like_has "${_expected}" "${_actual}" && return 1
    return 0
  fi
  if [[ "${_expected}" == *"|"* ]]; then
    local _alt
    IFS='|' read -ra _alts <<< "${_expected}"
    for _alt in "${_alts[@]}"; do
      [[ "${_actual,,}" == "${_alt,,}" ]] && return 1
    done
    return 0
  fi
  [[ "${_actual,,}" != "${_expected,,}" ]]
}

ctx__compare() {
  # @brief ctx__compare <key> <op> <expected> — Compare registry value (eq|ne|lt|lte|gt|gte).
  local _key="$1" _op="$2" _expected="$3"
  local _actual
  _actual="$(ctx__get "${_key}")"
  case "${_op}" in
    eq) _ctx__compare_eq "${_key}" "${_expected}" "${_actual}" ;;
    ne) _ctx__compare_ne "${_key}" "${_expected}" "${_actual}" ;;
    lt | lte | gt | gte)
      [[ "${_key}" == "os.id_like" ]] && return 1
      local _cmp
      _cmp="$(ver__cmp "${_actual}" "${_expected}")" || return 1
      case "${_op}" in
        lt) [[ "${_cmp}" -lt 0 ]] ;;
        lte) [[ "${_cmp}" -le 0 ]] ;;
        gt) [[ "${_cmp}" -gt 0 ]] ;;
        gte) [[ "${_cmp}" -ge 0 ]] ;;
      esac
      ;;
    *)
      _ctx__fail "unsupported op '${_op}'."
      return 1
      ;;
  esac
}

_ctx__apply_case_flavor() {
  local _flavor="$1" _value="$2"
  case "${_flavor}" in
    upper) printf '%s' "${_value^^}" ;;
    lower) printf '%s' "${_value,,}" ;;
    title)
      [[ -z "${_value}" ]] && return 0
      local _first="${_value:0:1}"
      printf '%s%s' "${_first^^}" "${_value:1}"
      ;;
    *) printf '%s' "${_value}" ;;
  esac
}

_ctx__load_linux_os() {
  local _file="${_CTX__OS_RELEASE_FILE:-/etc/os-release}"
  if [[ ! -f "${_file}" ]]; then
    return 0
  fi
  local _key _val _qkey
  while IFS='=' read -r _key _val; do
    [[ -z "${_key-}" || "${_key}" =~ ^# ]] && continue
    _val="${_val#\"}"
    _val="${_val%\"}"
    _val="${_val#\'}"
    _val="${_val%\'}"
    _qkey="os.${_key,,}"
    ctx__set "${_qkey}=${_val}"
  done < "${_file}"
  local _vid="${_CTX__REGISTRY["os.version_id"]:-}"
  if [[ -n "${_vid}" ]]; then
    ctx__set "os.version_id_major=${_vid%%.*}"
    if [[ "${_vid}" == *.*.* ]]; then
      ctx__set "os.version_id_mm=${_vid%.*}"
    else
      ctx__set "os.version_id_mm=${_vid}"
    fi
  fi
}

_ctx__load_darwin_os() {
  local _name _vid _build _extra
  _name="$(sw_vers -productName 2> /dev/null || true)"
  _vid="$(sw_vers -productVersion 2> /dev/null || true)"
  _build="$(sw_vers -buildVersion 2> /dev/null || true)"
  _extra="$(sw_vers -productVersionExtra 2> /dev/null || true)"
  ctx__set os.id=macos
  ctx__set os.id_like=macos
  ctx__set "os.name=${_name}"
  ctx__set "os.version_id=${_vid}"
  ctx__set "os.build_id=${_build}"
  ctx__set "os.version_extra=${_extra}"
  if [[ -n "${_name}" && -n "${_vid}" ]]; then
    ctx__set "os.version=${_name} ${_vid}"
  elif [[ -n "${_name}" ]]; then
    ctx__set "os.version=${_name}"
  fi
  if [[ -n "${_vid}" ]]; then
    ctx__set "os.version_id_major=${_vid%%.*}"
    if [[ "${_vid}" == *.*.* ]]; then
      ctx__set "os.version_id_mm=${_vid%.*}"
    else
      ctx__set "os.version_id_mm=${_vid}"
    fi
  fi
}

_ctx__populate_plat() {
  local _v
  ctx__set "plat.kernel=$(os__kernel)"
  ctx__set "plat.machine=$(os__arch)"
  ctx__set "plat.platform=$(os__platform)"
  _v="$(os__release_arch 2> /dev/null || os__arch)"
  ctx__set "plat.machine_release=${_v}"
  _v="$(os__release_kernel gh 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.kernel_gh=${_v}"; fi
  _v="$(os__release_kernel macos 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.kernel_macos=${_v}"; fi
  _v="$(os__release_kernel osx 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.kernel_osx=${_v}"; fi
  _v="$(os__release_arch --flavor gh 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.machine_gh=${_v}"; fi
  _v="$(os__release_arch --flavor node 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.machine_node=${_v}"; fi
  _v="$(os__release_arch --flavor bitness 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.machine_bitness=${_v}"; fi
  _v="$(os__rust_triple 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.rust_triple=${_v}"; fi
  _v="$(os__libc 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.libc=${_v}"; fi
}

_ctx__ensure_registry() {
  [[ "${_CTX__REGISTRY_INITIALIZED}" == true ]] && return 0
  case "$(uname -s)" in
    Darwin) _ctx__load_darwin_os ;;
    *) _ctx__load_linux_os ;;
  esac
  _ctx__populate_plat
  if ospkg__detect; then
    ctx__set "plat.pm=${_OSPKG__PM_KEY:-}"
    [[ -n "${_OSPKG__DEB_ARCH:-}" ]] && ctx__set "plat.deb_arch=${_OSPKG__DEB_ARCH}"
  else
    ctx__set plat.pm=""
  fi
  _CTX__REGISTRY_INITIALIZED=true
}

_ctx__eval_pattern_cond() {
  local _cond="$1"
  [[ "${_cond}" =~ ^([^=!<>]+)(==|!=|>=|>|<=|<)(.+)$ ]] || return 1
  local _key="${BASH_REMATCH[1]}" _sym="${BASH_REMATCH[2]}" _val="${BASH_REMATCH[3]}"
  local _op=""
  case "${_sym}" in
    '==') _op=eq ;;
    '!=') _op=ne ;;
    '>=') _op=gte ;;
    '>') _op=gt ;;
    '<=') _op=lte ;;
    '<') _op=lt ;;
  esac
  ctx__compare "${_key}" "${_op}" "${_val}"
}

_ctx__eval_pattern_token() {
  local _tok="$1"
  local _cond _tbranch _fbranch _parsed _ns _part _flavor _base _val
  if str__split_conditional "${_tok}" _cond _tbranch _fbranch; then
    if _ctx__eval_pattern_cond "${_cond}"; then
      _ctx__expand_pattern "${_tbranch}"
    else
      _ctx__expand_pattern "${_fbranch}"
    fi
    return
  fi
  mapfile -t _parsed < <(ctx__parse_key "${_tok}" 2> /dev/null || true)
  if ((${#_parsed[@]} >= 2)); then
    _ns="${_parsed[0]}"
    _part="${_parsed[1]}"
    _flavor="${_parsed[2]:-}"
    _base="${_ns}.${_part}"
    if [[ ! -v _CTX__REGISTRY["${_base}"] ]]; then
      printf '{%s}' "${_tok}"
      return 0
    fi
    _val="$(ctx__get "${_base}")"
    if [[ -n "${_flavor}" ]]; then
      _val="$(_ctx__apply_case_flavor "${_flavor}" "${_val}")"
    fi
    printf '%s' "${_val}"
    return 0
  fi
  printf '{%s}' "${_tok}"
}

_ctx__expand_pattern() {
  local _s="$1"
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
      _expanded="$(_ctx__eval_pattern_token "${_tok}")"
      _result+="${_expanded}"
      _i=$((_i + _cpos + 2))
    else
      _result+="${_c}"
      _i=$((_i + 1))
    fi
  done
  printf '%s' "${_result}"
}

ctx__expand_pattern() {
  # @brief ctx__expand_pattern <pattern> — Expand qualified {…} tokens and conditionals.
  _ctx__ensure_registry
  _ctx__expand_pattern "$1"
}

_ctx__yaml_to_json() {
  local _yaml="$1" _yq
  bootstrap__yq > /dev/null || return 1
  _yq="$(bootstrap__yq)"
  printf '%s' "${_yaml}" | "${_yq}" -o=json '.' -
}

_ctx__eval_when_jq() {
  local _yaml="$1"
  local _ctx_json _when_json _result
  _ctx_json="$(ctx__json)"
  _when_json="$(_ctx__yaml_to_json "${_yaml}")" || return 1
  _result="$(json__query -L "${_CTX__LIB_DIR}" --argjson ctx "${_ctx_json}" --argjson when "${_when_json}" \
    -n -f "${_CTX__LIB_DIR}/ctx-when-eval.jq" 2> /dev/null)" || return 1
  [[ "${_result}" == "true" ]]
}

ctx__match_spec() {
  # @brief ctx__match_spec [--quiet] <yaml-and-group> — Return 0 if the AND group matches.
  _ctx__quiet=false
  [[ "${1:-}" == --quiet ]] && {
    _ctx__quiet=true
    shift
  }
  local _yaml="${1:-}"
  [[ -z "${_yaml}" ]] && return 0
  _ctx__ensure_registry
  _ctx__eval_when_jq "${_yaml}"
}

ctx__match_when() {
  # @brief ctx__match_when [--quiet] <yaml-when> — Return 0 if any OR group matches.
  _ctx__quiet=false
  [[ "${1:-}" == --quiet ]] && {
    _ctx__quiet=true
    shift
  }
  local _yaml="${1:-}"
  [[ -z "${_yaml}" ]] && return 0
  _ctx__ensure_registry
  _ctx__eval_when_jq "${_yaml}"
}

ctx__select_first() {
  # @brief ctx__select_first [--quiet] -- [<yaml-group>] [-- [<yaml-group>] …]
  _ctx__quiet=false
  [[ "${1:-}" == --quiet ]] && {
    _ctx__quiet=true
    shift
  }
  [[ "${1:-}" == "--" ]] || {
    _ctx__fail "ctx__select_first requires leading '--'."
    return 1
  }
  shift
  local -a _group=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      if [[ ${#_group[@]} -gt 0 ]] && ctx__match_spec "${_group[0]}"; then
        return 0
      fi
      _group=()
      shift
      continue
    fi
    _group+=("$1")
    shift
  done
  [[ ${#_group[@]} -gt 0 ]] && ctx__match_spec "${_group[0]}"
}
