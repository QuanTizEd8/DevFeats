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
  features=$(find features -mindepth 2 -maxdepth 2 -name "metadata.yaml" \
    | sed 's|^features/||; s|/metadata.yaml$||' | sort -u \
    | jq -R . | jq -sc .)
else
  features=$(printf '%s\n' "$INPUT_FEATURES" | tr ',' '\n' | tr -d ' ' \
    | grep -v '^$' | jq -R . | jq -sc .)
fi

# ── Resolve macos_features ────────────────────────────────────────
if [[ "${INPUT_MACOS_FEATURES:-}" == \[* ]]; then
  macos_features="$INPUT_MACOS_FEATURES"
elif [[ -z "${INPUT_MACOS_FEATURES:-}" ]]; then
  macos_capable=$(find test -mindepth 3 -maxdepth 3 -name "*.sh" -path "*/macos/*" \
    | sed 's|test/||; s|/macos/.*||' | sort -u)
  macos_features=$(printf '%s\n' "$macos_capable" | grep -v '^$' | jq -R . | jq -sc .)
else
  macos_features=$(printf '%s\n' "$INPUT_MACOS_FEATURES" | tr ',' '\n' | tr -d ' ' \
    | grep -v '^$' | jq -R . | jq -sc .)
fi

# ── run_prepare: true if any job that consumes artifacts is requested ─
run_prepare=false
for flag in "$INPUT_RUN_LINT" "$INPUT_RUN_VALIDATE" "$INPUT_RUN_UNIT" "$INPUT_RUN_FEATURES" "$INPUT_RUN_MACOS" "$INPUT_RUN_DIST"; do
  if [[ "$flag" == "true" ]]; then
    run_prepare=true
    break
  fi
done

# ── Resolve version ───────────────────────────────────────────────
version="${INPUT_VERSION:-${GITHUB_SHA}}"

# ── Resolve ci_image ──────────────────────────────────────────────
ci_image="ghcr.io/${GITHUB_REPOSITORY}-devcontainer:${INPUT_IMAGE_TAG:-latest}"

{
  echo "run_lint=$INPUT_RUN_LINT"
  echo "run_validate=$INPUT_RUN_VALIDATE"
  echo "run_unit=$INPUT_RUN_UNIT"
  echo "run_features=$INPUT_RUN_FEATURES"
  echo "features=$features"
  echo "run_macos=$INPUT_RUN_MACOS"
  echo "macos_features=$macos_features"
  echo "run_dist=$INPUT_RUN_DIST"
  echo "run_prepare=$run_prepare"
  echo "version=$version"
  echo "ci_image=$ci_image"
} >> "$GITHUB_OUTPUT"
