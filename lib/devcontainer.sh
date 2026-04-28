#!/usr/bin/env bash
# devcontainer.sh — devcontainer.json glue for install.bash (JSONC, workspace, feature filter, env exports, disable globs).
# Bash >=4. Source: json str graph proc (optional: os, users) after path setup.
[[ -n "${_DEVCONTAINER__LIB_LOADED-}" ]] && return 0
_DEVCONTAINER__LIB_LOADED=1

_DEVCONTAINER__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/logging.sh
. "$_DEVCONTAINER__LIB_DIR/logging.sh"

# shellcheck source=lib/json.sh disable=SC1091
[[ -n "${_JSON__LIB_LOADED-}" ]] || { _j="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/json.sh" && . "$_j" || return 1; }
# shellcheck source=lib/str.sh disable=SC1091
[[ -n "${_STR__LIB_LOADED-}" ]] || { _j="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/str.sh" && . "$_j" || return 1; }

# shellcheck disable=SC2034
_DEVCONTAINER_LIFECYCLE_PHASES=(onCreateCommand updateContentCommand postCreateCommand postStartCommand postAttachCommand)

devcontainer__is_registry_host_like() {
  local _host="${1-}"
  [[ -n "$_host" ]] || return 1
  [[ "$_host" == "localhost" || "$_host" =~ ^localhost:[0-9]+$ ]] && return 0
  [[ "$_host" == *.* ]] && return 0
  [[ "$_host" =~ ^\[[0-9A-Fa-f:.]+\](:[0-9]+)?$ ]] && return 0
  return 1
}

# @brief devcontainer__parse_config <file> — print normalized JSON to stdout; return 1 on error.
devcontainer__parse_config() {
  local _f="${1-}"
  [[ -f "$_f" ]] || return 1
  # shellcheck disable=SC2119  # called with stdin redirect, not positional args
  json__detect_duplicate_keys_stdin < "$_f" || return 1
  json__strip_jsonc_stdin < "$_f" || return 1
  return 0
}

# @brief devcontainer__workspace_folder <config-path> — print workspace realpath.
devcontainer__workspace_folder() {
  local _f="${1-}" _d _r
  [[ -f "$_f" ]] || return 1
  _d="$(cd "$(dirname "$_f")" 2> /dev/null && pwd -P 2> /dev/null || pwd 2> /dev/null)" || return 1
  _r="$_d"
  while [[ "$_r" == *'/.devcontainer'* ]]; do
    _r="$(dirname "$_r")"
  done
  # shellcheck disable=SC2001
  if [[ -z "$_r" || "$_r" == / ]]; then
    echo "/"
  else
    echo "$_r"
  fi
  return 0
}

# @brief devcontainer__name_version_suffix <name-string>
devcontainer__name_version_suffix() {
  str__extract_version_suffix "${1-}"
  return 0
}

# @brief devcontainer__oci_id_and_tag <oci-key> — line1: id (no tag), line2: tag or empty
devcontainer__oci_id_and_tag() {
  local _k="${1-}" _rest _t _id
  _rest="${_k##*/}"
  if [[ "$_rest" == *":"* ]]; then
    _id="${_rest%%:*}"
    _t="${_rest#*:}"
  else
    _id="$_rest"
    _t=""
  fi
  echo "$_id"
  echo "$_t"
  return 0
}

# @brief devcontainer__is_compatible_key <key> <prefix> ... — 0 if OCI key matches a prefix, or a local path with devcontainer-feature.json
devcontainer__is_compatible_key() {
  local _k="${1-}"
  local _host
  shift
  local _p
  for _p in "$@"; do
    [[ -n "$_p" && "$_k" == "$_p"* ]] && return 0
  done
  if [[ "$_k" == ./* || "$_k" == ../* || "$_k" == /* ]]; then
    local _d
    _d="${_k%/devcontainer-feature.json}"
    if [[ -f "${_d}/devcontainer-feature.json" ]]; then
      return 0
    fi
    if [[ -d "$_d" && -f "${_d}/devcontainer-feature.json" ]]; then
      return 0
    fi
  fi
  if [[ "$_k" == */* && ( "$_k" == *@sha256:* || "$_k" == *:* ) ]]; then
    _host="${_k%%/*}"
    devcontainer__is_registry_host_like "$_host" && return 0
  fi
  return 1
}

