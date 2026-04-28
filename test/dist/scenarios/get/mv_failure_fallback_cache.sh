#!/usr/bin/env bash
# get/mv_failure_fallback_cache.sh — Regression for post-pull mv failure.
#
# What this tests:
#   • OCI pull succeeds but moving pulled archive to destination fails.
#   • install.bash does not exit early on mv failure.
#   • It falls back to local manifest cache and succeeds.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

_registry="${_tmp}/registry"
_fakebin="${_tmp}/fakebin"
mkdir -p "${_registry}" "${_fakebin}"

_payload_tgz="${REPO_ROOT}/dist/sysset-install-pixi.tar.gz"
if command -v sha256sum > /dev/null 2>&1; then
  _hex="$(sha256sum "$_payload_tgz" | awk '{print $1}')"
else
  _hex="$(shasum -a 256 "$_payload_tgz" | awk '{print $1}')"
fi
_dkey="sha256:${_hex}"
_ref="ghcr.io/quantized8/sysset/install-pixi:1.2.3"
_rel="features/ghcr.io/quantized8/sysset/install-pixi/sha256/${_hex}/"
_dest="${_registry}/${_rel}"
mkdir -p "$_dest"
tar -xzf "$_payload_tgz" -C "$_dest"

if command -v sha256sum > /dev/null 2>&1; then
  _c_install="$(sha256sum "${_dest}/install.sh" | awk '{print $1}')"
  _c_dcj="$(sha256sum "${_dest}/devcontainer-feature.json" | awk '{print $1}')"
else
  _c_install="$(shasum -a 256 "${_dest}/install.sh" | awk '{print $1}')"
  _c_dcj="$(shasum -a 256 "${_dest}/devcontainer-feature.json" | awk '{print $1}')"
fi

cat > "${_registry}/manifest.json" << EOF
{
  "schemaVersion": "2.0.0",
  "refs": {
    "${_ref}": "${_dkey}"
  },
  "digests": {
    "${_dkey}": {
      "relativePath": "${_rel}",
      "fetchedAt": "2026-04-28T00:00:00Z",
      "sourceRefs": ["${_ref}"],
      "checksums": {
        "install.sh": "${_c_install}",
        "devcontainer-feature.json": "${_c_dcj}"
      }
    }
  }
}
EOF

# Fake oras:
# - version: satisfy oci__ensure_oras
# - repo tags: resolve install-pixi -> 1.2.3
# - pull: succeed and materialize a *.tgz payload
cat > "${_fakebin}/oras" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1-}" in
  version)
    echo "Version: 1.2.0"
    ;;
  repo)
    # oras repo tags <repo>
    echo "1.2.3"
    ;;
  pull)
    # oras pull <ref> -o <dir>
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
    cp "${SYSSET_TEST_PAYLOAD_TGZ}" "${_outdir}/devcontainer-feature-install-pixi.tgz"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${_fakebin}/oras"

# Force mv failure to exercise fallback path after successful pull.
cat > "${_fakebin}/mv" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${_fakebin}/mv"

export PATH="${_fakebin}:$PATH"
export SYSSET_TEST_PAYLOAD_TGZ="${_payload_tgz}"
export SYSSET_LOCAL_REGISTRY="${_registry}"

check "install.sh --download-only falls back to local cache when mv fails" \
  bash "${REPO_ROOT}/install.sh" --download-only install-pixi

reportResults
