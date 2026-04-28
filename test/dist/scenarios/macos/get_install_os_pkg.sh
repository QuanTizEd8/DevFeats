#!/usr/bin/env bash
# macos/get_install_os_pkg.sh — Verify install.sh downloads and installs a feature
# on macOS using a local HTTP file server.
#
# setup-shim is used because it requires no package manager (no ospkg__run
# call), works on macOS as root, and produces verifiable shim artifacts.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_FEAT="setup-shim"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-macos-get"
_tmp="$(mktemp -d)"
_fakebin="${_tmp}/fakebin"
mkdir -p "${_fakebin}"

mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"
_PAYLOAD="${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz"
_HASH="$(shasum -a 256 "$_PAYLOAD" | awk '{print $1}')"

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

_PORT=18551
trap 'stop_file_server; rm -rf "${_MIRROR}" "${_tmp}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL

check "install.sh installs setup-shim on macOS (rolling mode, explicit :version)" \
  sudo env PATH="${_fakebin}:$PATH" \
  SYSSET_RAW_BASE="$SYSSET_RAW_BASE" \
  SYSSET_BASE_URL="$SYSSET_BASE_URL" \
  SYSSET_TEST_PAYLOAD_TGZ="${_PAYLOAD}" \
  SYSSET_TEST_PAYLOAD_SHA="${_HASH}" \
  SYSSET_TEST_FEATURE_ID="${_FEAT}" \
  SYSSET_TEST_REF_TAG="${_VER}" \
  bash "${REPO_ROOT}/install.sh" "${_FEAT}:${_VER}"

check "code shim installed by setup-shim" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
