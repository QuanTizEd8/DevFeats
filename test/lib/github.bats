#!/usr/bin/env bats
# Unit tests for lib/github.sh
#
# Network calls are replaced with function stubs or fake curl binaries that
# return canned JSON fixtures.

bats_require_minimum_version 1.7.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib net.sh
  reload_lib github.sh
  # Stub out the network-layer helpers so no real connections are made.
  net__ensure_fetch_tool() {
    _NET_FETCH_TOOL=curl
    _NET_CA_CERTS_OK=true
    return 0
  }
  net__ensure_ca_certs() {
    _NET_CA_CERTS_OK=true
    return 0
  }
  export -f net__ensure_fetch_tool net__ensure_ca_certs
}

# ---------------------------------------------------------------------------
# github__latest_tag  (parsing logic)
# ---------------------------------------------------------------------------

@test "github__latest_tag parses tag_name from JSON" {
  github__fetch_release_json() {
    echo '{"tag_name": "v1.2.3", "name": "Release v1.2.3"}'
    return 0
  }
  export -f github__fetch_release_json
  run --separate-stderr github__latest_tag "owner/repo"
  assert_output "v1.2.3"
  assert_success
}

@test "github__latest_tag fails when fetch returns empty" {
  github__fetch_release_json() { return 1; }
  net__fetch_url_stdout() { return 1; }
  export -f net__fetch_url_stdout
  export -f github__fetch_release_json
  run github__latest_tag "owner/repo"
  assert_failure
}

@test "github__latest_tag falls back to releases/latest HTML redirect parsing" {
  github__fetch_release_json() { return 1; }
  net__fetch_url_stdout() {
    printf '%s\n' '<a href="/owner/repo/releases/tag/v9.8.7">latest</a>'
    return 0
  }
  export -f github__fetch_release_json net__fetch_url_stdout
  run github__latest_tag "owner/repo"
  assert_success
  assert_output "v9.8.7"
}

@test "github__latest_tag fails when tag_name is absent from JSON" {
  github__fetch_release_json() {
    echo '{"name": "oops no tag_name field"}'
    return 0
  }
  export -f github__fetch_release_json
  run github__latest_tag "owner/repo"
  assert_failure
  assert_output --partial "could not parse tag_name"
}

# ---------------------------------------------------------------------------
# github__release_tags  (parsing logic via fake curl)
# ---------------------------------------------------------------------------

@test "github__release_tags parses multiple tags from JSON array" {
  # net__fetch_url_stdout is used inside; override it to return canned JSON.
  net__fetch_url_stdout() {
    printf '%s\n' '[{"tag_name":"v3.0.0"},{"tag_name":"v2.1.0"},{"tag_name":"v2.0.0"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__release_tags "owner/repo"
  assert_output "v3.0.0
v2.1.0
v2.0.0"
}

@test "github__release_tags accepts --per_page option" {
  net__fetch_url_stdout() {
    printf '%s\n' '[{"tag_name":"v1.0.0"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__release_tags "owner/repo" --per_page 5
  assert_output "v1.0.0"
  assert_success
}

@test "github__release_tags rejects unknown option" {
  run github__release_tags "owner/repo" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "github__release_tags --retries replays after repeated API list failure" {
  # Stub the list helper (not net__fetch_url_stdout): sourcing json/ospkg pulls
  # net.sh back in and would replace a net stub before github__release_tags runs.
  _gh_list_n=0
  _github__api_list_field() {
    _gh_list_n=$((_gh_list_n + 1))
    if [ "$_gh_list_n" -lt 3 ]; then
      return 1
    fi
    printf '%s\n' 'v1.0.0'
    return 0
  }
  export -f _github__api_list_field
  run --separate-stderr github__release_tags "owner/repo" --retries 3 --retry-delay 0
  assert_success
  assert_output "v1.0.0"
  assert_stderr --partial "retrying"
}

# ---------------------------------------------------------------------------
# github__release_asset_urls  (parsing logic via fake fetch_release_json)
# ---------------------------------------------------------------------------

@test "github__release_asset_urls returns download URLs" {
  github__fetch_release_json() {
    # Write canned JSON to --dest file if provided.
    local _dest=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dest)
          shift
          _dest="$1"
          shift
          ;;
        *) shift ;;
      esac
    done
    local _json
    _json='{"assets":[
      {"browser_download_url":"https://example.com/tool-linux-x86_64.tar.gz"},
      {"browser_download_url":"https://example.com/tool-darwin-arm64.tar.gz"}
    ]}'
    if [ -n "$_dest" ]; then
      printf '%s\n' "$_json" > "$_dest"
    else
      printf '%s\n' "$_json"
    fi
    return 0
  }
  export -f github__fetch_release_json
  run github__release_asset_urls "owner/repo"
  assert_output --partial "https://example.com/tool-linux-x86_64.tar.gz"
  assert_output --partial "https://example.com/tool-darwin-arm64.tar.gz"
}

