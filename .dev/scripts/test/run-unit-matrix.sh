#!/usr/bin/env bash
# Usage: run-unit-matrix.sh [--env <name>] [-- <extra-args-to-run-unit.sh>]
#
# Without --env: runs all environments from test/lib/scenarios.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
export REPO_ROOT

_TARGET_ENV="" _EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      _TARGET_ENV="$2"
      shift 2
      ;;
    --)
      shift
      _EXTRA_ARGS=("$@")
      break
      ;;
    *)
      printf 'Unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

_scenarios_json=$(
  python3 - << 'PYEOF'
import json, os, sys
sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], ".dev/lib"))
from proman.test.scenarios import load, expand_test_files
scenarios_yaml = os.path.join(os.environ["REPO_ROOT"], "test/lib/scenarios.yaml")
defaults, scenarios = load(scenarios_yaml)
lib_dir = os.path.join(os.environ["REPO_ROOT"], "test/lib")
result = {}
for name, s in scenarios.items():
    result[name] = {"env": s["env"], "env_vars": s.get("env_vars", {}),
                    "test_files": expand_test_files(s.get("tests"), lib_dir)}
print(json.dumps(result))
PYEOF
)

_run_env() {
  local name="$1"
  local env_name env_vars_args=() run_unit_args=()
  env_name=$(jq -r --arg n "$name" '.[$n].env' <<< "$_scenarios_json")
  local image
  image=$("$SCRIPT_DIR/resolve-env.sh" "$env_name")

  while IFS='=' read -r k v; do
    [[ -n "$k" ]] && env_vars_args+=("--env" "${k}=${v}")
  done < <(jq -r --arg n "$name" '.[$n].env_vars | to_entries[] | "\(.key)=\(.value)"' \
    <<< "$_scenarios_json")

  while IFS= read -r tf; do
    # translate host-side absolute path to container-side /repo/... path
    [[ -n "$tf" ]] && run_unit_args+=("--paths" "/repo${tf#"${REPO_ROOT}"}")
  done < <(jq -r --arg n "$name" '.[$n].test_files[]' <<< "$_scenarios_json")
  run_unit_args+=("${_EXTRA_ARGS[@]+"${_EXTRA_ARGS[@]}"}")

  printf '\n══ %s [%s] ══\n' "$name" "$env_name"
  "$SCRIPT_DIR/run-in-container.sh" \
    --image "$image" \
    --name "test-unit-${name}" \
    "${env_vars_args[@]+"${env_vars_args[@]}"}" \
    --run "bash /repo/.dev/scripts/test/run-unit.sh ${run_unit_args[*]+"${run_unit_args[*]}"}"
}

if [[ -n "$_TARGET_ENV" ]]; then
  _run_env "$_TARGET_ENV"
else
  _pass=0 _fail=0
  while IFS= read -r name; do
    if _run_env "$name"; then ((_pass++)); else ((_fail++)); fi
  done < <(jq -r 'keys[]' <<< "$_scenarios_json")
  printf '\nMatrix: %d passed, %d failed\n' "$_pass" "$_fail"
  [[ $_fail -eq 0 ]]
fi
