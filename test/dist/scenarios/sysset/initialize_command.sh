#!/usr/bin/env bash
# sysset/initialize_command.sh — Exercise host-side `initializeCommand`.
#
# What this tests:
#   • A string initializeCommand runs via /bin/sh -c before any feature install.
#   • --no-initialize-command suppresses it entirely.
#   • A failing initializeCommand aborts the whole run (exit non-zero, no
#     features are installed).
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_VER="99.99.0-test"

_PORT=18546
_manifest_dir="$(mktemp -d)"
_state_dir="$(mktemp -d)"
_sentinel="${_state_dir}/init-ran"
_skip_sentinel="${_state_dir}/init-skipped"
trap 'stop_file_server; rm -rf "$_manifest_dir" "$_state_dir"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/sysset/install-pixi:${_VER}" \
  "${DIST}/sysset-install-pixi.tar.gz"

# ── 1. initializeCommand runs before install ─────────────────────────────────
_mfa="${_manifest_dir}/with-init.json"
cat > "$_mfa" << EOF
{
  "name": "init test",
  "initializeCommand": "touch '${_sentinel}'",
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:${_VER}": { "version": "0.66.0" }
  }
}
EOF

check "install.bash runs initializeCommand and then installs features" \
  bash "${REPO_ROOT}/install.bash" "$_mfa"
check "initializeCommand sentinel was created" \
  test -f "$_sentinel"
check "install-pixi installed despite initializeCommand" \
  command -v pixi

# ── 2. --no-initialize-command skips it ──────────────────────────────────────
_mfb="${_manifest_dir}/skip-init.json"
cat > "$_mfb" << EOF
{
  "name": "skip-init test",
  "initializeCommand": "touch '${_skip_sentinel}'",
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:${_VER}": { "version": "0.66.0" }
  }
}
EOF

check "install.bash honors --no-initialize-command" \
  bash "${REPO_ROOT}/install.bash" --no-initialize-command "$_mfb"
check "initializeCommand sentinel was NOT created when suppressed" \
  bash -c "[ ! -f '${_skip_sentinel}' ]"

# ── 3. Failing initializeCommand aborts the run ──────────────────────────────
_mfc="${_manifest_dir}/fail-init.json"
cat > "$_mfc" << EOF
{
  "name": "fail-init test",
  "initializeCommand": "false",
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:${_VER}": { "version": "0.66.0" }
  }
}
EOF

fail_check "install.bash exits non-zero when initializeCommand fails" \
  bash "${REPO_ROOT}/install.bash" "$_mfc"

reportResults