# @brief devcontainer__lifecycle_disabled <entry> <scope> <featureId> <phase> [<cmdname>]
# Returns 0 if this lifecycle entry should be skipped. scope=feature|container
# Grammar (option (c) in plan §1.2.6):
#   all                               → always match
#   <phase>                           → bare phase (authoritative when name matches)
#   <phase>:<cmd>                     → phase + named object-form sub-command
#   <featureId>                       → feature-scope match (ignored at container scope)
#   <featureId>:<phase>               → feature-scope match (ignored at container scope)
#   <featureId>:<phase>:<cmd>         → feature-scope match for a named object-form command
# Caller is expected to call this only for entries that belong to the relevant
# flag (feature flag vs container flag); ambiguous forms are already constrained
# by the caller's scope.
devcontainer__lifecycle_disabled() {
  local _e="${1-}" _sc="${2-}" _fid="${3-}" _ph="${4-}" _cn="${5-}"
  [[ -z "$_e" ]] && return 1
  if [[ "$_e" == "all" ]]; then
    return 0
  fi
  local _p _is_phase=0
  for _p in "${_DEVCONTAINER_LIFECYCLE_PHASES[@]+"${_DEVCONTAINER_LIFECYCLE_PHASES[@]}"}"; do
    if [[ "$_e" == "$_p" ]]; then
      _is_phase=1
      [[ "$_e" == "$_ph" ]] && return 0
      return 1
    fi
    if [[ "$_e" == "${_p}:${_cn}" && -n "$_cn" && "$_p" == "$_ph" ]]; then
      return 0
    fi
  done
  ((_is_phase)) && return 1
  if [[ "$_e" == "$_fid" ||
    "$_e" == "${_fid}:${_ph}" ||
    ("$_e" == "${_fid}:${_ph}:${_cn}" && -n "$_cn") ]]; then
    [[ "$_sc" == container ]] && return 1
    return 0
  fi
  return 1
}

# @brief devcontainer__iter_features <config-file> <workspace-folder> <compat-prefix>...
# Emits TAB-delimited lines: <id>\t<key>\t<tag>
# - <id>   the trailing path component without :tag suffix
# - <key>  the raw features[] key
# - <tag>  the :tag suffix after the last ':' in the last segment, or empty
# Keys that don't match any prefix and aren't a resolvable local path → warned + skipped.
devcontainer__iter_features() {
  local _cfg="${1-}" _wf="${2-}"
  shift 2 || return 1
  local -a _prefixes=("$@")
  [[ -f "$_cfg" ]] || return 1
  local _k _p _hit _id _tag _rest _full _host
  while IFS= read -r _k; do
    [[ -z "$_k" ]] && continue
    _hit=0
    for _p in "${_prefixes[@]+"${_prefixes[@]}"}"; do
      [[ -n "$_p" && "$_k" == "$_p"* ]] && {
        _hit=1
        break
      }
    done
    if ((_hit == 0)); then
      case "$_k" in
        ./* | ../* | /*)
          _full="$_k"
          [[ "$_full" != /* && -n "$_wf" ]] && _full="${_wf%/}/${_k}"
          if [[ -f "${_full%/}/devcontainer-feature.json" || -f "${_full}/devcontainer-feature.json" ]]; then
            _hit=1
          fi
          ;;
      esac
    fi
    if ((_hit == 0)); then
      if [[ "$_k" == */* && ( "$_k" == *@sha256:* || "$_k" == *:* ) ]]; then
        _host="${_k%%/*}"
        devcontainer__is_registry_host_like "$_host" && _hit=1
      fi
    fi
    ((_hit == 0)) && {
      logging__warn "skip feature key (not sysset-compatible): $_k"
      continue
    }
    _rest="${_k##*/}"
    if [[ "$_rest" == *":"* ]]; then
      _id="${_rest%%:*}"
      _tag="${_rest#*:}"
    else
      _id="$_rest"
      _tag=""
    fi
    printf '%s\t%s\t%s\n' "$_id" "$_k" "$_tag"
  done < <(json__query -r '(.features // {}) | keys[]' < "$_cfg")
  return 0
}

