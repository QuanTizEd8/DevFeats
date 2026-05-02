#!/usr/bin/env bash
# build/default.sh — Verify that build-artifacts.sh produces a correct dist/ layout.
#
# Checks:
#   1. Per-feature tarballs exist for every feature with an install.bash.
#   2. Each tarball contains: install.sh, install.bash, _lib/.
#   3. build-offline-kit.sh can assemble an offline kit from dist/ + manifest base.
#   4. dist/ does NOT contain install.sh (it lives in the repo root).
#   5. dist/ does NOT contain scripts/ (old arch artefact).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"
DIST="${REPO_ROOT}/dist"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

# ── Helper: list features that have an install.bash ─────────────────────────
_features=()
while IFS= read -r _json; do
  _dir="$(dirname "$_json")"
  _name="$(basename "$_dir")"
  [[ -f "${_dir}/install.bash" ]] && _features+=("$_name")
done < <(find "${REPO_ROOT}/src" -maxdepth 2 -name "devcontainer-feature.json" | sort)

# ── Checks ────────────────────────────────────────────────────────────────────

check "dist/ does not contain install.sh (it lives in repo root)" test ! -f "${DIST}/install.sh"
check "dist/scripts/ absent after build" test ! -d "${DIST}/scripts"
check "repo root install.sh exists" test -f "${REPO_ROOT}/install.sh"
check "repo root install.bash exists" test -f "${REPO_ROOT}/install.bash"

for _feat in "${_features[@]}"; do
  _tarball="${DIST}/devfeats-${_feat}.tar.gz"
  check "devfeats-${_feat}.tar.gz exists" test -f "$_tarball"
  check "devfeats-${_feat}: contains install.sh" \
    bash -c "tar -tzf '${_tarball}' | grep -qx '\./install\.sh\|install\.sh'"
  check "devfeats-${_feat}: contains install.bash" \
    bash -c "tar -tzf '${_tarball}' | grep -qx '\./install\.bash\|install\.bash'"
  check "devfeats-${_feat}: contains _lib/" \
    bash -c "tar -tzf '${_tarball}' | grep -q '_lib/'"
  check "devfeats-${_feat}: contains devcontainer-feature.json" \
    bash -c "tar -tzf '${_tarball}' | grep -q 'devcontainer-feature\.json'"
done

_f0="${_features[0]}"
_ver="$(grep -E '^[[:space:]]*version:' "${REPO_ROOT}/features/${_f0}/metadata.yaml" | head -1 | awk '{print $2}')"
_kit_mirror="$(mktemp -d)"
trap 'rm -rf "${_kit_mirror:-}"' EXIT
offline_kit_publish_mirror "${_kit_mirror}" "v0.0.777-disttest" "${DIST}" "${_f0}:${_ver}"
check "offline kit tarball exists" test -f "${_kit_mirror}/v0.0.777-disttest/devfeats-v0.0.777-disttest.tar.gz"
check "offline kit contains manifest.json" \
  bash -c "tar -tzf '${_kit_mirror}/v0.0.777-disttest/devfeats-v0.0.777-disttest.tar.gz' | grep -qx '\./manifest\.json\|manifest\.json'"

reportResults
