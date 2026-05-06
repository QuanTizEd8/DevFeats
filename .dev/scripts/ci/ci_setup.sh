#!/usr/bin/env bash
set -euo pipefail

# ── Resolve features ──────────────────────────────────────────────
# INPUT_FEATURES can be:
#   - a JSON array string (from workflow_call via cicd.yaml) → pass through as-is
#   - blank (from direct workflow_dispatch with no override) → discover all
#   - a comma-separated list (from direct workflow_dispatch form) → parse and convert
if [[ "${INPUT_FEATURES:-}" == \[* ]]; then
  features="$INPUT_FEATURES"
elif [[ -z "${INPUT_FEATURES:-}" ]]; then
  features=$(find features -mindepth 2 -maxdepth 2 -name "metadata.yaml" |
    sed 's|^features/||; s|/metadata.yaml$||' | sort -u |
    jq -R . | jq -sc .)
else
  features=$(printf '%s\n' "$INPUT_FEATURES" | tr ',' '\n' | tr -d ' ' |
    grep -v '^$' | jq -R . | jq -sc .)
fi

# ── Resolve macos_matrix and unit_macos_matrix ────────────────────
_envs_json=$(yq -o=json '.' "test/environments.yaml")

macos_matrix=$(
  for f in test/features/*/scenarios.yaml; do
    [[ -f "$f" ]] || continue
    _feature=$(basename "$(dirname "$f")")
    yq -o=json '.' "$f" | jq -c --arg feature "$_feature" --argjson envs "$_envs_json" '
      [to_entries[]
       | select(.key != "defaults")
       | .value.envs // []
       | .[]
       | . as $env_name
       | $envs[$env_name]
       | select(. != null and (.image | test("^macos")))
       | .image
       | {feature: $feature, runner: .}
      ] | unique' 2> /dev/null || true
  done | jq -sc 'add // [] | unique_by(.feature + .runner)'
)

# Apply INPUT_MACOS_FEATURES filter if provided
if [[ "${INPUT_MACOS_FEATURES:-}" == \[* ]]; then
  macos_matrix=$(echo "$macos_matrix" |
    jq -c --argjson f "$INPUT_MACOS_FEATURES" '[.[] | select([.feature] | inside($f))]')
elif [[ -n "${INPUT_MACOS_FEATURES:-}" ]]; then
  _f=$(printf '%s\n' "$INPUT_MACOS_FEATURES" | tr ',' '\n' | tr -d ' ' | grep -v '^$' | jq -R . | jq -sc .)
  macos_matrix=$(echo "$macos_matrix" |
    jq -c --argjson f "$_f" '[.[] | select([.feature] | inside($f))]')
fi

unit_macos_matrix=$(echo "$_envs_json" |
  jq -c '[to_entries[] | select(.value.image | test("^macos")) | {runner: .value.image}] | unique')

# ── run_prepare: true if any job that consumes artifacts is requested ─
run_prepare=false
for flag in "$INPUT_RUN_LINT" "$INPUT_RUN_VALIDATE" "$INPUT_RUN_UNIT" "$INPUT_RUN_FEATURES" "$INPUT_RUN_MACOS"; do
  if [[ "$flag" == "true" ]]; then
    run_prepare=true
    break
  fi
done

# ── Resolve version ───────────────────────────────────────────────
version="${INPUT_VERSION:-${GITHUB_SHA}}"

# ── Resolve ci_image ──────────────────────────────────────────────
repo_lower="${GITHUB_REPOSITORY,,}"
ci_image="ghcr.io/${repo_lower}-devcontainer:${INPUT_IMAGE_TAG:-latest}"

# ── Resolve unit_env_matrix ──────────────────────────────────────
unit_env_matrix=$(yq -o=json '.' "test/lib/scenarios.yaml" |
  jq -c '[to_entries[] | select(.key != "defaults") | {name: .key, env: .value.env}]')

{
  echo "run_lint=$INPUT_RUN_LINT"
  echo "run_validate=$INPUT_RUN_VALIDATE"
  echo "run_unit=$INPUT_RUN_UNIT"
  echo "run_features=$INPUT_RUN_FEATURES"
  echo "features=$features"
  echo "run_macos=$INPUT_RUN_MACOS"
  echo "macos_matrix=$macos_matrix"
  echo "unit_macos_matrix=$unit_macos_matrix"
  echo "run_prepare=$run_prepare"
  echo "run_python=$INPUT_RUN_PYTHON"
  echo "version=$version"
  echo "ci_image=$ci_image"
  echo "unit_env_matrix=$unit_env_matrix"
} >> "$GITHUB_OUTPUT"
