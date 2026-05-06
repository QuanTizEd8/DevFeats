#!/usr/bin/env bash
# Usage: run-feature-tests.sh <feature> [--mode devcontainer|standalone|macos|all]
#                                        [--filter <scenario-name>]
#
# Default mode: all.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
export REPO_ROOT

FEATURE="${1:?Usage: run-feature-tests.sh <feature> [--mode ...] [--filter ...]}"
shift

_MODE="all"
_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      _MODE="${2:?--mode requires a value}"
      shift 2
      ;;
    --filter)
      _FILTER="${2:?--filter requires a value}"
      shift 2
      ;;
    *)
      printf '⛔ Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

_TESTS_DIR="${REPO_ROOT}/test/features/${FEATURE}/tests"
if [[ ! -d "$_TESTS_DIR" ]]; then
  printf '⛔ tests/ directory not found for feature %s: %s\n' "$FEATURE" "$_TESTS_DIR" >&2
  exit 1
fi

# ── Load scenarios via Python ────────────────────────────────────────────────
_scenarios_json=$(
  python3 - "$FEATURE" "$REPO_ROOT" << 'PYEOF'
import json, os, sys
sys.path.insert(0, os.path.join(sys.argv[2], ".dev/lib"))
from proman.test.scenarios import load, merge_defaults, expand_envs
from proman.test.environments import load as load_envs, is_macos
sp = os.path.join(sys.argv[2], "test/features", sys.argv[1], "scenarios.yaml")
ep = os.path.join(sys.argv[2], "test/environments.yaml")
defaults, scenarios = load(sp)
envs = load_envs(ep)
result = []
for name, sc in scenarios.items():
    sc = merge_defaults(sc, defaults)
    for key, env_name, scenario in expand_envs(name, sc):
        result.append({"key": key, "scenario_name": name, "env_name": env_name,
                       "env_is_macos": is_macos(env_name, envs), "scenario": scenario})
print(json.dumps(result))
PYEOF
)

# ── Devcontainer mode ────────────────────────────────────────────────────────
_run_devcontainer() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  ln -s "${REPO_ROOT}/src" "${tmpdir}/src"

  proman-test-gen-devcontainer \
    --feature "$FEATURE" \
    --unified "${REPO_ROOT}/test/features/${FEATURE}/scenarios.yaml" \
    --envs "${REPO_ROOT}/test/environments.yaml" \
    --out-dir "${tmpdir}"

  if [[ -n "$_FILTER" ]]; then
    jq --arg f "$_FILTER" 'with_entries(select(.key | startswith($f)))' \
      "${tmpdir}/scenarios.json" > "${tmpdir}/scenarios.tmp.json"
    mv "${tmpdir}/scenarios.tmp.json" "${tmpdir}/scenarios.json"
  fi

  mkdir -p "${tmpdir}/test/${FEATURE}"
  cp "${_TESTS_DIR}/"*.sh "${tmpdir}/test/${FEATURE}/"
  devcontainer features test -f "$FEATURE" --project-folder "${tmpdir}"
}

