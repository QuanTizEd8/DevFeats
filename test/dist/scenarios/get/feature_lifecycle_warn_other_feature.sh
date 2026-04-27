#!/usr/bin/env bash
# get/feature_lifecycle_warn_other_feature.sh —
# Verify that --no-feature-lifecycle-command <other-feature-id>:<phase> in
# feature mode emits a warning and is otherwise ignored (the installed
# feature's lifecycle continues to run normally).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="fake-warn-probe"
_VER="0.0.1-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-feature-warn"
_stage="$(mktemp -d)"
_PORT=18538
_log="$(mktemp)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_stage" "$_log"' EXIT

# Build the synthetic feature tarball: no-op installer + a postCreate hook.
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
  "name": "Fake warn probe",
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

check "install.sh ignores disable entry for a different feature id (with warning)" \
  sudo -E bash "${REPO_ROOT}/install.sh" --log_file "$_log" \
  --no-feature-lifecycle-command "install-pixi:postCreateCommand" \
  "${_FEAT}@${_VER}"

check "warning was emitted about mismatched feature id" \
  bash -c "grep -Eq 'references a different feature|installed:' '$_log'"

# The installed feature's own hooks must still have run — the disable entry
# referenced a different feature id, so it is ignored after emitting the warning.
check "installed feature's postCreate hook ran despite the mismatched disable entry" \
  bash -c "grep -q 'sysset-probe:post-create-ran' '$_log'"

reportResults