@test "github__release_asset_urls applies --filter" {
  github__fetch_release_json() {
    local _dest=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dest)
          shift
          _dest="$1"
          shift
          ;;
        *) shift ;;
      esac
    done
    local _json
    _json='{"assets":[
      {"browser_download_url":"https://example.com/tool-linux-x86_64.tar.gz"},
      {"browser_download_url":"https://example.com/tool-darwin-arm64.tar.gz"}
    ]}'
    [ -n "$_dest" ] && printf '%s\n' "$_json" > "$_dest" || printf '%s\n' "$_json"
    return 0
  }
  export -f github__fetch_release_json
  run github__release_asset_urls "owner/repo" --filter "linux"
  assert_output "https://example.com/tool-linux-x86_64.tar.gz"
  refute_output --partial "darwin"
}

# ---------------------------------------------------------------------------
# github__fetch_release_json  (option parsing and header injection)
# ---------------------------------------------------------------------------

@test "github__fetch_release_json rejects unknown option" {
  run github__fetch_release_json "owner/repo" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "github__fetch_release_json includes Authorization header when GITHUB_TOKEN is set" {
  # Override net__fetch_url_stdout to print all its arguments so we can inspect headers.
  net__fetch_url_stdout() {
    printf '%s\n' "$@"
    return 0
  }
  export -f net__fetch_url_stdout
  GITHUB_TOKEN="mytoken" run github__fetch_release_json "owner/repo"
  assert_output --partial "Authorization: Bearer mytoken"
}

@test "github__fetch_release_json builds a tag URL when --tag is given" {
  net__fetch_url_stdout() {
    printf '%s\n' "$@"
    return 0
  }
  export -f net__fetch_url_stdout
  run github__fetch_release_json "owner/repo" --tag "v2.0.0"
  assert_output --partial "releases/tags/v2.0.0"
}

# ---------------------------------------------------------------------------
# github__release_json_tag_name / github__release_json_id (single-release file)
# ---------------------------------------------------------------------------

@test "github__release_json_tag_name and github__release_json_id parse minified JSON" {
  _fixture="${BATS_TEST_TMPDIR}/release.json"
  printf '%s' '{"url":"u","id":708,"author":{"id":9959},"tag_name":"v2.304.8","draft":false}' > "$_fixture"
  run github__release_json_tag_name "$_fixture"
  assert_success
  assert_output "v2.304.8"
  run github__release_json_id "$_fixture"
  assert_success
  assert_output "708"
}

@test "github__release_json_id reads root id when assets appear first (minified)" {
  _fixture="${BATS_TEST_TMPDIR}/release-assets-first.json"
  # Root id must not be confused with the first asset id in a one-line payload.
  printf '%s' '{"assets":[{"id":111,"name":"a.zip"}],"tag_name":"v9.0","id":999888}' > "$_fixture"
  run github__release_json_tag_name "$_fixture"
  assert_success
  assert_output "v9.0"
  run github__release_json_id "$_fixture"
  assert_success
  assert_output "999888"
}

# ---------------------------------------------------------------------------
# github__release_json_digest_for_asset
# ---------------------------------------------------------------------------

@test "github__release_json_digest_for_asset prints lowercase hex from sha256 digest" {
  _fixture="${BATS_TEST_TMPDIR}/release-fzf-digest.json"
  printf '%s' '{"assets":[{"name":"fzf-0.71.0-linux_amd64.tar.gz","digest":"sha256:ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789"}]}' > "$_fixture"
  run github__release_json_digest_for_asset "$_fixture" "fzf-0.71.0-linux_amd64.tar.gz"
  assert_success
  assert_output "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
}

@test "github__release_json_digest_for_asset fails when digest absent" {
  _fixture="${BATS_TEST_TMPDIR}/release-no-digest.json"
  printf '%s' '{"assets":[{"name":"tool.tar.gz","size":3}]}' > "$_fixture"
  run github__release_json_digest_for_asset "$_fixture" "tool.tar.gz"
  assert_failure
}

@test "github__release_json_digest_for_asset fails when asset name mismatches" {
  _fixture="${BATS_TEST_TMPDIR}/release-wrong-name.json"
  printf '%s' '{"assets":[{"name":"other.tar.gz","digest":"sha256:00"}]}' > "$_fixture"
  run github__release_json_digest_for_asset "$_fixture" "tool.tar.gz"
  assert_failure
}

@test "github__release_json_tag_name fails for missing file" {
  run github__release_json_tag_name "${BATS_TEST_TMPDIR}/does-not-exist.json"
  assert_failure
}

# ---------------------------------------------------------------------------
# github__release_asset_urls  (--tag forwarding)
# ---------------------------------------------------------------------------

@test "github__release_asset_urls accepts --tag option" {
  github__fetch_release_json() {
    local _dest=""
    while [ "$#" -gt 0 ]; do
      [ "$1" = "--dest" ] && {
        shift
        _dest="$1"
        shift
        continue
      }
      shift
    done
    [ -n "$_dest" ] && printf '{"assets":[{"browser_download_url":"https://example.com/v2.tar.gz"}]}\n' > "$_dest"
    return 0
  }
  export -f github__fetch_release_json
  run github__release_asset_urls "owner/repo" --tag "v2.0.0"
  assert_success
  assert_output "https://example.com/v2.tar.gz"
}

# ---------------------------------------------------------------------------
# _github__api_list_field  (shared extraction helper)
# ---------------------------------------------------------------------------

@test "_github__api_list_field extracts name field from JSON array" {
  net__fetch_url_stdout() {
    printf '%s\n' '[{"name":"v2.0.0"},{"name":"v1.9.0"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/owner/repo/tags?per_page=100" "name"
  assert_output "v2.0.0
v1.9.0"
  assert_success
}

@test "_github__api_list_field extracts every tag_name from minified one-line JSON" {
  net__fetch_url_stdout() {
    printf '%s' '[{"tag_name":"24.7.1-2","id":1},{"tag_name":"24.7.1-1","id":2},{"tag_name":"4.8.4-0","id":3}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/conda-forge/miniforge/releases?per_page=100" "tag_name"
  assert_success
  assert_output "24.7.1-2
24.7.1-1
4.8.4-0"
}

@test "_github__api_list_field returns 1 when fetch fails" {
  net__fetch_url_stdout() { return 1; }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/owner/repo/tags?per_page=100" "name"
  assert_failure
}

@test "_github__api_list_field returns 1 on empty response" {
  net__fetch_url_stdout() {
    printf ''
    return 0
  }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/owner/repo/tags?per_page=100" "name"
  assert_failure
}

@test "_github__api_list_field returns 1 when the requested field is absent" {
  net__fetch_url_stdout() {
    printf '{"message":"API rate limit exceeded"}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/owner/repo/tags?per_page=100" "name"
  assert_failure
}

# ---------------------------------------------------------------------------
# github__tags
# ---------------------------------------------------------------------------

@test "github__tags prints tag names from /tags endpoint" {
  net__fetch_url_stdout() {
    printf '%s\n' '[{"name":"v2.48.0"},{"name":"v2.47.2"},{"name":"v2.47.1"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__tags "git/git"
  assert_output "v2.48.0
v2.47.2
v2.47.1"
  assert_success
}

@test "github__tags accepts --per_page option" {
  # Stub _github__api_get to echo the URL as a "name" field so it passes
  # through json extraction and appears in the final output.
  _github__api_get() {
    printf '[{"name":"%s"}]\n' "$1"
    return 0
  }
  export -f _github__api_get
  run github__tags "git/git" --per_page 50
  assert_output --partial "tags?per_page=50"
  assert_success
}

@test "github__tags rejects unknown option" {
  run github__tags "git/git" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "github__tags fails when API call fails" {
  net__fetch_url_stdout() { return 1; }
  export -f net__fetch_url_stdout
  run github__tags "git/git"
  assert_failure
  assert_output --partial "failed to reach GitHub API"
}

@test "github__tags fails when the tags response has no name fields" {
  net__fetch_url_stdout() {
    printf '{"message":"API rate limit exceeded"}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__tags "git/git"
  assert_failure
  assert_output --partial "failed to reach GitHub API"
}

# ---------------------------------------------------------------------------
# github__release_tags still works after refactor
# ---------------------------------------------------------------------------

@test "github__release_tags still parses tag_name via shared helper" {
  net__fetch_url_stdout() {
    printf '%s\n' '[{"tag_name":"v3.0.0"},{"tag_name":"v2.9.0"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__release_tags "owner/repo"
  assert_output "v3.0.0
v2.9.0"
  assert_success
}

# ---------------------------------------------------------------------------
# github__pick_release_asset  (heuristic asset selector)
#
# All tests stub github__release_asset_urls, os__arch, and os__kernel to
# avoid network calls and make assertions deterministic.
# ---------------------------------------------------------------------------

# Helper: stub os__arch and os__kernel to fixed values.
_stub_arch_kernel() {
  _STUB_ARCH="$1"
  _STUB_KERNEL="$2"
  export _STUB_ARCH _STUB_KERNEL
  os__arch() { printf '%s\n' "$_STUB_ARCH"; }
  os__kernel() { printf '%s\n' "$_STUB_KERNEL"; }
  export -f os__arch os__kernel
}

# Helper: stub github__release_asset_urls to print the given newline-separated URLs.
_stub_urls() {
  _STUB_URLS="$1"
  export _STUB_URLS
  github__release_asset_urls() {
    printf '%s\n' "$_STUB_URLS"
    return 0
  }
  export -f github__release_asset_urls
}

# --- basic success / failure ------------------------------------------------

@test "github__pick_release_asset returns the single matching URL" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset fails when no assets are returned" {
  _stub_arch_kernel "x86_64" "Linux"
  github__release_asset_urls() { return 1; }
  export -f github__release_asset_urls
  run github__pick_release_asset "owner/repo"
  assert_failure
}

@test "github__pick_release_asset fails when asset list is empty" {
  _stub_arch_kernel "x86_64" "Linux"
  github__release_asset_urls() {
    printf ''
    return 0
  }
  export -f github__release_asset_urls
  run github__pick_release_asset "owner/repo"
  assert_failure
  assert_output --partial "no assets found"
}

@test "github__pick_release_asset rejects unknown option" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool.tar.gz"
  run github__pick_release_asset "owner/repo" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

# --- --asset-regex pre-filter -----------------------------------------------

@test "github__pick_release_asset --asset-regex: exact single match returns immediately" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux-arm64.tar.gz
https://example.com/tool-darwin-amd64.tar.gz"
  run github__pick_release_asset "owner/repo" --asset-regex "linux-amd64"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset --asset-regex: no match returns failure" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz"
  run github__pick_release_asset "owner/repo" --asset-regex "does-not-match"
  assert_failure
  assert_output --partial "matched no assets"
}

# --- negative arch filter ---------------------------------------------------

@test "github__pick_release_asset removes other-arch assets on x86_64" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux-arm64.tar.gz
https://example.com/tool-linux-aarch64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset removes other-arch assets on aarch64" {
  _stub_arch_kernel "aarch64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux-arm64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-arm64.tar.gz"
}

@test "github__pick_release_asset skips arch filter when it would produce empty list" {
  # Only one asset; it would be removed by the bad-arch filter (no arch keyword
  # matches x86_64 negative patterns).  The filter must be skipped.
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux.tar.gz"
}

# --- negative platform filter -----------------------------------------------

@test "github__pick_release_asset removes Windows assets on Linux" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-windows-amd64.exe
https://example.com/tool-Windows-amd64.zip"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset removes macOS assets on Linux" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-darwin-amd64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset removes Linux assets on Darwin" {
  _stub_arch_kernel "x86_64" "Darwin"
  _stub_urls "https://example.com/tool-darwin-amd64.tar.gz
https://example.com/tool-linux-amd64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-darwin-amd64.tar.gz"
}

# --- negative misc filter ---------------------------------------------------

@test "github__pick_release_asset removes checksum files" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux-amd64.tar.gz.sha256
https://example.com/Checksums.txt"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset removes .deb and .rpm packages" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-amd64.deb
https://example.com/tool-x86_64.rpm"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset skips misc filter when it would empty the list" {
  # All assets are .txt — the misc filter would remove everything, so it must
  # be skipped and we still get exactly one candidate.
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/install.txt"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/install.txt"
}

# --- positive arch tiebreaker -----------------------------------------------

@test "github__pick_release_asset prefers explicit arch match (amd64) on x86_64" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset prefers explicit arch match (arm64) on aarch64" {
  _stub_arch_kernel "aarch64" "Linux"
  _stub_urls "https://example.com/tool-linux-arm64.tar.gz
https://example.com/tool-linux.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-arm64.tar.gz"
}

# --- positive static/musl tiebreaker ----------------------------------------

@test "github__pick_release_asset prefers musl/static build when multiple remain" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64-musl.tar.gz
https://example.com/tool-linux-amd64-gnu.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64-musl.tar.gz"
}

# --- ambiguity error --------------------------------------------------------

@test "github__pick_release_asset fails when more than one candidate remains" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64-v1.tar.gz
https://example.com/tool-linux-amd64-v2.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_failure
  assert_output --partial "ambiguous"
}

