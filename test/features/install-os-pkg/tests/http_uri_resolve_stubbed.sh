#!/usr/bin/env bash
# Stub net fetch; verify uri__resolve materializes an http:// manifest for install-os-pkg-style YAML.
set -euo pipefail

# shellcheck source=test/support/assert.sh
source dev-container-features-test-lib

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/uri.sh"

# Stub the uri-layer fetch seam (after sourcing uri.sh) so net.sh loading cannot overwrite it.
_uri__net_fetch() {
  printf '%s\n' 'packages:' '  - tree' > "$2"
}
export -f _uri__net_fetch

_dest="$(mktemp "${TMPDIR:-/tmp}/ospkg-uri.XXXXXX")"
uri__resolve "https://stub.internal/manifest.yaml" "$_dest"

check "stub manifest lists a package" grep -q '^  - tree' "$_dest"

reportResults
