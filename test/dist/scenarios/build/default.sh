#!/usr/bin/env bash
# build/default.sh — Verify that build-artifacts.sh produces a correct dist/ layout.
#
# Checks:
#   1. Per-feature tarballs exist for every feature with an install.bash.
#   2. Each tarball contains: install.sh, install.bash, _lib/.
#   3. sysset-all.tar.gz exists and contains all per-feature tarballs.
#   4. dist/ does NOT contain get.sh (it lives in the repo root).
#   5. dist/ does NOT contain scripts/ (old arch artefact).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"
DIST="${REPO_ROOT}/dist"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

# ── Helper: list features that have an install.bash ─────────────────────────
_features=()
while IFS= read -r _json; do
  _dir="$(dirname "$_json")"
  _name="$(basename "$_dir")"
  [[ -f "${_dir}/install.bash" ]] && _features+=("$_name")
done < <(find "${REPO_ROOT}/src" -maxdepth 2 -name "devcontainer-feature.json" | sort)

# ── Checks ────────────────────────────────────────────────────────────────────

check "dist/sysset-all.tar.gz exists" test -f "${DIST}/sysset-all.tar.gz"
check "dist/ does not contain get.sh (it lives in repo root)" test ! -f "${DIST}/get.sh"
check "dist/scripts/ absent after build" test ! -d "${DIST}/scripts"
check "repo root get.sh exists" test -f "${REPO_ROOT}/get.sh"
check "repo root get.bash exists" test -f "${REPO_ROOT}/get.bash"

for _feat in "${_features[@]}"; do
  _tarball="${DIST}/sysset-${_feat}.tar.gz"
  check "sysset-${_feat}.tar.gz exists" test -f "$_tarball"
  check "sysset-${_feat}: contains install.sh" \
    bash -c "tar -tzf '${_tarball}' | grep -qx '\./install\.sh\|install\.sh'"
  check "sysset-${_feat}: contains install.bash" \
    bash -c "tar -tzf '${_tarball}' | grep -qx '\./install\.bash\|install\.bash'"
  check "sysset-${_feat}: contains _lib/" \
    bash -c "tar -tzf '${_tarball}' | grep -q '_lib/'"
done

# sysset-all.tar.gz contains only per-feature tarballs (no runtime scripts).
for _feat in "${_features[@]}"; do
  check "sysset-all: contains sysset-${_feat}.tar.gz" \
    bash -c "tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'sysset-${_feat}\.tar\.gz'"
done
check "sysset-all: does NOT contain scripts/sysset.sh" \
  bash -c "! tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'sysset\.sh'"
check "sysset-all: does NOT contain get.sh" \
  bash -c "! tar -tzf '${DIST}/sysset-all.tar.gz' | grep -qx '\./get\.sh\|get\.sh'"

reportResults