@test "github__pick_release_asset lists filenames on ambiguity" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64-v1.tar.gz
https://example.com/tool-linux-amd64-v2.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_failure
  assert_output --partial "tool-linux-amd64-v1.tar.gz"
  assert_output --partial "tool-linux-amd64-v2.tar.gz"
}

# --- --tag forwarding -------------------------------------------------------

@test "github__pick_release_asset passes --tag to github__release_asset_urls" {
  _stub_arch_kernel "x86_64" "Linux"
  github__release_asset_urls() {
    # Capture the arguments and echo back the tag value found.
    while [ "$#" -gt 0 ]; do
      [ "$1" = "--tag" ] && {
        printf 'TAG=%s\n' "$2"
        return 0
      }
      shift
    done
    printf 'NO_TAG\n'
    return 0
  }
  export -f github__release_asset_urls
  run github__pick_release_asset "owner/repo" --tag "v1.2.3"
  assert_success
  assert_output "TAG=v1.2.3"
}

# ---------------------------------------------------------------------------
# github__resolve_version
# ---------------------------------------------------------------------------

@test "github__resolve_version empty spec delegates to github__latest_tag" {
  github__latest_tag() {
    printf 'v3.0.1\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" ""
  assert_success
  assert_output "v3.0.1
3.0.1"
}

@test "github__resolve_version 'stable' spec delegates to github__latest_tag" {
  github__latest_tag() {
    printf 'v2.5.0\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" "stable"
  assert_success
  assert_output "v2.5.0
2.5.0"
}

@test "github__resolve_version omitted spec defaults to stable" {
  github__latest_tag() {
    printf 'v4.0.0\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo"
  assert_success
  assert_output "v4.0.0
4.0.0"
}

@test "github__resolve_version non-v tag prefix is stripped in bare version" {
  github__latest_tag() {
    printf 'jq-1.7.1\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" "stable"
  assert_success
  assert_output "jq-1.7.1
1.7.1"
}

@test "github__resolve_version stable failure propagates" {
  github__latest_tag() { return 1; }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" ""
  assert_failure
  assert_output --partial "could not resolve stable release"
}

@test "github__resolve_version 'latest' uses list API, not github__latest_tag" {
  github__latest_tag() {
    echo "⛔ unexpected call to github__latest_tag" >&2
    return 1
  }
  _github__api_list_field() {
    printf 'v5.0.0-beta.1\n'
    return 0
  }
  export -f github__latest_tag _github__api_list_field
  run github__resolve_version "owner/repo" "latest"
  assert_success
  assert_output "v5.0.0-beta.1
5.0.0-beta.1"
}

@test "github__resolve_version 'latest' failure propagates" {
  _github__api_list_field() { return 1; }
  export -f _github__api_list_field
  run github__resolve_version "owner/repo" "latest"
  assert_failure
  assert_output --partial "could not retrieve releases"
}

@test "github__resolve_version exact X.Y.Z spec resolves to matching stable tag" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2.3"
  assert_success
  assert_output "v1.2.3
1.2.3"
}

@test "github__resolve_version v-prefixed spec is equivalent to bare spec" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "v1.2.3"
  assert_success
  assert_output "v1.2.3
1.2.3"
}

@test "github__resolve_version MAJOR spec resolves to newest stable matching tag" {
  _github__api_get() {
    printf '[{"tag_name":"v3.0.0","prerelease":false,"draft":false},{"tag_name":"v2.9.1","prerelease":false,"draft":false},{"tag_name":"v2.9.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "2"
  assert_success
  assert_output "v2.9.1
2.9.1"
}

@test "github__resolve_version MAJOR.MINOR spec resolves to newest stable matching tag" {
  _github__api_get() {
    printf '[{"tag_name":"v2.10.0","prerelease":false,"draft":false},{"tag_name":"v2.9.1","prerelease":false,"draft":false},{"tag_name":"v2.9.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "2.9"
  assert_success
  assert_output "v2.9.1
2.9.1"
}

@test "github__resolve_version spec '2' does not match tag 'v20.0.0'" {
  _github__api_get() {
    printf '[{"tag_name":"v20.0.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "2"
  assert_failure
  assert_output --partial "no stable release matching '2'"
}

@test "github__resolve_version spec '1.2' does not match tag 'v1.20.0'" {
  _github__api_get() {
    printf '[{"tag_name":"v1.20.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2"
  assert_failure
  assert_output --partial "no stable release matching '1.2'"
}

@test "github__resolve_version pre-releases are skipped when resolving numeric spec" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3-rc.1","prerelease":true,"draft":false},{"tag_name":"v1.2.2","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2"
  assert_success
  assert_output "v1.2.2
1.2.2"
}

@test "github__resolve_version draft releases are skipped when resolving numeric spec" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3","prerelease":false,"draft":true},{"tag_name":"v1.2.2","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2"
  assert_success
  assert_output "v1.2.2
1.2.2"
}

@test "github__resolve_version spec 'X.Y.Z' matches build-suffix tag 'X.Y.Z-N'" {
  _github__api_get() {
    printf '[{"tag_name":"24.11.0-1","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "24.11.0"
  assert_success
  assert_output "24.11.0-1
24.11.0-1"
}

@test "github__resolve_version jq-style prefixed spec matches tag with same prefix" {
  _github__api_get() {
    printf '[{"tag_name":"jq-1.7.1","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "jq-1.7.1"
  assert_success
  assert_output "jq-1.7.1
1.7.1"
}

@test "github__resolve_version finds match on page 2 when page 1 has only pre-releases" {
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"tag_name":"v2.%d.0-rc.1","prerelease":true,"draft":false}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *\&page=2)
        printf '[{"tag_name":"v2.0.0","prerelease":false,"draft":false}]\n'
        return 0
        ;;
      *)
        echo "⛔ unexpected page: $1" >&2
        return 1
        ;;
    esac
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "2"
  assert_success
  assert_output "v2.0.0
2.0.0"
}

@test "github__resolve_version stops pagination immediately after match is found" {
  # Page 2 is a full page (100 items) — without early exit the function would
  # request page 3; the catch-all arm fails to prove page 3 is never fetched.
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"tag_name":"v0.%d.0","prerelease":true,"draft":false}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *\&page=2)
        local i
        printf '[{"tag_name":"v1.0.0","prerelease":false,"draft":false}'
        for i in $(seq 1 99); do
          printf ',{"tag_name":"v0.%d.1","prerelease":true,"draft":false}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *)
        echo "⛔ unexpected page beyond page 2: $1" >&2
        return 1
        ;;
    esac
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1"
  assert_success
  assert_output "v1.0.0
1.0.0"
}

@test "github__resolve_version fails when no stable release matches spec" {
  _github__api_get() {
    printf '[{"tag_name":"v3.0.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "9"
  assert_failure
  assert_output --partial "no stable release matching '9'"
}

@test "github__resolve_version spec with no numeric content fails immediately" {
  _github__api_get() {
    echo "⛔ unexpected API call" >&2
    return 1
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "abc"
  assert_failure
  assert_output --partial "no numeric version content"
}

@test "github__resolve_version rejects unknown option" {
  run github__resolve_version "owner/repo" "--bogus"
  assert_failure
  assert_output --partial "unknown option"
}

@test "github__resolve_version rejects extra positional argument" {
  run github__resolve_version "owner/repo" "1.2.3" "extra"
  assert_failure
  assert_output --partial "unexpected positional"
}

# ---------------------------------------------------------------------------
# github__release_tags --all pagination
# ---------------------------------------------------------------------------

@test "github__release_tags --all walks pages until a short page" {
  # Fake _github__api_get returns 100-item page 1, 3-item page 2, empty page 3.
  # Patterns MUST anchor on '&page=' (with leading '&') so they don't false-match
  # the 'per_page=100' substring (which also contains 'page=1').
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"tag_name":"p1-%d"}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *\&page=2)
        printf '[{"tag_name":"p2-1"},{"tag_name":"p2-2"},{"tag_name":"p2-3"}]\n'
        return 0
        ;;
      *)
        printf '[]\n'
        return 0
        ;;
    esac
  }
  export -f _github__api_get
  run github__release_tags "owner/repo" --all
  assert_success
  # Expect 103 lines total.
  [ "${#lines[@]}" -eq 103 ]
  [ "${lines[0]}" = "p1-1" ]
  [ "${lines[99]}" = "p1-100" ]
  [ "${lines[100]}" = "p2-1" ]
  [ "${lines[102]}" = "p2-3" ]
}

