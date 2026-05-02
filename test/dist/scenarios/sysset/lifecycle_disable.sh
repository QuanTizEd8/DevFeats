#!/usr/bin/env bash
# devfeats/lifecycle_disable.sh — Verify the grammar for disable flags for
# feature- and container-level lifecycle commands.
#
# What this tests (manifest mode):
#   • Container-level postCreateCommand runs by default.
#   • --no-container-lifecycle-command <phase> suppresses that phase
#     container-wide.
#   • --no-feature-lifecycle-command <feature>:<phase> suppresses one
#     feature's phase but leaves the container-level entry for that phase
#     running.
#   • --no-feature-lifecycle-command all suppresses every feature-level phase.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_OSP="${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml"
_VER="99.99.0-test"

_PORT=18548
_manifest_dir="$(mktemp -d)"
_state="$(mktemp -d)"
trap 'stop_file_server; rm -rf "$_manifest_dir" "$_state"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

for _f in install-pixi install-os-pkg; do
  push_oci_feature "${SYSSET_REGISTRY_HOST}" \
    "quantized8/devfeats/${_f}:${_VER}" \
    "${DIST}/devfeats-${_f}.tar.gz"
done

_manifest() {
  # $1 = state sentinel prefix
  local _p="$1"
  local _f="${_manifest_dir}/dc-${_p}.json"
  cat > "$_f" << EOF
{
  "name": "lifecycle-disable test",
  "features": {
    "ghcr.io/quantized8/devfeats/install-pixi:${_VER}": { "version": "0.66.0" },
    "ghcr.io/quantized8/devfeats/install-os-pkg:${_VER}": { "manifest": "${_OSP}" }
  },
  "postCreateCommand": "touch '${_state}/container-${_p}'"
}
EOF
  echo "$_f"
}

# ── 1. Default: container postCreateCommand runs ─────────────────────────────
_mf1="$(_manifest "default")"
check "install.bash runs container-level postCreateCommand by default" \
  bash "${REPO_ROOT}/install.bash" "$_mf1"
check "container sentinel present (default run)" \
  test -f "${_state}/container-default"

# ── 2. --no-container-lifecycle-command postCreateCommand skips container phase
_mf2="$(_manifest "skip-container")"
check "install.bash accepts --no-container-lifecycle-command postCreateCommand" \
  bash "${REPO_ROOT}/install.bash" \
  --no-container-lifecycle-command postCreateCommand "$_mf2"
check "container sentinel NOT created when its phase is suppressed" \
  bash -c "[ ! -f '${_state}/container-skip-container' ]"

# ── 3. --no-feature-lifecycle-command install-os-pkg:postCreateCommand ───────
# (suppresses only that feature's phase; container sentinel must still run)
_mf3="$(_manifest "skip-feature")"
check "install.bash accepts feature:phase disable form" \
  bash "${REPO_ROOT}/install.bash" \
  --no-feature-lifecycle-command "install-os-pkg:postCreateCommand" "$_mf3"
check "container sentinel still present with only feature phase skipped" \
  test -f "${_state}/container-skip-feature"

# ── 4. --no-feature-lifecycle-command all ────────────────────────────────────
_mf4="$(_manifest "skip-all-features")"
check "install.bash accepts --no-feature-lifecycle-command all" \
  bash "${REPO_ROOT}/install.bash" \
  --no-feature-lifecycle-command all "$_mf4"
check "container sentinel still present when only feature hooks are disabled" \
  test -f "${_state}/container-skip-all-features"

reportResults
