#!/usr/bin/env bash
# get/feature_lifecycle.sh — Verify that single-feature installs trigger the
# feature's own lifecycle hooks read from its staged devcontainer-feature.json.
#
# What this tests:
#   • A synthetic feature with onCreateCommand / updateContentCommand /
#     postCreateCommand hooks in its devcontainer-feature.json.
#   • After install.bash installs the feature, all three hooks run in order.
#   • Each hook echoes a well-known probe string; all three must appear in
#     the captured log_file.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="fake-lifecycle-probe"
_VER="0.0.1-test"
_stage="$(mktemp -d)"
_PORT=18535
_log="$(mktemp)"
trap 'stop_file_server; rm -rf "$_stage" "$_log"' EXIT

# Build the synthetic feature tarball: no-op installer + three lifecycle phases.
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
  "name": "Fake lifecycle probe",
  "onCreateCommand": "echo 'sysset-probe:on-create-ran'",
  "updateContentCommand": "echo 'sysset-probe:update-content-ran'",
  "postCreateCommand": "echo 'sysset-probe:post-create-ran'"
}
EOF
tar -C "${_stage}/root" -czf "${_stage}/sysset-${_FEAT}.tar.gz" .

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/sysset/${_FEAT}:${_VER}" \
  "${_stage}/sysset-${_FEAT}.tar.gz"

# Run feature-mode install. The feature declares string-form hooks for all three
# phases; each echoes a well-known probe string to stdout.
check "install.sh installs ${_FEAT}:${_VER} (feature mode)" \
  sudo -E bash "${REPO_ROOT}/install.sh" --log_file "$_log" "${_FEAT}:${_VER}"

check "onCreateCommand hook was executed" \
  bash -c "grep -q 'sysset-probe:on-create-ran' '$_log'"
check "updateContentCommand hook was executed" \
  bash -c "grep -q 'sysset-probe:update-content-ran' '$_log'"
check "postCreateCommand hook was executed" \
  bash -c "grep -q 'sysset-probe:post-create-ran' '$_log'"

reportResults
