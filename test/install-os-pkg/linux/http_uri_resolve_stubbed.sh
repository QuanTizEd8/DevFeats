#!/usr/bin/env bash
# Stub net fetch; verify uri__resolve materializes an http:// manifest for install-os-pkg-style YAML.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

net__fetch_url_file() {
  printf '%s\n' 'packages:' '  - tree' > "$2"
}
export -f net__fetch_url_file

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/uri.sh"

_dest="$(mktemp "${TMPDIR:-/tmp}/ospkg-uri.XXXXXX")"
uri__resolve "https://stub.internal/manifest.yaml" "$_dest"

check "stub manifest lists a package" grep -q '^  - tree' "$_dest"

reportResults
