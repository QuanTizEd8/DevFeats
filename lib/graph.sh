#!/usr/bin/env bash
# graph.sh — round-based installation order (devcontainer-style). Bash >=4.
# Do not edit _lib/ copies — edit lib/ instead.
[[ -n "${_GRAPH__LIB_LOADED-}" ]] && return 0
_GRAPH__LIB_LOADED=1

# @brief graph__round_order
#   --hard-edges-file F  pred<TAB>succ  (pred before succ; both must appear in node list)
#   --soft-edges-file F  same; pred ignored if not in node list
#   --priority-file F    id<TAB>int  (higher = earlier within a round; default 0)
#   --compare CMD        optional: sort candidate batch (stdin: ids, stdout: ordered ids). Default: numeric priority desc then sort -u.
#   --                   then: one node id per argument
graph__round_order() {
  local -a _nodes=() _cand=() _pick=()
  local _hf="" _sf="" _pf="" _cmp=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --hard-edges-file) _hf="${2-}"; shift 2 ;;
    --soft-edges-file) _sf="${2-}"; shift 2 ;;
    --priority-file) _pf="${2-}"; shift 2 ;;
    --compare) _cmp="${2-}"; shift 2 ;;
    --) shift; _nodes=("$@"); break ;;
    *) _nodes=("$@"); break ;;
    esac
  done

  if [[ ${#_nodes[@]} -eq 0 ]]; then
    echo "⛔ graph__round_order: need node ids after --" >&2
    return 1
  fi

  declare -A _have=() _hdep=() _sdep=() _pr=() _done=()
  local _a _l p q

  for _a in "${_nodes[@]}"; do
    _have["$_a"]=1
  done

  if [[ -n "$_pf" && -f "$_pf" ]]; then
    while IFS= read -r _l || [[ -n "$_l" ]]; do
      [[ -z "$_l" ]] && continue
      IFS=$'\t' read -r p q <<<"$_l" || true
      [[ -n "$p" ]] && _pr["$p"]="${q:-0}"
    done <"$_pf" || return 1
  fi

  if [[ -n "$_hf" && -f "$_hf" ]]; then
    while IFS= read -r _l || [[ -n "$_l" ]]; do
      [[ -z "$_l" ]] && continue
      IFS=$'\t' read -r p q <<<"$_l" || true
      if [[ -z "$p" || -z "$q" ]]; then
        continue
      fi
      if [[ -z "${_have[$p]+x}" || -z "${_have[$q]+x}" ]]; then
        echo "⛔ graph__round_order: hard edge unknown node (${p} -> ${q})" >&2
        return 1
      fi
      _hdep["$q"]+="${p} "
    done <"$_hf" || return 1
  fi

  if [[ -n "$_sf" && -f "$_sf" ]]; then
    while IFS= read -r _l || [[ -n "$_l" ]]; do
      [[ -z "$_l" ]] && continue
      IFS=$'\t' read -r p q <<<"$_l" || true
      [[ -z "$p" || -z "$q" || -z "${_have[$q]+x}" ]] && continue
      [[ -z "${_have[$p]+x}" ]] && continue
      _sdep["$q"]+="${p} "
    done <"$_sf" || return 1
  fi

  _all_pred_done() {
    local n="$1" d
    for d in ${_hdep["$n"]-}; do
      [[ -z "$d" ]] && continue
      [[ -z "${_done[$d]+x}" ]] && return 1
    done
    for d in ${_sdep["$n"]-}; do
      [[ -z "$d" ]] && continue
      [[ -n "${_have[$d]+x}" && -z "${_done[$d]+x}" ]] && return 1
    done
    return 0
  }

  while true; do
    _cand=()
    for _a in "${!_have[@]}"; do
      [[ -n "${_done[$_a]+x}" ]] && continue
      _all_pred_done "$_a" && _cand+=("$_a")
    done
    if ((${#_cand[@]} == 0)); then
      for _a in "${!_have[@]}"; do
        [[ -z "${_done[$_a]+x}" ]] && {
          echo "⛔ graph__round_order: cycle in dependencies" >&2
          return 1
        }
      done
      break
    fi
    if [[ -n "$_cmp" ]]; then
      mapfile -t _pick < <(printf '%s\n' "${_cand[@]}" | bash -c "$_cmp")
    else
      mapfile -t _pick < <(
        for _a in "${_cand[@]}"; do
          printf '%010d\t%s\n' "${_pr["$_a"]-0}" "$_a"
        done | sort -t$'\t' -k1,1nr -k2,2 | cut -f2-
      )
    fi
    for _a in "${_pick[@]}"; do
      [[ -z "$_a" ]] && continue
      _done["$_a"]=1
      echo "$_a"
    done
  done
  return 0
}
