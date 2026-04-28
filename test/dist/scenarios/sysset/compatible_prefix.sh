#!/usr/bin/env bash
# sysset/compatible_prefix.sh — Verify that feature keys not matching any of
# the --compatible-prefix entries are warned about and skipped, not fatal.
#
# What this tests:
#   • The default compatible prefix "ghcr.io/quantized8/sysset/" is honored.
#   • An extra key under a different prefix (e.g. `ghcr.io/devcontainers/features/...`)
#     emits a "skip feature key (not sysset-compatible)" warning and does NOT
#     stop the installation of a compatible sibling feature.
#   • --compatible-prefix can be extended via CLI to include an additional
#     namespace; keys under the added prefix are accepted (and must resolve,
#     or an install failure surfaces through the normal error path).
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

DIST="${REPO_ROOT}/dist"

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-sysset-compat-prefix"
mkdir -p "${_MIRROR}"
mkdir -p "${_MIRROR}/install-pixi/${_VER}"
cp "${DIST}/sysset-install-pixi.tar.gz" "${_MIRROR}/install-pixi/${_VER}/"
offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${DIST}" "install-pixi:${_VER}"

_PORT=18547
_manifest_dir="$(mktemp -d)"
_log_file="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir" "$_log_file"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "compat ${_BUNDLE}",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/quantized8/sysset/install-pixi": { "version": "0.66.0" }
  }
}
EOF

check "install.bash completes even with non-sysset feature key present" \
  bash "${REPO_ROOT}/install.bash" --log_file "$_log_file" "$_manifest"

check "warning was emitted for non-compatible feature key" \
  bash -c "grep -q 'skip feature key (not sysset-compatible).*devcontainers/features/docker-in-docker' '$_log_file'"

check "install-pixi installed (sibling was not blocked by incompatible key)" \
  command -v pixi

reportResults
