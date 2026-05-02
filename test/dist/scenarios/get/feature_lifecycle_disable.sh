#!/usr/bin/env bash
# get/feature_lifecycle_disable.sh — Verify --no-lifecycle-commands skips all
# lifecycle hooks.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="fake-lifecycle-disable-probe"
_VER="0.0.1-test"
_stage="$(mktemp -d)"
_sentinel="$(mktemp)"
rm -f "$_sentinel" # ensure it does not exist before the install
_log="$(mktemp)"
_PORT=18538
trap 'stop_file_server; rm -rf "$_stage" "$_log"' EXIT

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
  "name": "Fake disable lifecycle probe",
  "postCreateCommand": "touch '${_sentinel}'"
}
EOF
tar -C "${_stage}/root" -czf "${_stage}/devfeats-${_FEAT}.tar.gz" .

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/devfeats/${_FEAT}:${_VER}" \
  "${_stage}/devfeats-${_FEAT}.tar.gz"

check "install.sh --no-lifecycle-commands succeeds" \
  sudo -E bash "${REPO_ROOT}/install.sh" \
  --no-lifecycle "${_FEAT}:${_VER}"

check "lifecycle sentinel was NOT created" \
  bash -c "[[ ! -f '$_sentinel' ]]"

reportResults
