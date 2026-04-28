#!/usr/bin/env bash
# get/install_pixi.sh — Rolling per-feature mode with an explicit :version spec.
#
# What this tests:
#   • SYSSET_BASE_URL override directs downloads to the local file-server.
#   • install.sh resolves `install-pixi:<ver>` without hitting the GitHub API
#     (exact 3-part spec → direct tag construction).
#   • URL scheme is the new <feature>/<X.Y.Z>/sysset-<feature>.tar.gz layout.
#   • The tarball is extracted, the bootstrap runs, and pixi is installed.
#
# The mirror layout is intentionally sparse (only install-pixi) to verify
# that install.bash does not depend on sibling features being present.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

# ── Mirror layout ────────────────────────────────────────────────────────────
# Use a clearly fake version so api.github.com will never return a digest for
# install-pixi/<ver> (keeps the test hermetic vs. real releases).
_FEAT="install-pixi"
_VER="99.99.0-test"
_MIRROR="${REPO_ROOT}/test-mirror-get-install-pixi"
mkdir -p "${_MIRROR}/${_FEAT}/${_VER}"
cp "${REPO_ROOT}/dist/sysset-${_FEAT}.tar.gz" "${_MIRROR}/${_FEAT}/${_VER}/"

_PORT=18531
trap 'stop_file_server; rm -rf "${_MIRROR}"' EXIT
start_file_server "${REPO_ROOT}" "$_PORT"
export SYSSET_RAW_BASE="http://127.0.0.1:${_PORT}"
SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/$(basename "${_MIRROR}")"
export SYSSET_BASE_URL
unset SYSSET_VERSION

# ── Run install.sh ───────────────────────────────────────────────────────────────
# install-pixi requires root (ospkg__require_root); installs pixi to /usr/local/bin.
check "install.sh installs install-pixi:${_VER} successfully (rolling mode, explicit spec)" \
  sudo -E bash "${REPO_ROOT}/install.sh" "${_FEAT}:${_VER}"

check "pixi binary present in PATH after install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
