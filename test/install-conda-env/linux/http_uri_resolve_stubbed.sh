#!/usr/bin/env bash
# Stub net__fetch_url_file and verify uri__resolve handles http:// for conda env YAML.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/uri.sh"

# Stub the uri-layer fetch seam (after sourcing uri.sh) so net.sh loading cannot overwrite it.
_uri__net_fetch() {
  printf 'name: from-http-stub\ndependencies:\n  - numpy\n' > "$2"
}
export -f _uri__net_fetch

_dest="$(mktemp "${TMPDIR:-/tmp}/conda-uri.XXXXXX")"
uri__resolve "http://stub.example/env.yml" "$_dest"

check "stubbed http YAML has expected name" grep -q 'from-http-stub' "$_dest"

reportResults
