#!/usr/bin/env bash
# get/feature_lifecycle_warn_other_feature.sh — Verify that install.sh warns
# when a devfeats-unknown feature lifecycle hook references another feature's
# resource and still completes successfully.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="fake-warn-lifecycle-probe"
_VER="0.0.1-test"
_stage="$(mktemp -d)"
_log="$(mktemp)"
_PORT=18539
trap 'stop_file_server; rm -rf "$_stage" "$_log"' EXIT

mkdir -p "${_stage}/root"
cat > "${_stage}/root/install.sh" << 'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "${_stage}/root/install.sh"
# NOTE: $additionalProperties is intentionally NOT a real install.bash option.
# install.bash should warn about it and continue rather than fail.
cat > "${_stage}/root/devcontainer-feature.json" << EOF
{
  "id": "${_FEAT}",
  "version": "${_VER}",
  "name": "Fake warn lifecycle probe",
  "customizations": {
    "devfeats": {
      "dependsOn": "quantized8/devfeats/other-feature"
    }
  },
  "postCreateCommand": "echo 'devfeats-probe:warn-lifecycle-ran'"
}
EOF
tar -C "${_stage}/root" -czf "${_stage}/devfeats-${_FEAT}.tar.gz" .

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"

push_oci_feature "${SYSSET_REGISTRY_HOST}" \
  "quantized8/devfeats/${_FEAT}:${_VER}" \
  "${_stage}/devfeats-${_FEAT}.tar.gz"

check "install.sh succeeds despite unresolvable dependency hint" \
  sudo -E bash "${REPO_ROOT}/install.sh" --log_file "$_log" "${_FEAT}:${_VER}"

check "postCreateCommand still ran" \
  bash -c "grep -q 'devfeats-probe:warn-lifecycle-ran' '$_log'"

reportResults
