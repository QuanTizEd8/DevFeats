#!/usr/bin/env bash
# build-offline-kit.sh — Assemble devfeats-vX.Y.Z.tar.gz offline kit from dist/ + manifest base JSON.
#
# Usage:
#   bash scripts/build-offline-kit.sh <bundle-tag> <dist-dir> <manifest-base.json> [output-tarball]
#
#   bundle-tag       e.g. v1.2.0 (manifest ``version`` field)
#   dist-dir         Directory containing devfeats-<feature>.tar.gz from build-artifacts.sh
#   manifest-base    JSON from: compute-bundle-tag.py --manifest
#   output-tarball   Optional path for the kit (default: <dist-dir>/../devfeats-vX.Y.Z.tar.gz)
#
# Requires: Python 3 (stdlib), tar, gzip.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/.." && pwd)"

_TAG="${1:?bundle tag required}"
_DIST="$(cd "${2:?dist dir}" && pwd)"
_BASE="${3:?manifest base json}"
if [[ ! -f "$_BASE" ]]; then
  echo "⛔ manifest base JSON not found or not a file: ${_BASE}" >&2
  exit 1
fi
_kit_tag="${_TAG}"
[[ "${_kit_tag}" == v* ]] || _kit_tag="v${_kit_tag}"
if [[ $# -ge 4 && -n "${4-}" ]]; then
  _OUT="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
else
  _OUT="$(dirname "${_DIST}")/devfeats-${_kit_tag}.tar.gz"
fi

_STAGING="$(mktemp -d)"
trap 'rm -rf "${_STAGING}"' EXIT

bash "${_SCRIPT_DIR}/python.sh" "${_SCRIPT_DIR}/offline_kit_assemble.py" \
  "${_TAG}" "${_DIST}" "${_BASE}" "${_STAGING}"

tar -czf "${_OUT}" -C "${_STAGING}" .
echo "✅ Offline kit: ${_OUT}" >&2
