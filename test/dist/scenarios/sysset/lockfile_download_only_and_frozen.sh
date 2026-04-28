#!/usr/bin/env bash
# sysset/lockfile_download_only_and_frozen.sh
# Verifies:
# 1) --lockfile writes resolved OCI refs in --download-only mode
# 2) --frozen-lockfile installs using the lockfile ref without tag resolution
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_tmp="$(mktemp -d)"
_fakebin="${_tmp}/fakebin"
_work="${_tmp}/work"
_registry="${_tmp}/registry"
_manifest="${_tmp}/devcontainer.json"
_lockfile="${_tmp}/devcontainer-lock.json"
_payload="${_tmp}/feature.tgz"
_port=18566
trap 'stop_file_server; rm -rf "${_tmp}"' EXIT

mkdir -p "${_fakebin}" "${_work}" "${_registry}"
mkdir -p "${_work}/payload"
printf '%s\n' '#!/usr/bin/env sh' > "${_work}/payload/install.sh"
printf '%s\n' '{}' > "${_work}/payload/devcontainer-feature.json"
tar -czf "${_payload}" -C "${_work}/payload" .
_hash="$(shasum -a 256 "${_payload}" | awk '{print $1}')"

cat > "${_manifest}" <<'EOF'
{
  "name": "lockfile check",
  "features": {
    "ghcr.io/example/features/demo": {}
  }
}
EOF

cat > "${_fakebin}/oras" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1-}" in
  version)
    echo "Version: 1.2.0"
    ;;
  login)
    exit 0
    ;;
  repo)
    if [[ "${SYSSET_TEST_FROZEN_MODE:-0}" == "1" ]]; then
      # If frozen mode still tries to resolve tags, fail hard.
      exit 1
    fi
    echo "1.0.0"
    ;;
  manifest)
    cat <<JSON
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:${SYSSET_TEST_PAYLOAD_SHA}"}]}
JSON
    ;;
  pull)
    _ref="${2-}"
    [[ "${_ref}" == "${SYSSET_TEST_EXPECT_REF}" ]] || exit 1
    _out=""
    while [[ $# -gt 0 ]]; do
      if [[ "${1}" == "-o" ]]; then
        _out="${2}"
        shift 2
      else
        shift
      fi
    done
    mkdir -p "${_out}"
    cp "${SYSSET_TEST_PAYLOAD}" "${_out}/demo.tgz"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${_fakebin}/oras"

start_file_server "${REPO_ROOT}" "${_port}"
export SYSSET_RAW_BASE="http://127.0.0.1:${_port}"
export PATH="${_fakebin}:$PATH"
export SYSSET_LOCAL_REGISTRY="${_registry}"
export SYSSET_TEST_PAYLOAD="${_payload}"
export SYSSET_TEST_PAYLOAD_SHA="${_hash}"

export SYSSET_TEST_EXPECT_REF="ghcr.io/example/features/demo:latest"
check "--lockfile writes resolved ref in download-only mode" \
  bash "${REPO_ROOT}/install.bash" --download-only --compatible-prefix "ghcr.io/example/features/" --lockfile "${_lockfile}" "${_manifest}"

check "lockfile contains expected resolved ref" \
  bash -c "jq -e '(.features | to_entries | length) == 1 and ((.features | to_entries[0].value.resolved) == \"ghcr.io/example/features/demo:latest\")' \"${_lockfile}\" >/dev/null"

export SYSSET_TEST_FROZEN_MODE=1
export SYSSET_TEST_EXPECT_REF="ghcr.io/example/features/demo:latest"
check "--frozen-lockfile uses locked ref without tag resolution" \
  bash "${REPO_ROOT}/install.bash" --download-only --compatible-prefix "ghcr.io/example/features/" --frozen-lockfile "${_lockfile}" "${_manifest}"

reportResults
