#!/usr/bin/env bash
set -euo pipefail

# ── Determine if this is a "force" run (skip diff; test everything) ──
is_force=false
if [[ "$REF_TYPE" == "tag" || "$EVENT_NAME" == "workflow_dispatch" ]]; then
  is_force=true
elif [[ "$EVENT_NAME" == "push" && "$BEFORE" == "0000000000000000000000000000000000000000" ]]; then
  # First push to a new branch — no diff baseline; run everything safely
  is_force=true
fi

# ── Determine is_release and resolve release_tag ──────────────────
is_release=false
release_tag=""
if [[ "$EVENT_NAME" == "push" && "$REF_TYPE" == "tag" ]]; then
  is_release=true
  release_tag="$REF_NAME"
elif [[ "$EVENT_NAME" == "workflow_dispatch" && -n "${INPUT_TAG:-}" ]]; then
  is_release=true
  release_tag="$INPUT_TAG"
fi

# ── Feature discovery helpers ──────────────────────────────────────
feature_ids=$(find features -mindepth 2 -maxdepth 2 -name "metadata.yaml" \
  | sed 's|^features/||; s|/metadata.yaml$||' | sort -u)
all_features=$(printf '%s\n' "$feature_ids" | grep -v '^$' | jq -R . | jq -sc .)
macos_capable=$(find test -mindepth 3 -maxdepth 3 -name "*.sh" -path "*/macos/*" \
  | sed 's|test/||; s|/macos/.*||' | sort -u)
macos_all=$(printf '%s\n' "$macos_capable" | grep -v '^$' | jq -R . | jq -sc .)

# ── Compute changed files (when not a force run) ───────────────────
if [[ "$is_force" == "true" ]]; then
  run_lint=true
  run_validate=true
  run_unit=true
  run_features=true
  features="$all_features"
  run_dist=true
  if [[ "$macos_all" != "[]" ]]; then run_macos=true; else run_macos=false; fi
  macos_features="$macos_all"
else
  if [[ "$EVENT_NAME" == "pull_request" ]]; then
    changed=$(git diff --name-only "origin/${BASE_REF}"...HEAD)
  else
    changed=$(git diff --name-only "${BEFORE}...HEAD")
  fi

  # run_lint: any shell file changed
  if echo "$changed" | grep -qE '\.(sh|bash|bats)$'; then run_lint=true; else run_lint=false; fi

  # run_validate: metadata.yaml or metadata.schema.json changed (source for devcontainer-feature.json)
  if echo "$changed" | grep -qE 'metadata\.yaml|metadata\.schema\.json'; then run_validate=true; else run_validate=false; fi

  # run_unit: lib/ or test/unit/ changed
  if echo "$changed" | grep -qE '^(lib/|test/unit/)'; then run_unit=true; else run_unit=false; fi

  # features: if features/bootstrap.sh, lib/, or test/lib/ changed, all features are affected
  if echo "$changed" | grep -qE '^(features/bootstrap\.sh|lib/|test/lib/)'; then
    features="$all_features"
  else
    features=$(printf '%s\n' "$feature_ids" | while IFS= read -r f; do
      if echo "$changed" | grep -qE "^(features|test)/$f/"; then echo "$f"; fi
    done | jq -R . | jq -sc .)
  fi
  if [[ "$features" != "[]" ]]; then run_features=true; else run_features=false; fi

  # macos_features: if features/bootstrap.sh, lib/, or test/lib/ changed, all macos-capable features are affected
  if echo "$changed" | grep -qE '^(features/bootstrap\.sh|lib/|test/lib/)'; then
    macos_features="$macos_all"
  else
    macos_features=$(printf '%s\n' "$macos_capable" | grep -v '^$' | while IFS= read -r f; do
      if echo "$changed" | grep -qE "^(features|test)/$f/"; then echo "$f"; fi
    done | jq -R . | jq -sc .)
  fi
  if [[ "$macos_features" != "[]" ]]; then run_macos=true; else run_macos=false; fi

  # run_dist: dist-related files changed
  if echo "$changed" | grep -qE '^(features/bootstrap\.sh|features/get\.sh|features/sysset\.sh|scripts/build-artifacts\.sh|features/|lib/|test/dist/|test/lib/)'; then
    run_dist=true
  else
    run_dist=false
  fi
fi

# ── Write all outputs ──────────────────────────────────────────────
{
  echo "run_lint=$run_lint"
  echo "run_validate=$run_validate"
  echo "run_unit=$run_unit"
  echo "run_features=$run_features"
  echo "features=$features"
  echo "run_macos=$run_macos"
  echo "macos_features=$macos_features"
  echo "run_dist=$run_dist"
  echo "is_release=$is_release"
  echo "release_tag=$release_tag"
} >> "$GITHUB_OUTPUT"

# ── Resolve branch name for devcontainer image tag ─────────────────
if [[ "$REF_TYPE" == "tag" ]]; then
  branch_name="main"
elif [[ -n "${HEAD_REF:-}" ]]; then
  branch_name="$HEAD_REF"
else
  branch_name="$REF_NAME"
fi
branch_tag="branch-$(echo "$branch_name" | sed 's/[^a-zA-Z0-9._-]/-/g')"

# ── Detect devcontainer changes ────────────────────────────────────
devcontainer_changed=false
if [[ "$REF_TYPE" == "tag" ]]; then
  devcontainer_changed=false
elif [[ "$is_force" == "true" ]]; then
  devcontainer_changed=true
elif echo "${changed:-}" | grep -qE '^\.devcontainer/\.dev/'; then
  devcontainer_changed=true
fi

# ── Probe GHCR for existing devcontainer image tags ────────────────
existing_tags=""
if existing_tags_raw=$(gh api \
    "orgs/${REPO_OWNER}/packages/container/${REPOSITORY#*/}-devcontainer/versions" \
    --jq '.[].metadata.container.tags[]' 2>/dev/null); then
  existing_tags="$existing_tags_raw"
fi
has_latest=false
has_branch=false
if echo "$existing_tags" | grep -qx "latest"; then has_latest=true; fi
if echo "$existing_tags" | grep -qx "$branch_tag"; then has_branch=true; fi

# ── Apply decision matrix ──────────────────────────────────────────
build_image=false
image_tag="latest"

if [[ "$REF_TYPE" == "tag" ]]; then
  # Release: always skip build, always use latest
  build_image=false
  image_tag="latest"
elif [[ "$branch_name" == "main" ]]; then
  image_tag="latest"
  if [[ "$devcontainer_changed" == "true" || "$has_latest" == "false" ]]; then
    build_image=true
  fi
else
  # Non-main branch / PR
  if [[ "$devcontainer_changed" == "true" ]]; then
    build_image=true
    image_tag="$branch_tag"
  elif [[ "$has_branch" == "true" ]]; then
    # Branch tag exists — reuse it
    build_image=false
    image_tag="$branch_tag"
  elif [[ "$has_latest" == "true" ]]; then
    # No branch tag, but latest exists — fall back to latest
    build_image=false
    image_tag="latest"
  else
    # Cold start: no tags at all — build branch tag
    build_image=true
    image_tag="$branch_tag"
  fi
fi

{
  echo "build_image=$build_image"
  echo "image_tag=$image_tag"
} >> "$GITHUB_OUTPUT"
