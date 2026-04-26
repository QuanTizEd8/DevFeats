#!/usr/bin/env bash
# proc.sh — parallel / devcontainer-style command values. Bash >=4. Requires json.sh (jq via json__query); requires os.sh when using --user.
[[ -n "${_PROC__LIB_LOADED-}" ]] && return 0
_PROC__LIB_LOADED=1

_PROC__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json.sh
. "$_PROC__LIB_DIR/json.sh"
# shellcheck source=lib/logging.sh
. "$_PROC__LIB_DIR/logging.sh"

# @brief proc__run_parallel — --outdir <dir> -- <label> <argv...> [-- <label> <argv> ...]
proc__run_parallel() {
  local _od="" _cwd=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --outdir)
        _od="${2-}"
        shift 2
        ;;
      --cwd)
        _cwd="${2-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        logging__error "proc__run_parallel: use --outdir and --"
        return 1
        ;;
    esac
  done
  [[ -n "$_od" ]] || _od="$(mktemp -d)"
  mkdir -p "$_od" || return 1
  local -a _rest=("$@") _argv=() _pids=() _labs=()
  local _lab _i _r _ec=0
  while ((${#_rest[@]} > 0)); do
    _lab="${_rest[0]}"
    _rest=("${_rest[@]:1}")
    _argv=()
    while ((${#_rest[@]} > 0)) && [[ "${_rest[0]}" != -- ]]; do
      _argv+=("${_rest[0]}")
      _rest=("${_rest[@]:1}")
    done
    [[ ${#_rest[@]} -gt 0 && "${_rest[0]}" == -- ]] && _rest=("${_rest[@]:1}")
    ((${#_argv[@]} == 0)) && continue
    _labs+=("$_lab")
    (
      if [[ -n "$_cwd" ]]; then
        cd "$_cwd" && "${_argv[@]}" > "${_od}/${_lab}.out" 2>&1
      else
        "${_argv[@]}" > "${_od}/${_lab}.out" 2>&1
      fi
      echo $? > "${_od}/${_lab}.ec"
    ) &
    _pids+=($!)
  done
  for _i in "${!_pids[@]}"; do
    wait "${_pids[$_i]}" || true
  done
  for _i in "${!_labs[@]}"; do
    _lab="${_labs[$_i]}"
    read -r _r < "${_od}/${_lab}.ec" 2> /dev/null || _r=0
    ((_r != 0 && _ec == 0)) && _ec=$_r
  done
  for _lab in "${_labs[@]}"; do
    [[ -f "${_od}/${_lab}.out" ]] && cat "${_od}/${_lab}.out"
  done
  return "$_ec"
}

# @brief proc__run_command_form [--cwd d] [--user u] — JSON from stdin. string → sh -c; array → direct exec; object → proc__run_parallel (keys = labels).
proc__run_command_form() {
  local _cwd="" _user="" _json
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd)
        _cwd="${2-}"
        shift 2
        ;;
      --user)
        _user="${2-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  _json="$(cat)"
  [[ -n "$_json" ]] || return 1
  _json__ensure_jq || return 1
  local _t _s _k _v _ty _od
  _t="$(printf '%s' "$_json" | json__query -r 'type' 2> /dev/null)" || return 1

  _rc() {
    if [[ -n "$_user" ]]; then
      if ! command -v os__run_as > /dev/null 2>&1; then
        logging__error "proc__run_command_form: --user requires os.sh (os__run_as)"
        return 1
      fi
      if [[ -n "$_cwd" ]]; then
        os__run_as "$_user" --cwd "$_cwd" -- "$@"
      else
        os__run_as "$_user" -- "$@"
      fi
    elif [[ -n "$_cwd" ]]; then
      (cd "$_cwd" && "$@")
    else
      "$@"
    fi
  }

  case "$_t" in
    string)
      _s="$(printf '%s' "$_json" | json__query -r '.')"
      _rc /bin/sh -c "$_s"
      ;;
    array)
      mapfile -t _av < <(printf '%s' "$_json" | json__query -r '.[]' 2> /dev/null) || return 1
      ((${#_av[@]} > 0)) || return 1
      _rc "${_av[@]}"
      ;;
    object)
      _od="$(mktemp -d)"
      local -a _pl=() _e=0 _first=1
      while IFS= read -r _k; do
        [[ -z "$_k" ]] && continue
        # shellcheck disable=SC2016
        _v="$(printf '%s' "$_json" | json__query -c --arg k "$_k" '.[$k]')" || continue
        _ty="$(printf '%s' "$_v" | json__query -r 'type' 2> /dev/null)" || continue
        [[ "$_first" -eq 0 ]] && _pl+=(--)
        _first=0
        if [[ "$_ty" == string ]]; then
          _s="$(printf '%s' "$_v" | json__query -r '.')"
          _pl+=("$_k" /bin/sh -c "$_s")
        elif [[ "$_ty" == array ]]; then
          mapfile -t _av2 < <(printf '%s' "$_v" | json__query -r '.[]' 2> /dev/null) || continue
          _pl+=("$_k" "${_av2[@]}")
        else
          logging__error "proc__run_command_form: object values must be string or array"
          rm -rf "$_od"
          return 1
        fi
      done < <(printf '%s' "$_json" | json__query -r 'keys[]' 2> /dev/null)
      ((${#_pl[@]} == 0)) && {
        rm -rf "$_od"
        return 0
      }
      local -a _pargs=()
      [[ -n "$_cwd" ]] && _pargs+=(--cwd "$_cwd")
      proc__run_parallel --outdir "$_od" "${_pargs[@]}" -- "${_pl[@]}"
      _e=$?
      rm -rf "$_od"
      return "$_e"
      ;;
    *)
      logging__error "proc__run_command_form: not string/array/object"
      return 1
      ;;
  esac
}
