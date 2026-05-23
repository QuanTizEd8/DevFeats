#!/usr/bin/env bash
# .dev/scripts/work/work.sh — format, lint, sync, and test for changed working-tree files.
#
# Runs each step through capture/composite.sh (per-step logs + work summary.md).
#
# Usage: bash .dev/scripts/work/work.sh

set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
composite_sh="${script_dir}/../capture/composite.sh"
lint_sh="${script_dir}/../lint/sh-check.sh"
format_sh="${script_dir}/../format/shfmt.sh"
run_unit="${script_dir}/../test/run-unit.sh"

steps=()

add_step() {
  local name=$1
  shift
  steps+=("$name" -- "$@")
}

mapfile -t _changed < <({
  git diff --name-only
  git diff --cached --name-only
} | sort -u)

if [[ ${#_changed[@]} -eq 0 ]]; then
  printf 'No staged or unstaged changes.\n' >&2
  exit 0
fi

_sh_all=()
_sh_lib=()
_py=()
_lib_any=false
declare -A _feats=()

for _path in "${_changed[@]}"; do
  case "$_path" in
    *.sh | *.bash)
      _sh_all+=("$_path")
      [[ "$_path" == lib/* ]] && _sh_lib+=("$_path")
      ;;
    *.py)
      _py+=("$_path")
      ;;
  esac
  [[ "$_path" == lib/* ]] && _lib_any=true
  if [[ "$_path" =~ ^features/([^/]+)/ ]]; then
    _feats["${BASH_REMATCH[1]}"]=1
  fi
done

if [[ ${#_sh_all[@]} -gt 0 ]]; then
  add_step format-sh bash "$format_sh" "${_sh_all[@]}"
fi

if [[ ${#_sh_lib[@]} -gt 0 ]]; then
  add_step lint-sh-check-lib bash "$lint_sh" "${_sh_lib[@]}"
fi

if [[ ${#_py[@]} -gt 0 ]]; then
  add_step lint-py pixi run --environment lint lint-py "${_py[@]}"
  add_step format-py pixi run --environment lint format-py "${_py[@]}"
fi

add_step sync-src pixi run sync-src

if [[ "$_lib_any" == true ]]; then
  mapfile -t _installs < <(find src -maxdepth 2 -name 'install.bash' 2> /dev/null | sort)
  if [[ ${#_installs[@]} -gt 0 ]]; then
    add_step lint-sh-check-install bash "$lint_sh" "${_installs[@]}"
  fi
elif [[ ${#_feats[@]} -gt 0 ]]; then
  _install_args=()
  for _feat in "${!_feats[@]}"; do
    _install="src/${_feat}/install.bash"
    [[ -f "$_install" ]] && _install_args+=("$_install")
  done
  if [[ ${#_install_args[@]} -gt 0 ]]; then
    add_step lint-sh-check-install bash "$lint_sh" "${_install_args[@]}"
  fi
fi

declare -A _modules=()
for _path in "${_changed[@]}"; do
  [[ "$_path" =~ ^lib/(.+)\.sh$ ]] || continue
  _rel="${BASH_REMATCH[1]}"
  if [[ "$_rel" != */* ]]; then
    _mod="$_rel"
  else
    case "$_rel" in
      install/*) _mod=install_tools ;;
      *) _mod="${_rel%%/*}" ;;
    esac
  fi
  [[ -f "test/lib/${_mod}.bats" ]] && _modules["$_mod"]=1
done

for _mod in $(printf '%s\n' "${!_modules[@]}" | sort); do
  add_step "test-lib-mod-${_mod}" bash "$run_unit" --module "$_mod"
done

exec bash "$composite_sh" work -- "${steps[@]}"