@test "github__release_tags without --all fetches only first page" {
  # Non-paginated call contains 'per_page=100' and has NO '&page=' segment.
  # Match the paginated-call case on '&page=' so it doesn't false-match the
  # 'per_page=…' substring.
  _github__api_get() {
    case "$1" in
      *\&page=*)
        echo "⛔ unexpected paginated call: $1" >&2
        return 1
        ;;
      *per_page=100*)
        printf '[{"tag_name":"only-1"},{"tag_name":"only-2"}]\n'
        return 0
        ;;
    esac
  }
  export -f _github__api_get
  run github__release_tags "owner/repo"
  assert_success
  assert_output "only-1
only-2"
}

@test "github__release_tags --all short single page terminates after one request" {
  # 50 items on page=1 with per_page=100 → short page → terminate without
  # fetching page=2. Pattern must anchor on '&page=' to avoid false-matching
  # 'per_page=100'.
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 50); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"tag_name":"t%d"}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *)
        echo "⛔ unexpected subsequent page request: $1" >&2
        return 1
        ;;
    esac
  }
  export -f _github__api_get
  run github__release_tags "owner/repo" --all
  assert_success
  [ "${#lines[@]}" -eq 50 ]
  [ "${lines[0]}" = "t1" ]
  [ "${lines[49]}" = "t50" ]
}

