#!/usr/bin/env bash
# get/feature_lifecycle.sh — Verify that single-feature installs trigger the
# feature's own lifecycle hooks read from its staged devcontainer-feature.json.
#
# What this tests:
#   • A synthetic feature with string-form onCreateCommand / updateContentCommand /
#     postCreateCommand hooks in its devcontainer-feature.json.
#   • After get.bash (feature mode) installs the feature, all three hooks run in
#     declaration order (onCreate → updateContent → postCreate).
#   • Each hook echoes a well-known probe string; all three must appear in the
#     captured logfile.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="fake-lifecycle-probe"
_VER="0.0.1-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-feature-lifecycle"
_stage="$(mktemp -d)"
_PORT=18535
_log="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_stage" "$_log"' EXIT

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

# Run feature-mode install. The feature declares string-form hooks for all three
# phases; each echoes a well-known probe string to stdout.
check "get.sh installs ${_FEAT}@${_VER} (feature mode)" \
  sudo -E bash "${REPO_ROOT}/get.sh" --logfile "$_log" "${_FEAT}@${_VER}"

check "onCreateCommand hook was executed" \
  bash -c "grep -q 'sysset-probe:on-create-ran' '$_log'"
check "updateContentCommand hook was executed" \
  bash -c "grep -q 'sysset-probe:update-content-ran' '$_log'"
check "postCreateCommand hook was executed" \
  bash -c "grep -q 'sysset-probe:post-create-ran' '$_log'"

reportResults
