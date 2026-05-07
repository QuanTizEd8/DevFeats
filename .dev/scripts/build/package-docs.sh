#!/usr/bin/env bash
# Package the built Sphinx site into a GitHub Pages artifact.
#
# Usage:
#   bash package-docs.sh [<output-path>]
#
#   <output-path>   Path for the output tar file.
#                   Defaults to $WEBSITE_TAR_FILEPATH (set by the pixi docs env
#                   activation), falling back to docs/.build/website.tar.
#
# The output format matches the artifact expected by the GitHub Pages deployment
# API: a single uncompressed tar archive with no symlinks or hard links, produced
# with --dereference --hard-dereference so that any dangling references are
# resolved rather than embedded as links.
# Ref: https://github.com/actions/upload-pages-artifact/blob/main/action.yml
#
# Pre-flight: docs/.build/ must already be populated by 'just build-website'.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=.dev/scripts/git_helpers.sh
. "${_SCRIPT_DIR}/../git_helpers.sh"

_REPO_ROOT="$(git__require_repo_root)"
_OUTPUT="${1:-${_REPO_ROOT}/${WEBSITE_TAR_FILEPATH:-docs/.build/artifact.tar}}"
_BUILD_DIR="$(dirname "${_OUTPUT}")"

# ── Pre-flight ────────────────────────────────────────────────────────────────

if [[ ! -d "${_BUILD_DIR}" ]]; then
    echo "⛔ ${_BUILD_DIR}/ not found. Run 'just build-website' first." >&2
    exit 1
fi

# Require at least one HTML file — a directory with only the tar itself doesn't count.
_check=$(find "${_BUILD_DIR}" -name '*.html' 2>/dev/null | head -1)
if [[ -z "${_check}" ]]; then
    echo "⛔ ${_BUILD_DIR}/ contains no HTML files. Run 'just build-website' first." >&2
    exit 1
fi

# Warn if any symlinks are present — the Pages API rejects artifacts containing them.
_symlinks=$(find "${_BUILD_DIR}" -type l 2>/dev/null)
if [[ -n "${_symlinks}" ]]; then
    echo "⚠️  Symlinks found in docs/.build/ — the GitHub Pages API will reject this artifact:" >&2
    echo "${_symlinks}" >&2
    exit 1
fi

# ── Package ───────────────────────────────────────────────────────────────────

echo "ℹ️  Packaging docs/.build/ → ${_OUTPUT}" >&2

rm -f "${_OUTPUT}"

tar \
    --dereference \
    --hard-dereference \
    --directory "${_BUILD_DIR}" \
    -cvf "${_OUTPUT}" \
    --exclude=.git \
    --exclude=.github \
    --exclude='.[^/]*' \
    .

echo "✅ Packaged: ${_OUTPUT} ($(du -sh "${_OUTPUT}" | cut -f1))" >&2