@test "github__tags --all walks pages until a short page" {
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"name":"t1-%d"}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *\&page=2)
        printf '[{"name":"t2-1"},{"name":"t2-2"}]\n'
        return 0
        ;;
      *)
        printf '[]\n'
        return 0
        ;;
    esac
  }
  export -f _github__api_get
  run github__tags "owner/repo" --all
  assert_success
  [ "${#lines[@]}" -eq 102 ]
  [ "${lines[101]}" = "t2-2" ]
}

# ---------------------------------------------------------------------------
# github__fetch_release_asset_tarball
# ---------------------------------------------------------------------------

@test "github__fetch_release_asset_tarball downloads asset when API omits digest" {
  _dest="$(mktemp "${BATS_TEST_TMPDIR}/gh-asset.XXXXXX")"
  github__fetch_release_json() {
    while [ $# -gt 0 ]; do
      case "$1" in
        --dest)
          printf '%s' '{"assets":[]}' > "$2"
          return 0
          ;;
        *) shift ;;
      esac
    done
    return 1
  }
  net__fetch_url_file() {
    printf 'tar-bytes' > "$2"
    return 0
  }
  export -f github__fetch_release_json net__fetch_url_file
  SYSSET_RELEASE_BASE="https://dl.invalid/r" run github__fetch_release_asset_tarball "o/r" "t1" "a.tgz" "$_dest"
  assert_success
  run cat "$_dest"
  assert_output "tar-bytes"
  rm -f "$_dest"
}
