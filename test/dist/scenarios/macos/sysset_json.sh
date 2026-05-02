#!/usr/bin/env bash
# macos/devfeats_json.sh — Verify that install.bash processes a devcontainer.json and
# installs features on macOS using a local HTTP file server.
#
# setup-shim is used because it requires no package manager (no ospkg__run
# call), works on macOS as root, and produces verifiable shim artifacts.
# Requires: root for install.bash manifest mode (os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"
# shellcheck source=test/lib/offline_kit_mirror.sh
. "${REPO_ROOT}/test/lib/offline_kit_mirror.sh"

DIST="${REPO_ROOT}/dist"

_BUNDLE="v99.99.0-test"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-macos-json"
_tmp="$(mktemp -d)"
_fakebin="${_tmp}/fakebin"
mkdir -p "${_fakebin}"
mkdir -p "${_MIRROR}"
mkdir -p "${_MIRROR}/setup-shim/${_VER}"
cp "${DIST}/devfeats-setup-shim.tar.gz" "${_MIRROR}/setup-shim/${_VER}/"
_PAYLOAD="${DIST}/devfeats-setup-shim.tar.gz"
_HASH="$(shasum -a 256 "$_PAYLOAD" | awk '{print $1}')"
offline_kit_publish_mirror "${_MIRROR}" "${_BUNDLE}" "${DIST}" "setup-shim:${_VER}"

cat > "${_fakebin}/oras" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1-}" in
  version)
    echo "Version: 1.2.0"
    ;;
  repo)
    echo "latest"
    echo "${SYSSET_TEST_REF_TAG:-99.99.0-test}"
    ;;
  manifest)
    cat <<JSON
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:${SYSSET_TEST_PAYLOAD_SHA}"}]}
JSON
    ;;
  pull)
    _outdir=""
    while [[ $# -gt 0 ]]; do
      if [[ "${1}" == "-o" ]]; then
        _outdir="${2}"
        shift 2
      else
        shift
      fi
    done
    mkdir -p "${_outdir}"
    cp "${SYSSET_TEST_PAYLOAD_TGZ}" "${_outdir}/devcontainer-feature-${SYSSET_TEST_FEATURE_ID}.tgz"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${_fakebin}/oras"

_PORT=18552
_manifest_dir="$(mktemp -d)"
trap 'stop_file_server; rm -rf "${_MIRROR}" "$_manifest_dir" "${_tmp}"' EXIT

start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL

_manifest="${_manifest_dir}/devcontainer.json"
cat > "$_manifest" << EOF
{
  "name": "macos ${_BUNDLE}",
  "features": {
    "ghcr.io/quantized8/devfeats/setup-shim": {}
  }
}
EOF

check "install.bash processes devcontainer.json on macOS (bundle-pinned via SYSSET_VERSION)" \
  sudo env PATH="${_fakebin}:$PATH" \
  SYSSET_RAW_BASE="$SYSSET_RAW_BASE" \
  SYSSET_BASE_URL="$SYSSET_BASE_URL" \
  SYSSET_TEST_PAYLOAD_TGZ="${_PAYLOAD}" \
  SYSSET_TEST_PAYLOAD_SHA="${_HASH}" \
  SYSSET_TEST_FEATURE_ID="setup-shim" \
  SYSSET_TEST_REF_TAG="${_VER}" \
  SYSSET_VERSION="${_BUNDLE}" \
  bash "${REPO_ROOT}/install.bash" "$_manifest"

check "code shim installed by setup-shim (macOS)" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
