#!/usr/bin/env bash
# get/feature_lifecycle_cwd.sh — Verify --workspace-folder and
# --lifecycle-command-dir set the cwd for feature-mode lifecycle commands.
#
# Strategy:
#   We install a tiny fake feature tarball whose install.sh is a no-op and
#   whose devcontainer-feature.json contains a single object-form
#   postCreateCommand that writes `pwd` into a sentinel file. The sentinel
#   value must equal the flag value we passed on the command line.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="fake-cwd-feature"
_VER="0.0.1-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-feature-lifecycle-cwd"
_stage="$(mktemp -d)"
_dest_ws="$(mktemp -d)"
_dest_lc="$(mktemp -d)"
_log="$(mktemp)"
_sentinel_ws="${_dest_ws}/cwd.txt"
_sentinel_lc="${_dest_lc}/cwd.txt"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_stage" "$_dest_ws" "$_dest_lc" "$_log"' EXIT

# Build the synthetic feature tarball.
mkdir -p "${_stage}/root"
cat > "${_stage}/root/install.sh" << 'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "${_stage}/root/install.sh"
cat > "${_stage}/root/install.bash" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${_stage}/root/install.bash"
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

mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${_stage}/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

_PORT=18537
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
unset SYSSET_VERSION

# ── 1. --workspace-folder sets default cwd for lifecycle commands ────────────
check "get.sh --workspace-folder <ws> runs hook in <ws>" \
  sudo -E bash "${REPO_ROOT}/get.sh" --logfile "$_log" \
    --workspace-folder "$_dest_ws" "${_FEAT}@${_VER}"
check "sentinel file under --workspace-folder is present" \
  test -f "$_sentinel_ws"
check "sentinel contents equal the --workspace-folder value" \
  bash -c "[[ \"\$(cat '$_sentinel_ws')\" == '$_dest_ws' ]]"

# ── 2. --lifecycle-command-dir overrides the cwd for lifecycle commands ─────
# Rewrite the tarball to target the second sentinel path.
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
cp "${_stage}/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

check "get.sh --lifecycle-command-dir <lc> runs hook in <lc>" \
  sudo -E bash "${REPO_ROOT}/get.sh" \
    --workspace-folder "$_dest_ws" \
    --lifecycle-command-dir "$_dest_lc" \
    "${_FEAT}@${_VER}"
check "sentinel under --lifecycle-command-dir present" \
  test -f "$_sentinel_lc"
check "sentinel contents equal --lifecycle-command-dir value" \
  bash -c "[[ \"\$(cat '$_sentinel_lc')\" == '$_dest_lc' ]]"

reportResults
