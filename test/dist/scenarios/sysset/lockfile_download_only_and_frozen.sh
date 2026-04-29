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
if command -v sha256sum > /dev/null 2>&1; then
  _hash="$(sha256sum "${_payload}" | awk '{print $1}')"
else
  _hash="$(shasum -a 256 "${_payload}" | awk '{print $1}')"
fi

cat > "${_manifest}" << 'EOF'
{
  "name": "lockfile check",
  "features": {
    "ghcr.io/example/features/demo": {}
  }
}
EOF

cat > "${_fakebin}/oras" << 'EOF'
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
    echo "latest"
    ;;
  manifest)
    cat <<JSON
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:${SYSSET_TEST_PAYLOAD_SHA}"}]}
JSON
    ;;
  pull)
    _out=""
    _ref=""
    _skip_next=0
    for _a in "${@:2}"; do
      if [[ "$_skip_next" -eq 1 ]]; then
        _out="$_a"
        _skip_next=0
      elif [[ "$_a" == "-o" || "$_a" == "--output" ]]; then
        _skip_next=1
      elif [[ "$_a" != -* ]]; then
        _ref="$_a"
      fi
    done
    [[ "${_ref}" == "${SYSSET_TEST_EXPECT_REF}" ]] || exit 1
    [[ -n "${_out}" ]] || exit 1
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
  bash "${REPO_ROOT}/install.bash" --download-only --lockfile "${_lockfile}" "${_manifest}"

check "lockfile contains expected resolved ref" \
  bash -c "jq -e '(.features | to_entries | length) == 1 and ((.features | to_entries[0].value.resolved) == \"ghcr.io/example/features/demo:latest\")' \"${_lockfile}\" >/dev/null"

export SYSSET_TEST_FROZEN_MODE=1
export SYSSET_TEST_EXPECT_REF="ghcr.io/example/features/demo:latest"
check "--frozen-lockfile uses locked ref without tag resolution" \
  bash "${REPO_ROOT}/install.bash" --download-only --frozen-lockfile "${_lockfile}" "${_manifest}"

reportResults
