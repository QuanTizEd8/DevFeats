#!/usr/bin/env bash
# offline_kit_mirror.sh — Build a bundle kit tarball on a local mirror for dist tests.
#
# Usage (source from a scenario script after REPO_ROOT is set):
#   offline_kit_publish_mirror <mirror_root> <bundle_tag_vX> <dist_dir> [feature:ver ...]
#
# Creates: <mirror_root>/<bundle_tag>/devfeats-vX.Y.Z.tar.gz (same ``v`` prefix as the release tag)
# Requires: jq, bash scripts/build-offline-kit.sh, dist devfeats-<feature>.tar.gz for each feature.
offline_kit_publish_mirror() {
  local _mr="${1:?mirror root}" _bt="${2:?bundle tag}" _dd="${3:?dist}"
  shift 3 || true
  local _base _feats _kit_tag
  _kit_tag="${_bt}"
  [[ "${_kit_tag}" == v* ]] || _kit_tag="v${_kit_tag}"
  mkdir -p "${_mr}/${_bt}"
  _base="$(mktemp)"
  _feats="$(jq -n '$ARGS.positional | map(split(":")) | map({key:.[0], value:.[1]}) | from_entries' --args -- "$@")"
  jq -n \
    --arg v "$_bt" \
    --argjson f "$_feats" \
    '{
      schemaVersion: "2.0.0",
      version: $v,
      generatedAt: "1970-01-01T00:00:00Z",
      source: {repo: "quantized8/devfeats", commit: "0000000000000000000000000000000000000000"},
      features: $f,
      refs: {},
      digests: {}
    }' > "$_base"
  bash "${REPO_ROOT:?}/scripts/build-offline-kit.sh" "${_bt}" "${_dd}" "${_base}" "${_mr}/${_bt}/devfeats-${_kit_tag}.tar.gz"
  rm -f "$_base"
}
