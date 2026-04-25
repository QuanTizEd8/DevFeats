#!/usr/bin/env bash
# build-artifacts.sh — Assemble standalone distribution artifacts into dist/.
#
# Usage:
#   bash scripts/build-artifacts.sh [<tag>]
#
#   <tag>   Release tag (used only for informational output; default: "dev")
#
# Outputs (all under dist/):
#   sysset-<feature>.tar.gz       One tarball per feature
#   sysset-all.tar.gz             All feature tarballs bundled for offline use
#
# Tarball layout (per feature):
#   install.sh        POSIX sh bootstrap (handles bash>=4 on any platform)
#   install.bash      Real bash>=4 installer
#   _lib/             Full lib/ copy
#   devcontainer-feature.json  Feature metadata (ordering, lifecycle hooks) — from sync-src
#   dependencies/     Optional — only when src/<feature>/dependencies/ exists
#   files/            Optional — only when src/<feature>/files/ exists
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/git_helpers.sh
. "${_SCRIPT_DIR}/git_helpers.sh"

_REPO_ROOT="$(git__require_repo_root)"
_TAG="${1:-dev}"

_DIST_DIR="${_REPO_ROOT}/dist"
_SRC_DIR="${_REPO_ROOT}/src"
_FEATURES_DIR="${_REPO_ROOT}/features"

echo "ℹ️  Building artifacts for tag: '${_TAG}'" >&2

# ── Pre-flight: require src/ to be already populated by scripts/sync-src.py ──
# build-artifacts.sh is a consumer of sync output — it does not call sync
# itself to stay usable in environments without Python+PyYAML (e.g. containers).
# Run 'python3 scripts/sync-src.py' (or 'just sync') before invoking this script.
_check_feature=$(find "${_SRC_DIR}" -maxdepth 2 -name 'install.bash' 2> /dev/null | head -1)
if [[ -z "$_check_feature" ]]; then
  echo "⛔ src/ is not populated. Run 'python3 scripts/sync-src.py' first." >&2
  exit 1
fi

# ── Step 1: Clean and create dist/ ──────────────────────────────────────────
rm -rf "${_DIST_DIR}"
mkdir -p "${_DIST_DIR}"

# ── Step 2: Auto-discover features from features/ (assembled artifacts are in src/) ─
_feature_dirs=()
while IFS= read -r _bash; do
  _dir="$(dirname "$_bash")"
  _name="$(basename "$_dir")"
  _src_dir="${_SRC_DIR}/${_name}"
  [[ -f "${_src_dir}/install.bash" ]] && _feature_dirs+=("$_src_dir")
done < <(find "${_FEATURES_DIR}" -maxdepth 2 -name "install.bash" | sort)

if [[ ${#_feature_dirs[@]} -eq 0 ]]; then
  echo "⛔ No features with an install.bash found." >&2
  exit 1
fi

echo "ℹ️  Found ${#_feature_dirs[@]} features." >&2

# ── Step 3: Build per-feature tarballs ──────────────────────────────────────
for _feature_dir in "${_feature_dirs[@]}"; do
  _name="$(basename "$_feature_dir")"
  _staging="${_DIST_DIR}/tmp/${_name}"
  _tarball="${_DIST_DIR}/sysset-${_name}.tar.gz"

  mkdir -p "$_staging"

  # Always include: bootstrap and real installer (with _lib/)
  cp "${_feature_dir}/install.sh" "${_staging}/install.sh"
  cp "${_feature_dir}/install.bash" "${_staging}/install.bash"
  cp -r "${_feature_dir}/_lib/" "${_staging}/_lib/"

  if [[ -f "${_feature_dir}/devcontainer-feature.json" ]]; then
    cp "${_feature_dir}/devcontainer-feature.json" "${_staging}/devcontainer-feature.json"
  fi

  # Optional: dependencies/
  if [[ -d "${_feature_dir}/dependencies" ]]; then
    cp -r "${_feature_dir}/dependencies/" "${_staging}/dependencies/"
  fi

  # Optional: files/
  if [[ -d "${_feature_dir}/files" ]]; then
    cp -r "${_feature_dir}/files/" "${_staging}/files/"
  fi

  tar -czf "$_tarball" -C "$_staging" .
  rm -rf "$_staging"
  echo "✅ ${_name}: built sysset-${_name}.tar.gz" >&2
done

rm -rf "${_DIST_DIR}/tmp"

# ── Step 4: Build all-bundle ────────────────────────────────────────────────
# Contains only feature tarballs — for offline use with SYSSET_BASE_URL=file://...
_feature_tarballs=()
while IFS= read -r _t; do
  _feature_tarballs+=("$(basename "$_t")")
done < <(find "${_DIST_DIR}" -maxdepth 1 -name "sysset-*.tar.gz" | sort)

(
  cd "${_DIST_DIR}"
  tar -czf sysset-all.tar.gz "${_feature_tarballs[@]}"
)
echo "✅ Built dist/sysset-all.tar.gz" >&2

echo "" >&2
echo "✅ Build complete. Artifacts in dist/:" >&2
ls -lh "${_DIST_DIR}/" >&2
