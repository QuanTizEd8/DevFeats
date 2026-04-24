#!/usr/bin/env bash
set -euo pipefail

# ── Determine if this is a "force" run (skip diff; test everything) ──
# Forced runs: workflow_dispatch (manual), or a brand-new branch push with no
# diff baseline. Tag-triggered runs are no longer supported (per-feature
# releases are driven by `features_to_release` on push-to-main).
is_force=false
if [[ "$EVENT_NAME" == "workflow_dispatch" ]]; then
  is_force=true
elif [[ "$EVENT_NAME" == "push" && "$BEFORE" == "0000000000000000000000000000000000000000" ]]; then
  is_force=true
fi

# ── Feature discovery helpers ──────────────────────────────────────
feature_ids=$(find features -mindepth 2 -maxdepth 2 -name "metadata.yaml" \
  | sed 's|^features/||; s|/metadata.yaml$||' | sort -u)
all_features=$(printf '%s\n' "$feature_ids" | grep -v '^$' | jq -R . | jq -sc .)
macos_capable=$(find test -mindepth 3 -maxdepth 3 -name "*.sh" -path "*/macos/*" \
  | sed 's|test/||; s|/macos/.*||' | sort -u)
macos_all=$(printf '%s\n' "$macos_capable" | grep -v '^$' | jq -R . | jq -sc .)

# ── Determine is_release and resolve features_to_release ──────────
# Two supported release triggers:
#
#   1. push to main: detect-releasable.py scans features/*/metadata.yaml,
#      returns a JSON array of every feature whose <id>/<version> tag does
#      not yet exist as a GitHub Release.
#
#   2. workflow_dispatch with feature + version inputs: publishes a single
#      feature/version (useful for hotfixes or retrying a failed release).
is_release=false
features_to_release="[]"
if [[ "$EVENT_NAME" == "workflow_dispatch" \
    && -n "${INPUT_FEATURE:-}" && -n "${INPUT_VERSION:-}" ]]; then
  features_to_release=$(jq -cn \
    --arg feat "$INPUT_FEATURE" \
    --arg ver "$INPUT_VERSION" \
    '[{feature:$feat, version:$ver, tag:"\($feat)/\($ver)"}]')
  is_release=true
elif [[ "$EVENT_NAME" == "push" \
    && "$REF_TYPE" == "branch" && "$REF_NAME" == "main" ]]; then
  features_to_release=$(python3 scripts/detect-releasable.py \
    --repo "$REPOSITORY" --features-dir features)
  if [[ -n "$features_to_release" && "$features_to_release" != "[]" ]]; then
    is_release=true
  fi
fi

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

# ── Version-bump enforcement (PR-only) ─────────────────────────────
# Fail PRs that modify payload-bearing paths without bumping the affected
# feature's metadata.yaml version. Scopes:
#
#   - lib/                  → every feature (lib is embedded in every tarball).
#   - features/bootstrap.sh → every feature (shared bootstrap).
#   - features/<id>/        → just that feature.
#
# Compares each feature's `^version:` line at HEAD vs. origin/$BASE_REF. New
# features (no metadata.yaml in the base branch) are exempt.
_head_feature_version() {
  # $1 = feature id
  local _f="features/$1/metadata.yaml"
  [[ -r "$_f" ]] || { echo ""; return; }
  grep -m1 '^version:' "$_f" | awk '{print $2}' | tr -d '"' || echo ""
}
_base_feature_version() {
  # $1 = feature id
  local _ref="origin/${BASE_REF}"
  git show "${_ref}:features/$1/metadata.yaml" 2> /dev/null \
    | grep -m1 '^version:' | awk '{print $2}' | tr -d '"' || true
}

if [[ "$EVENT_NAME" == "pull_request" ]]; then
  _libs_changed=false
  _bootstrap_changed=false
  if echo "$changed" | grep -qE '^lib/'; then _libs_changed=true; fi
  if echo "$changed" | grep -qE '^features/bootstrap\.sh$'; then _bootstrap_changed=true; fi

  _needs_bump=()
  while IFS= read -r _fid; do
    [[ -z "$_fid" ]] && continue
    _fid_changed=false
    if echo "$changed" | grep -qE "^features/${_fid}/"; then _fid_changed=true; fi
    if [[ "$_libs_changed" == "true" \
        || "$_bootstrap_changed" == "true" \
        || "$_fid_changed" == "true" ]]; then
      _base_v=$(_base_feature_version "$_fid")
      _head_v=$(_head_feature_version "$_fid")
      # New feature (no base version): exempt.
      [[ -z "$_base_v" ]] && continue
      if [[ "$_base_v" == "$_head_v" ]]; then
        _needs_bump+=("$_fid (version still $_head_v)")
      fi
    fi
  done <<< "$feature_ids"

  if [[ ${#_needs_bump[@]} -gt 0 ]]; then
    echo "⛔ version-bump lint: the following features were modified (directly or via lib/ or features/bootstrap.sh) but their metadata.yaml version has not been bumped vs. origin/${BASE_REF}:" >&2
    for _f in "${_needs_bump[@]}"; do echo "   - ${_f}" >&2; done
    echo "" >&2
    echo "   Bump the version field in each listed feature's metadata.yaml before merging." >&2
    exit 1
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
  echo "features_to_release=$features_to_release"
} >> "$GITHUB_OUTPUT"

# ── Resolve branch name for devcontainer image tag ─────────────────
if [[ -n "${HEAD_REF:-}" ]]; then
  branch_name="$HEAD_REF"
else
  branch_name="$REF_NAME"
fi
branch_tag="branch-$(echo "$branch_name" | sed 's/[^a-zA-Z0-9._-]/-/g')"

# ── Detect devcontainer changes ────────────────────────────────────
devcontainer_changed=false
if [[ "$is_force" == "true" ]]; then
  devcontainer_changed=true
elif echo "${changed:-}" | grep -qE '^\.devcontainer/\.dev/'; then
  devcontainer_changed=true
fi

# ── Probe GHCR for existing devcontainer image tags ────────────────
existing_tags=""
owner_name="${REPO_OWNER,,}"
package_name="${REPOSITORY#*/}"
package_name="${package_name,,}"
if existing_tags_raw=$(gh api \
    "orgs/${owner_name}/packages/container/${package_name}-devcontainer/versions" \
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

if [[ "$branch_name" == "main" ]]; then
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
