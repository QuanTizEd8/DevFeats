#!/usr/bin/env bash
# NETRC fetched via uri__resolve from http:// (stubbed net__fetch_url_file).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/support/assert.sh
source "${REPO_ROOT}/test/support/assert.sh"

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/uri.sh"

# Stub the uri-layer fetch seam (after sourcing uri.sh) so net.sh loading cannot overwrite it.
_uri__net_fetch() {
  printf 'machine github.com login x password y\n' > "$2"
}
export -f _uri__net_fetch

_dest="$(mktemp "${TMPDIR:-/tmp}/pixi-netrc-uri.XXXXXX")"
chmod 600 "$_dest"
uri__resolve "http://stub.example/netrc" "$_dest"

check "resolved netrc mentions machine" grep -q '^machine github.com' "$_dest"

reportResults
