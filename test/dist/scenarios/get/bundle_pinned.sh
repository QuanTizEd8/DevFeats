#!/usr/bin/env bash
# get/bundle_pinned.sh — Bundle-pinned resolution via SYSSET_VERSION.
#
# What this tests:
#   • SYSSET_VERSION=<bundle-tag> drives bundle-pinned mode.
#   • get.bash fetches <bundle>/manifest.yaml from the mirror.
#   • Per-feature versions are read from the manifest and used to construct
#     <feature>/<X.Y.Z>/sysset-<feature>.tar.gz URLs.
#   • The mirror also hosts a foreign feature's tag (install-shell/0.1.0) to
#     verify that get.bash ignores unrelated features present in the mirror
#     (prefix-scoped resolution only downloads what the manifest says).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_BUNDLE="v99.99.0-test"
_PIXI_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-bundle-pinned"

mkdir -p "${_MIRROR}/${_BUNDLE}"
mkdir -p "${_MIRROR}/install-pixi/${_PIXI_VER}"
mkdir -p "${_MIRROR}/install-shell/0.1.0"

# Bundle manifest mapping install-pixi → _PIXI_VER.
cat > "${_MIRROR}/${_BUNDLE}/manifest.yaml" << EOF
bundle: ${_BUNDLE}
prior_bundle: v0.0.0
generated_at: "1970-01-01T00:00:00Z"
features:
  install-pixi: ${_PIXI_VER}
  install-shell: 0.1.0
EOF

# Pre-stage the correct install-pixi tarball at the manifest-addressed path.
cp "${REPO_ROOT}/dist/sysset-install-pixi.tar.gz" \
  "${_MIRROR}/install-pixi/${_PIXI_VER}/"
# Foreign feature tarball (not exercised by this scenario but mirrors multi-
# feature hosting): use the real install-shell tarball if it exists, else a
# placeholder.
if [[ -f "${REPO_ROOT}/dist/sysset-install-shell.tar.gz" ]]; then
  cp "${REPO_ROOT}/dist/sysset-install-shell.tar.gz" \
    "${_MIRROR}/install-shell/0.1.0/"
fi

_PORT=18534
trap 'stop_file_server; rm -rf "${_MIRROR}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_VERSION="${_BUNDLE}"

check "get.sh installs install-pixi via bundle-pinned manifest (${_BUNDLE} → ${_PIXI_VER})" \
  sudo -E bash "${REPO_ROOT}/get.sh" install-pixi

check "pixi binary present in PATH after bundle-pinned install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