# ── Standalone mode ──────────────────────────────────────────────────────────
_run_standalone() {
  while IFS= read -r entry; do
    local key env_name scenario modes user sudo_ok network options_json image

    key=$(jq -r '.key' <<< "$entry")
    env_name=$(jq -r '.env_name' <<< "$entry")
    scenario=$(jq -c '.scenario' <<< "$entry")

    [[ "$(jq -r '.env_is_macos' <<< "$entry")" == "true" ]] && continue
    [[ -n "$_FILTER" && "$key" != "$_FILTER"* ]] && continue

    modes=$(jq -r '(.modes // ["devcontainer","standalone"]) | join(",")' <<< "$scenario")
    [[ "$modes" != *standalone* ]] && continue

    user=$(jq -r '.standalone.user // ""' <<< "$scenario")
    sudo_ok=$(jq -r '.standalone.sudo // true' <<< "$scenario")
    network=$(jq -r '.standalone.network // ""' <<< "$scenario")
    skip_install=$(jq -r '.standalone.skip_install // false' <<< "$scenario")
    options_json=$(jq -c '.options // {}' <<< "$scenario")

    local _resolve_flags=()
    while IFS= read -r _flag; do
      [[ -n "$_flag" ]] && _resolve_flags+=("$_flag")
    done < <(jq -r '
        (.scenario.args // {} | to_entries[] | "--arg \(.key)=\(.value)"),
        (.scenario.env_vars // {} | to_entries[] | "--env-var \(.key)=\(.value)")
      ' <<< "$entry")
    image=$("$SCRIPT_DIR/resolve-env.sh" "$env_name" "${_resolve_flags[@]+"${_resolve_flags[@]}"}")

    local net_flag=()
    [[ "$network" == "none" ]] && net_flag=("--network-none")

    local shim_setup='mkdir -p /tmp/_testlib && cp /repo/test/support/assert.sh /tmp/_testlib/dev-container-features-test-lib && chmod +x /tmp/_testlib/dev-container-features-test-lib'
    local sudo_stub=''
    if [[ "$sudo_ok" == "false" ]]; then
      sudo_stub='mkdir -p /tmp/_nosudo && printf '"'"'#!/bin/sh\nexit 1\n'"'"' > /tmp/_nosudo/sudo && chmod +x /tmp/_nosudo/sudo && export PATH=/tmp/_nosudo:$PATH'
    fi

    local setup_cmds
    setup_cmds=$(jq -r '.setup // ""' <<< "$scenario")

    local exports
    exports=$(python3 -c "
import json, sys
opts = json.loads(sys.argv[1])
for k, v in opts.items():
    key = k.upper().replace('-', '_')
    print(f'export {key}={repr(str(v))}')
" "$options_json")

    local test_run_cmds=""
    while IFS= read -r test_script; do
      if [[ -n "$user" ]]; then
        test_run_cmds+="su ${user} -c 'PATH=/tmp/_testlib:\$PATH REPO_ROOT=/repo bash /repo/test/features/${FEATURE}/tests/${test_script}'"$'\n'
      else
        test_run_cmds+="PATH=/tmp/_testlib:\$PATH REPO_ROOT=/repo bash /repo/test/features/${FEATURE}/tests/${test_script}"$'\n'
      fi
    done < <(jq -r '.tests[]' <<< "$scenario")

    local run_cmd="${shim_setup}
${setup_cmds}
${sudo_stub}
${exports}"
    if [[ "$skip_install" != "true" ]]; then
      run_cmd+="
bash /repo/src/${FEATURE}/install.bash"
    fi
    run_cmd+="
${test_run_cmds}"

    printf '\n══ standalone: %s [%s] ══\n' "$key" "$env_name"
    "$SCRIPT_DIR/run-in-container.sh" \
      --image "$image" --name "standalone-${FEATURE}-${key//./-}" \
      "${net_flag[@]+"${net_flag[@]}"}" --run "$run_cmd"
  done < <(jq -c '.[]' <<< "$_scenarios_json")
}

# ── macOS mode ───────────────────────────────────────────────────────────────
_run_macos() {
  local shim_dir
  shim_dir="$(mktemp -d)"
  trap 'rm -rf "$shim_dir"' RETURN
  cp "${REPO_ROOT}/test/support/assert.sh" "$shim_dir/dev-container-features-test-lib"
  chmod +x "$shim_dir/dev-container-features-test-lib"

  while IFS= read -r entry; do
    [[ "$(jq -r '.env_is_macos' <<< "$entry")" != "true" ]] && continue

    local key env_name scenario options_json user

    key=$(jq -r '.key' <<< "$entry")
    env_name=$(jq -r '.env_name' <<< "$entry")
    scenario=$(jq -c '.scenario' <<< "$entry")

    [[ -n "$_FILTER" && "$key" != "$_FILTER"* ]] && continue

    options_json=$(jq -c '.options // {}' <<< "$scenario")
    user=$(jq -r '.standalone.user // ""' <<< "$scenario")

    local scenario_setup
    scenario_setup=$(jq -r '.setup // ""' <<< "$scenario")

    local env_build
    env_build=$(
      python3 - "$env_name" "$REPO_ROOT" << 'PYEOF'
import sys, os
sys.path.insert(0, os.path.join(sys.argv[2], ".dev/lib"))
from proman.test.environments import load
envs = load(os.path.join(sys.argv[2], "test/environments.yaml"))
print(envs.get(sys.argv[1], {}).get("build", {}).get("dockerfile", ""))
PYEOF
    )
    [[ -n "$env_build" ]] && eval "$env_build"
    [[ -n "$scenario_setup" ]] && eval "$scenario_setup"

    while IFS='=' read -r k v; do
      export "${k}"="${v}"
    done < <(python3 -c "
import json, sys
opts = json.loads(sys.argv[1])
for k, v in opts.items():
    key = k.upper().replace('-', '_')
    print(f'{key}={repr(str(v))}')
" "$options_json")

    printf '\n══ macos: %s ══\n' "$key"
    bash "${REPO_ROOT}/src/${FEATURE}/install.bash"

    while IFS= read -r test_script; do
      if [[ -n "$user" ]]; then
        su "$user" -c "PATH='${shim_dir}:${PATH}' REPO_ROOT='${REPO_ROOT}' bash '${REPO_ROOT}/test/features/${FEATURE}/tests/${test_script}'"
      else
        PATH="${shim_dir}:${PATH}" REPO_ROOT="${REPO_ROOT}" \
          bash "${REPO_ROOT}/test/features/${FEATURE}/tests/${test_script}"
      fi
    done < <(jq -r '.tests[]' <<< "$scenario")
  done < <(jq -c '.[]' <<< "$_scenarios_json")
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
case "$_MODE" in
  devcontainer) _run_devcontainer ;;
  standalone) _run_standalone ;;
  macos) _run_macos ;;
  all)
    _rc=0
    _run_devcontainer || _rc=1
    _run_standalone || _rc=1
    # macOS mode only runs if host is Darwin or envs include macos entries
    if [[ "$(uname)" == "Darwin" ]] ||
      jq -e 'map(select(.env_is_macos)) | length > 0' <<< "$_scenarios_json" > /dev/null 2>&1; then
      _run_macos || _rc=1
    fi
    exit "$_rc"
    ;;
  *)
    printf '⛔ Unknown mode: %s\n' "$_MODE" >&2
    exit 1
    ;;
esac
