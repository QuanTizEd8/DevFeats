#!/usr/bin/env bash
# Devcontainer JSON helpers: parse configs, resolve features, export env vars, compute install ordering.
#
# Provides helpers for reading devcontainer workspace settings, resolving feature
# configurations, iterating lifecycle hooks, and exporting feature environment
# variables. Requires `json`, `str`, `graph`, and `proc` to be sourced first.
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

# @brief devcontainer__parse_config <file> — Print normalized, JSONC-stripped JSON to stdout.
#
# Args:
#   <file>  Path to the devcontainer.json (or .jsonc) config file.
#
# Stdout: normalized JSON.
#
# Returns: 0 on success, 1 if the file does not exist or contains duplicate keys.
devcontainer__parse_config() {
  local _f="${1-}"
  [[ -f "$_f" ]] || return 1
  # shellcheck disable=SC2119  # called with stdin redirect, not positional args
  json__detect_duplicate_keys_stdin < "$_f" || return 1
  json__strip_jsonc_stdin < "$_f" || return 1
  return 0
}

# @brief devcontainer__workspace_folder <config-path> — Print the workspace root by stripping `/.devcontainer` suffix components from the config's directory.
#
# Args:
#   <config-path>  Path to the devcontainer.json config file.
#
# Stdout: absolute workspace folder path.
#
# Returns: 0 on success, 1 if the file does not exist.
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

# @brief devcontainer__name_version_suffix <name-string> — Extract the version suffix from a feature name string.
#
# Args:
#   <name-string>  Feature name possibly containing a version suffix.
#
# Stdout: version suffix (e.g. `@1.2.3`), or empty if none.
devcontainer__name_version_suffix() {
  str__extract_version_suffix "${1-}"
  return 0
}

# @brief devcontainer__oci_id_and_tag <oci-key> — Split an OCI feature key into its id and tag components.
#
# Args:
#   <oci-key>  OCI reference key (e.g. `ghcr.io/owner/repo/feature:tag`).
#
# Stdout: two lines — line 1: id without tag; line 2: tag, or empty if absent.
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

# @brief devcontainer__is_compatible_key <key> — Return 0 if `<key>` is an OCI-shaped ref or a local path containing `devcontainer-feature.json`.
#
# Args:
#   <key>  Feature key from a devcontainer.json `features` block.
#
# Returns: 0 if compatible, 1 otherwise.
devcontainer__is_compatible_key() {
  local _k="${1-}"
  local _host
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
  if [[ "$_k" == */* ]]; then
    _host="${_k%%/*}"
    devcontainer__is_registry_host_like "$_host" && return 0
  fi
  return 1
}

# @brief devcontainer__lifecycle_disabled <entry> <scope> <featureId> <phase> [<cmdname>] — Return 0 if this lifecycle entry should be skipped for the given context.
#
# Entry grammar: `all`, `<phase>`, `<phase>:<cmd>`, `<featureId>`, `<featureId>:<phase>`,
# or `<featureId>:<phase>:<cmd>`. Feature-scoped entries are ignored at container scope.
#
# Args:
#   <entry>     Disable-entry string (see grammar above).
#   <scope>     `feature` or `container`.
#   <featureId> Feature identifier for feature-scope matching.
#   <phase>     Current lifecycle phase name.
#   [<cmdname>] Optional object-form sub-command name.
#
# Returns: 0 if the entry matches (should be skipped), 1 otherwise.
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

# @brief devcontainer__iter_features <config-file> <workspace-folder> — Emit one TAB-delimited line per feature in the config's `features` block.
#
# Keys that are neither OCI-shaped refs nor resolvable local paths are warned and skipped.
#
# Args:
#   <config-file>      Path to the devcontainer.json config.
#   <workspace-folder> Workspace root (used to resolve relative local paths).
#
# Stdout: TAB-delimited lines `<id>\t<key>\t<tag>` — id is the trailing path component without `:tag`; key is the raw features[] key; tag is the `:tag` suffix or empty.
#
# Returns: 0 on success, 1 if the config file does not exist.
devcontainer__iter_features() {
  local _cfg="${1-}" _wf="${2-}"
  [[ -f "$_cfg" ]] || return 1
  local _k _p _hit _id _tag _rest _full _host
  while IFS= read -r _k; do
    [[ -z "$_k" ]] && continue
    _hit=0
    case "$_k" in
      ./* | ../* | /*)
        _full="$_k"
        [[ "$_full" != /* && -n "$_wf" ]] && _full="${_wf%/}/${_k}"
        if [[ -f "${_full%/}/devcontainer-feature.json" || -f "${_full}/devcontainer-feature.json" ]]; then
          _hit=1
        fi
        ;;
    esac
    if ((_hit == 0)); then
      if [[ "$_k" == */* ]]; then
        _host="${_k%%/*}"
        devcontainer__is_registry_host_like "$_host" && _hit=1
      fi
    fi
    ((_hit == 0)) && {
      logging__warn "skip feature key (not OCI ref or local-path feature): $_k"
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

# @brief devcontainer__feature_env_exports — Read a feature options JSON object from stdin; emit `export KEY=VALUE` lines suitable for eval.
#
# Values are coerced via `json__coerce_scalar_stdin`; arrays and objects cause an error.
# Keys are normalized with `str__safe_id`. Bash `%q` quoting is used for values.
#
# Stdout: `export KEY=VALUE` lines, one per option key.
#
# Returns: 0 on success, 1 if any value is an array or object.
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

# @brief devcontainer__build_ordering_inputs --hard-edges-file F --soft-edges-file F --priority-file F --staged-root D --config-file F -- <id>... — Write `graph__round_order` input files for feature install ordering.
#
# Hard edges derive from `dependsOn`; soft edges from `installsAfter`; priority
# from `overrideFeatureInstallOrder` (first entry gets highest score).
#
# Args:
#   --hard-edges-file F  Output path for hard dependency edges (TAB-delimited `<from>\t<to>`).
#   --soft-edges-file F  Output path for soft dependency edges.
#   --priority-file F    Output path for priority scores (TAB-delimited `<id>\t<score>`).
#   --staged-root D      Directory containing staged feature subdirectories.
#   --config-file F      Path to the devcontainer.json config.
#   <id>...              Feature IDs to process.
#
# Returns: 0 on success, 1 if any required flag is missing.
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

# @brief devcontainer__lifecycle_iter --config-file F --staged-root D --phase P -- <id>... — Emit lifecycle commands for the given phase across features and container config.
#
# Features are iterated in the provided order; the container-level entry is emitted last.
#
# Args:
#   --config-file F  Path to the devcontainer.json config.
#   --staged-root D  Directory containing staged feature subdirectories.
#   --phase P        Lifecycle phase name (e.g. `postCreateCommand`).
#   <id>...          Feature IDs to iterate.
#
# Stdout: TAB-delimited lines `<scope>\t<id>\t<cmd-json>` — scope is `feature` or `container`; id is the feature id or `_container_`; cmd-json is compact JSON.
#
# Returns: 0 on success, 1 if `--phase` is not provided or jq is unavailable.
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

# @brief devcontainer__user_home <user> — Print the resolved home directory for `<user>`, or empty if unresolvable.
#
# Detection order: `getent passwd` (Linux) → `dscl` (macOS) → tilde expansion.
#
# Args:
#   <user>  Username to resolve.
#
# Stdout: absolute home directory path, or empty if unresolvable.
#
# Returns: 0 on success, 1 if no username is provided.
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
