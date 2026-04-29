#!/usr/bin/env bash
# get/feature_lifecycle_cwd.sh — Verify --workspace-folder and
# --lifecycle-command-dir set the cwd for feature-mode lifecycle commands.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="fake-cwd-feature"
_VER="0.0.1-test"
_stage="$(mktemp -d)"
_dest_ws="$(mktemp -d)"
_dest_lc="$(mktemp -d)"
_log="$(mktemp)"
_sentinel_ws="${_dest_ws}/cwd.txt"
_sentinel_lc="${_dest_lc}/cwd.txt"
_PORT=18537
trap 'stop_file_server; rm -rf "$_stage" "$_dest_ws" "$_dest_lc" "$_log"' EXIT

# Build the synthetic feature tarball.
mkdir -p "${_stage}/root"
cat > "${_stage}/root/install.sh" << 'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "${_stage}/root/install.sh"
cat > "${_stage}/root/devcontainer-feature.json" << EOF
{
  "id": "${_FEAT}",
  "version": "${_VER}",
  "name": "Fake cwd probe",
  "postCreateCommand": {
    "probe": "pwd > '${_sentinel_ws}'"
  }
}
EOF
tar -C "${_stage}/root" -czf "${_stage}/sysset-${_FEAT}.tar.gz" .

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/sysset/${_FEAT}:${_VER}" \
  "${_stage}/sysset-${_FEAT}.tar.gz"

# ── 1. --workspace-folder sets default cwd for lifecycle commands ────────────
check "install.sh --workspace-folder <ws> runs hook in <ws>" \
  sudo -E bash "${REPO_ROOT}/install.sh" --log_file "$_log" \
  --workspace-folder "$_dest_ws" "${_FEAT}:${_VER}"
check "sentinel file under --workspace-folder is present" \
  test -f "$_sentinel_ws"
check "sentinel contents equal the --workspace-folder value" \
  bash -c "[[ \"\$(cat '$_sentinel_ws')\" == '$_dest_ws' ]]"

# ── 2. --lifecycle-command-dir overrides the cwd for lifecycle commands ──────
# Rewrite the tarball to target the second sentinel path, then re-push.
cat > "${_stage}/root/devcontainer-feature.json" << EOF
{
  "id": "${_FEAT}",
  "version": "${_VER}",
  "name": "Fake cwd probe 2",
  "postCreateCommand": {
    "probe": "pwd > '${_sentinel_lc}'"
  }
}
EOF
tar -C "${_stage}/root" -czf "${_stage}/sysset-${_FEAT}.tar.gz" .
push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/sysset/${_FEAT}:${_VER}" \
  "${_stage}/sysset-${_FEAT}.tar.gz"

check "install.sh --lifecycle-command-dir <lc> runs hook in <lc>" \
  sudo -E bash "${REPO_ROOT}/install.sh" \
  --workspace-folder "$_dest_ws" \
  --lifecycle-command-dir "$_dest_lc" \
  "${_FEAT}:${_VER}"
check "sentinel under --lifecycle-command-dir present" \
  test -f "$_sentinel_lc"
check "sentinel contents equal --lifecycle-command-dir value" \
  bash -c "[[ \"\$(cat '$_sentinel_lc')\" == '$_dest_lc' ]]"

reportResults
