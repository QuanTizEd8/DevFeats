#!/usr/bin/env bash
# get/bad_feature.sh — Verify that install.sh exits non-zero when the requested
# feature is unknown.
#
# Uses bundle-pinned mode with a manifest that lists install-pixi only. Asking
# for `does-not-exist` triggers the "feature not listed in bundle" error path
# deterministically (no dependency on GitHub API behaviour for the fake tag).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_BUNDLE="v99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-bad-feature"
mkdir -p "${_MIRROR}/${_BUNDLE}"
cat > "${_MIRROR}/${_BUNDLE}/manifest.yaml" << 'EOF'
bundle: v99.99.0-test
prior_bundle: v0.0.0
generated_at: "1970-01-01T00:00:00Z"
features:
  install-pixi: 99.99.0-test
EOF

_PORT=18533
trap 'stop_file_server; rm -rf "${_MIRROR}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
export SYSSET_VERSION="${_BUNDLE}"

# "does-not-exist" is not in the bundle manifest — install.sh should error out.
fail_check "install.sh exits non-zero for feature absent from bundle manifest" \
  bash "${REPO_ROOT}/install.sh" does-not-exist

reportResults
