#!/usr/bin/env bash
# sysset/fail_partial.sh — Verify that install.bash reports failure when one
# feature fails, after attempting features from the devcontainer.
#
# Strategy: devcontainer includes a non-existent OCI feature alongside a
# valid one. The bogus "does-not-exist" ref must fail without blocking
# install-pixi.
#
# Requires: root (install.bash manifest mode calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"
_VER="99.99.0-test"

_PORT=18542
_manifest_dir="$(mktemp -d)"
_run_log="$(mktemp)"
trap 'stop_file_server; rm -rf "$_manifest_dir" "$_run_log"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

# Push install-pixi only; "does-not-exist" is intentionally absent.
push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/sysset/install-pixi:${_VER}" \
  "${DIST}/sysset-install-pixi.tar.gz"

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "partial-fail test",
  "features": {
    "ghcr.io/quantized8/sysset/does-not-exist": {},
    "ghcr.io/quantized8/sysset/install-pixi:${_VER}": { "version": "0.66.0" }
  }
}
EOF

# install.bash should exit non-zero overall.
check "install.bash exits non-zero when a feature fails" \
  bash -c "bash \"${REPO_ROOT}/install.bash\" \"$_manifest\" >\"$_run_log\" 2>&1; test \$? -ne 0"

check "unknown feature id is reported in failed feature summary" \
  bash -c "grep -q 'failed:.*does-not-exist' '$_run_log'"

check "install-pixi still installed despite partial failure" \
  command -v pixi

reportResults