# @brief devcontainer__feature_env_exports <opts-json-stdin> <safe-id-prefix-or-empty>
# Reads a JSON object on stdin; emits `export KEY=VALUE` lines suitable for eval.
# Values are coerced via json__coerce_scalar_stdin; arrays/objects fail.
# Bash %q quoting preserves newlines, tabs, and non-ASCII characters verbatim.
devcontainer__feature_env_exports() {
  local _j _k _t _v _n
  _j="$(cat)"
  [[ -z "$_j" || "$_j" == "{}" || "$_j" == "null" ]] && return 0
  while IFS= read -r _k; do
    [[ -z "$_k" ]] && continue
    # shellcheck disable=SC2016
    _t="$(printf '%s' "$_j" | json__query -r --arg k "$_k" '.[$k] | type' 2> /dev/null)" || return 1
    if [[ "$_t" == "array" || "$_t" == "object" ]]; then
      logging__error "Option '${_k}': only boolean/string allowed by devcontainer spec (got ${_t})"
      return 1
    fi
    # shellcheck disable=SC2016
    _v="$(printf '%s' "$_j" | json__query -c --arg k "$_k" '.[$k]')"
    _v="$(printf '%s' "$_v" | json__coerce_scalar_stdin 2> /dev/null)" || return 1
    _n="$(str__safe_id "$_k")"
    printf 'export %s=%q\n' "$_n" "$_v"
  done < <(printf '%s' "$_j" | json__query -r 'keys[]' 2> /dev/null)
  return 0
}

# @brief devcontainer__build_ordering_inputs --hard-edges-file F --soft-edges-file F \
#     --priority-file F --staged-root D --config-file F -- <id>...
# Writes graph__round_order input files.
# - hard edges derive from each feature's `dependsOn` (keys map back to staged ids).
# - soft edges derive from `installsAfter` (missing targets ignored by graph__round_order).
# - priority reflects `overrideFeatureInstallOrder`: first entry gets highest score.
devcontainer__build_ordering_inputs() {
  local _hf="" _sf="" _pf="" _root="" _cfg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hard-edges-file)
        _hf="${2-}"
        shift 2
        ;;
      --soft-edges-file)
        _sf="${2-}"
        shift 2
        ;;
      --priority-file)
        _pf="${2-}"
        shift 2
        ;;
      --staged-root)
        _root="${2-}"
        shift 2
        ;;
      --config-file)
        _cfg="${2-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  local -a _ids=("$@")
  [[ -n "$_hf" && -n "$_sf" && -n "$_pf" && -n "$_root" && -n "$_cfg" ]] || {
    logging__error "devcontainer__build_ordering_inputs: missing flag"
    return 1
  }
  : > "$_hf"
  : > "$_sf"
  : > "$_pf"
  local _id _dep _short _hit _legacy
  local -A _alias_to_id=()
  for _id in "${_ids[@]+"${_ids[@]}"}"; do
    local _df0="${_root}/${_id}/devcontainer-feature.json"
    [[ -f "$_df0" ]] || continue
    _alias_to_id["$_id"]="$_id"
    while IFS= read -r _legacy; do
      [[ -z "$_legacy" ]] && continue
      _alias_to_id["$_legacy"]="$_id"
    done < <(json__query -r '(.legacyIds // [])[]' "$_df0" 2> /dev/null || true)
  done
  for _id in "${_ids[@]+"${_ids[@]}"}"; do
    local _df="${_root}/${_id}/devcontainer-feature.json"
    [[ -f "$_df" ]] || continue
    while IFS= read -r _dep; do
      [[ -z "$_dep" ]] && continue
      _short="${_dep##*/}"
      _short="${_short%%:*}"
      _short="${_short%%@*}"
      _hit=0
      if [[ -n "${_alias_to_id[$_short]+x}" ]]; then
        printf '%s\t%s\n' "${_alias_to_id[$_short]}" "$_id" >> "$_hf"
        _hit=1
      fi
    done < <(json__query -r '(.dependsOn // {}) | keys[]' "$_df" 2> /dev/null || true)
    while IFS= read -r _dep; do
      [[ -z "$_dep" ]] && continue
      _short="${_dep##*/}"
      _short="${_short%%:*}"
      _short="${_short%%@*}"
      if [[ -n "${_alias_to_id[$_short]+x}" ]]; then
        printf '%s\t%s\n' "${_alias_to_id[$_short]}" "$_id" >> "$_sf"
      fi
    done < <(json__query -r '(.installsAfter // [])[]' "$_df" 2> /dev/null || true)
  done
  local _oi=0 _entry _eshort
  while IFS= read -r _entry; do
    [[ -z "$_entry" ]] && continue
    _eshort="${_entry##*/}"
    _eshort="${_eshort%%:*}"
    _eshort="${_eshort%%@*}"
    if [[ -n "${_alias_to_id[$_eshort]+x}" ]]; then
      printf '%s\t%d\n' "${_alias_to_id[$_eshort]}" "$((1000000 - _oi))" >> "$_pf"
    fi
    _oi=$((_oi + 1))
  done < <(json__query -r '(.overrideFeatureInstallOrder // [])[]' "$_cfg" 2> /dev/null || true)
  return 0
}

