#!/usr/bin/env bash
# devfeats/frozen_lockfile_missing_entry.sh
# Verifies --frozen-lockfile fails when a manifest feature key is missing.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_tmp="$(mktemp -d)"
_manifest="${_tmp}/devcontainer.json"
_lockfile="${_tmp}/devcontainer-lock.json"
_port=18567
trap 'stop_file_server; rm -rf "${_tmp}"' EXIT

cat > "${_manifest}" << 'EOF'
{
  "name": "frozen-missing",
  "features": {
    "ghcr.io/example/features/demo": {}
  }
}
EOF

cat > "${_lockfile}" << 'EOF'
{
  "schemaVersion": "1",
  "features": {}
}
EOF

start_file_server "${REPO_ROOT}" "${_port}"
export SYSSET_RAW_BASE="http://127.0.0.1:${_port}"

fail_check "--frozen-lockfile fails when entry is missing" \
  bash "${REPO_ROOT}/install.bash" --download-only --frozen-lockfile "${_lockfile}" "${_manifest}"

reportResults
