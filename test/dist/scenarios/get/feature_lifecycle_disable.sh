#!/usr/bin/env bash
# get/feature_lifecycle_disable.sh — Verify --no-lifecycle and
# --no-feature-lifecycle-command suppress lifecycle hooks in feature mode.
#
# What this tests:
#   • --no-lifecycle (feature-mode-only shorthand) suppresses ALL hooks.
#   • --no-feature-lifecycle-command <phase> suppresses one phase only,
#     leaving the install and other phases intact.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="fake-lifecycle-probe"
_VER="0.0.1-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-feature-lifecycle-disable"
_stage="$(mktemp -d)"
_PORT=18536
_log1="$(mktemp)"
_log2="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_stage" "$_log1" "$_log2"' EXIT

# Build the synthetic feature tarball: no-op installer + three lifecycle phases.
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
  "name": "Fake lifecycle probe",
  "onCreateCommand": "echo 'sysset-probe:on-create-ran'",
  "updateContentCommand": "echo 'sysset-probe:update-content-ran'",
  "postCreateCommand": "echo 'sysset-probe:post-create-ran'"
}
EOF
tar -C "${_stage}/root" -czf "${_stage}/sysset-${_FEAT}.tar.gz" .
mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${_stage}/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
unset SYSSET_VERSION

# ── 1. --no-lifecycle skips every feature-level phase ───────────────────────
check "install.sh ${_FEAT}@${_VER} --no-lifecycle succeeds" \
  sudo -E bash "${REPO_ROOT}/install.sh" --log_file "$_log1" --no-lifecycle "${_FEAT}@${_VER}"
check "no probe strings in log when --no-lifecycle is set" \
  bash -c "! grep -q 'sysset-probe:' '$_log1'"

# ── 2. --no-feature-lifecycle-command postCreateCommand skips that phase ────
check "install.sh ${_FEAT}@${_VER} --no-feature-lifecycle-command postCreateCommand succeeds" \
  sudo -E bash "${REPO_ROOT}/install.sh" --log_file "$_log2" \
  --no-feature-lifecycle-command postCreateCommand "${_FEAT}@${_VER}"
check "onCreate and updateContent hooks ran when only postCreate is disabled" \
  bash -c "grep -q 'sysset-probe:on-create-ran' '$_log2' && grep -q 'sysset-probe:update-content-ran' '$_log2'"
check "postCreate hook was NOT invoked when that phase is disabled" \
  bash -c "! grep -q 'sysset-probe:post-create-ran' '$_log2'"

reportResults