# @brief devcontainer__lifecycle_iter --config-file F --staged-root D --phase P -- <id>...
# Emits lines: <scope>\t<id>\t<cmd-json>
# - scope is "feature" for feature-level commands, "container" for devcontainer.json
# - id is the feature id for feature scope, or "_container_" for container scope
# - cmd-json is compact JSON (one line) — string/array/object form
# Features iterated in provided order; container-level entry is emitted last.
devcontainer__lifecycle_iter() {
  local _cfg="" _root="" _ph=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config-file)
        _cfg="${2-}"
        shift 2
        ;;
      --staged-root)
        _root="${2-}"
        shift 2
        ;;
      --phase)
        _ph="${2-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  local -a _ids=("$@")
  [[ -n "$_ph" ]] || return 1
  _json__ensure_jq || return 1
  local _id _df _j
  for _id in "${_ids[@]+"${_ids[@]}"}"; do
    _df="${_root}/${_id}/devcontainer-feature.json"
    [[ -f "$_df" ]] || continue
    # shellcheck disable=SC2016
    _j="$(json__query -c --arg p "$_ph" 'if (has($p) | not) then empty else .[$p] end' "$_df" 2> /dev/null)" || continue
    [[ -z "$_j" || "$_j" == "null" ]] && continue
    printf 'feature\t%s\t%s\n' "$_id" "$_j"
  done
  if [[ -n "$_cfg" && -f "$_cfg" ]]; then
    # shellcheck disable=SC2016
    _j="$(json__query -c --arg p "$_ph" 'if (has($p) | not) then empty else .[$p] end' "$_cfg" 2> /dev/null)" || _j=""
    if [[ -n "$_j" && "$_j" != "null" ]]; then
      printf 'container\t_container_\t%s\n' "$_j"
    fi
  fi
  return 0
}

# @brief devcontainer__user_home <user>
# Prints the resolved home directory for <user>, or empty if unresolvable.
# Uses getent (Linux) then dscl (macOS) then eval-tilde as a last resort.
devcontainer__user_home() {
  local _u="${1-}"
  [[ -z "$_u" ]] && return 1
  local _h=""
  if command -v getent > /dev/null 2>&1; then
    _h="$(getent passwd "$_u" 2> /dev/null | cut -d: -f6 | head -1)" || _h=""
  fi
  if [[ -z "$_h" ]] && command -v dscl > /dev/null 2>&1; then
    _h="$(dscl . -read "/Users/${_u}" NFSHomeDirectory 2> /dev/null | awk '/^NFSHomeDirectory:/{print $2}')" || _h=""
  fi
  if [[ -z "$_h" ]]; then
    _h="$(eval "printf '%s' ~${_u}" 2> /dev/null)" || _h=""
    [[ "$_h" == "~${_u}" ]] && _h=""
  fi
  [[ -n "$_h" ]] && printf '%s' "$_h"
  return 0
}
