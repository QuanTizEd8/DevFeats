#!/usr/bin/env bats
# Unit tests for lib/uri.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib uri.sh
}

@test "uri__classify recognizes http, gh, file, local, oci" {
  run uri__classify "https://example.com/a"
  assert_success
  assert_output "http"

  run uri__classify "gh://org/repo@main:path/to.txt"
  assert_success
  assert_output "gh"

  run uri__classify "file:///etc/hosts"
  assert_success
  assert_output "file"

  run uri__classify "/tmp/foo"
  assert_success
  assert_output "local"

  run uri__classify "oci://ghcr.io/org/img:v1"
  assert_success
  assert_output "oci"
}

@test "_uri__gh_to_https maps gh:// to raw.githubusercontent.com" {
  run bash -c "source '${LIB_ROOT}/uri.sh'; _uri__gh_to_https 'gh://quantized8/devfeats@v1.2.3:docs/README.md'"
  assert_success
  assert_output "https://raw.githubusercontent.com/quantized8/devfeats/v1.2.3/docs/README.md"
}

@test "uri__resolve copies a local file" {
  local _src="${BATS_TEST_TMPDIR}/src.txt"
  printf 'hello-local\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/dst.txt"
  run uri__resolve "$_src" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "hello-local"
}

@test "uri__resolve reads file:// path" {
  local _src="${BATS_TEST_TMPDIR}/x.yml"
  printf 'y: 1\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out.yml"
  run uri__resolve "file://${_src}" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "y: 1"
}

@test "uri__resolve gh:// uses net__fetch_url_file (stubbed)" {
  net__fetch_url_file() {
    printf '%s\n' "$1" > "$2"
  }
  export -f net__fetch_url_file

  local _dst="${BATS_TEST_TMPDIR}/gh.txt"
  run uri__resolve "gh://acme/demo@release:cfg/app.yaml" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "https://raw.githubusercontent.com/acme/demo/release/cfg/app.yaml"
}

@test "uri__resolve http(s) uses net__fetch_url_file with extra args (stubbed)" {
  net__fetch_url_file() {
    printf 'got\n' > "$2"
    [[ "$3" == "--header" && "$4" == "X-Test: 1" && "$5" == "--netrc-file" && "$6" == "/tmp/n" ]] || return 1
    return 0
  }
  export -f net__fetch_url_file

  local _dst="${BATS_TEST_TMPDIR}/http.bin"
  run uri__resolve "https://example.com/z" "$_dst" --header "X-Test: 1" --netrc-file "/tmp/n"
  assert_success
  run cat "$_dst"
  assert_output "got"
}

@test "uri__resolve verifies #sha256 for local file" {
  local _src="${BATS_TEST_TMPDIR}/data"
  printf 'payload\n' > "$_src"
  local _expect
  _expect="$(verify__hash_file "$_src")"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run uri__resolve "${_src}#sha256=${_expect}" "$_dst"
  assert_success

  run uri__resolve "${_src}#sha256=0000000000000000000000000000000000000000000000000000000000000000" "${_dst}.bad"
  assert_failure
}

@test "uri__resolve_line leaves local paths unchanged" {
  local _p="${BATS_TEST_TMPDIR}/exists"
  touch "$_p"
  run uri__resolve_line "$_p" "${BATS_TEST_TMPDIR}/mat"
  assert_success
  assert_output "$_p"
}

@test "uri__resolve_list resolves two local lines" {
  local _a="${BATS_TEST_TMPDIR}/a"
  local _b="${BATS_TEST_TMPDIR}/b"
  touch "$_a" "$_b"
  run uri__resolve_list "$(printf '%s\n' "$_a" "$_b")" "${BATS_TEST_TMPDIR}/m"
  assert_success
  assert_line -n 0 "$_a"
  assert_line -n 1 "$_b"
}

@test "uri__resolve OCI path is bypassed via stub (_uri__resolve_oci_to)" {
  _uri__resolve_oci_to() {
    printf 'from-oci\n' > "$2"
    return 0
  }

  local _dst="${BATS_TEST_TMPDIR}/oci.txt"
  run uri__resolve "oci://example.com/ns/art:v1?path=x.yaml" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "from-oci"
}

# ── uri__classify: ftp/ftps/sftp ──────────────────────────────────────────────

@test "uri__classify: ftp/ftps/sftp all return ftp" {
  run uri__classify "ftp://ftp.example.com/pub/file.tar.gz"
  assert_success
  assert_output "ftp"

  run uri__classify "ftps://secure.ftp.com/file"
  assert_success
  assert_output "ftp"

  run uri__classify "sftp://user@host/path/file"
  assert_success
  assert_output "ftp"
}

# ── uri__fetch_asset tests ────────────────────────────────────────────────────

# Common stubs used by uri__fetch_asset tests.
_stub_fa_common() {
  net__fetch_url_file() { printf '%s\n' "$1" > "$2"; }
  export -f net__fetch_url_file

  _VERIFY_SHA_CALLS="${BATS_TEST_TMPDIR}/_sha_calls"
  export _VERIFY_SHA_CALLS
  verify__sha() { printf '%s %s\n' "$1" "$2" >> "$_VERIFY_SHA_CALLS"; return 0; }
  export -f verify__sha

  _VERIFY_GPG_CALLS="${BATS_TEST_TMPDIR}/_gpg_calls"
  export _VERIFY_GPG_CALLS
  verify__gpg_detached() { printf '%s\n' "$@" >> "$_VERIFY_GPG_CALLS"; return 0; }
  export -f verify__gpg_detached

  file__detect_type() { printf 'elf'; }
  export -f file__detect_type

  install__copy_bin() { cp "$1" "$2" && chmod +x "$2"; }
  export -f install__copy_bin

  install__track_internal_path() { return 0; }
  export -f install__track_internal_path
}

@test "uri__fetch_asset: --url is required" {
  run uri__fetch_asset --dest "${BATS_TEST_TMPDIR}/out"
  assert_failure
  assert_output --partial "--url is required"
}

@test "uri__fetch_asset: at least one destination option is required" {
  run uri__fetch_asset --url "/tmp/x"
  assert_failure
  assert_output --partial "required"
}

@test "uri__fetch_asset: local file copied to --dest, returns path on stdout" {
  local _src="${BATS_TEST_TMPDIR}/src.txt"
  printf 'hello\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/dst.txt"
  run --separate-stderr uri__fetch_asset --url "$_src" --dest "$_dst" --sha256 none
  assert_success
  assert_output "$_dst"
  run cat "$_dst"
  assert_output "hello"
}

@test "uri__fetch_asset: https URL calls net__fetch_url_file (stubbed)" {
  _stub_fa_common
  local _dst="${BATS_TEST_TMPDIR}/http.bin"
  run --separate-stderr uri__fetch_asset \
    --url "https://example.com/file.bin" --dest "$_dst" --sha256 none
  assert_success
  assert_output "$_dst"
  run cat "$_dst"
  assert_output "https://example.com/file.bin"
}

@test "uri__fetch_asset: ftp:// URL routes through net__fetch_url_file" {
  _FETCH_LOG="${BATS_TEST_TMPDIR}/_ftp_log"
  export _FETCH_LOG
  net__fetch_url_file() { printf '%s\n' "$1" > "$_FETCH_LOG"; printf 'content\n' > "$2"; }
  export -f net__fetch_url_file

  local _dst="${BATS_TEST_TMPDIR}/ftp.out"
  run --separate-stderr uri__fetch_asset \
    --url "ftp://ftp.example.com/pub/file.tar" --dest "$_dst" --sha256 none
  assert_success
  run grep -q "ftp://ftp.example.com" "$_FETCH_LOG"
  assert_success
}

@test "uri__fetch_asset: #sha256 fragment is verified automatically" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _hex
  _hex="$(verify__hash_file "$_src")"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    --url "${_src}#sha256=${_hex}" --dest "$_dst"
  assert_success
  run grep -qF "$_hex" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "uri__fetch_asset: --sha256 hex is verified via verify__sha" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _hex
  _hex="$(verify__hash_file "$_src")"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset --url "$_src" --sha256 "$_hex" --dest "$_dst"
  assert_success
  run grep -qF "$_hex" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "uri__fetch_asset: --sha256 none suppresses all sha checks" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset --url "$_src" --sha256 none --dest "$_dst"
  assert_success
  [[ ! -f "$_VERIFY_SHA_CALLS" ]] || [[ ! -s "$_VERIFY_SHA_CALLS" ]]
}

@test "uri__fetch_asset: --sha256 none cannot combine with --sidecar-url" {
  run uri__fetch_asset --url "https://x.com/a" --dest "/tmp/a" \
    --sha256 none --sidecar-url "https://x.com/a.sha256"
  assert_failure
  assert_output --partial "none"
}

@test "uri__fetch_asset: --sidecar-url multi-entry format matches by filename" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/asset.bin"
  printf 'content\n' > "$_src"
  local _hash="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
  local _sc="${BATS_TEST_TMPDIR}/checksums.sha256"
  printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  other.bin\n' > "$_sc"
  printf '%s  asset.bin\n' "$_hash" >> "$_sc"
  local _dst="${BATS_TEST_TMPDIR}/out.bin"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --sidecar-url "file://${_sc}" --dest "$_dst"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "uri__fetch_asset: --sidecar-url raw single-hash uses NR==1 NF==1 fallback" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/asset.bin"
  printf 'content\n' > "$_src"
  local _hash="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
  local _sc="${BATS_TEST_TMPDIR}/asset.sha256"
  printf '%s\n' "$_hash" > "$_sc"
  local _dst="${BATS_TEST_TMPDIR}/out.bin"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --sidecar-url "file://${_sc}" --dest "$_dst"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "uri__fetch_asset: --header and --netrc-file forwarded to net__fetch_url_file" {
  _FETCH_LOG="${BATS_TEST_TMPDIR}/_fetch_log"
  export _FETCH_LOG
  net__fetch_url_file() { printf '%s\n' "$@" > "$_FETCH_LOG"; printf 'ok\n' > "$2"; }
  export -f net__fetch_url_file

  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    --url "https://example.com/f" --dest "$_dst" --sha256 none \
    --header "X-Tok: abc" --netrc-file "/tmp/nr"
  assert_success
  run grep -q "X-Tok: abc" "$_FETCH_LOG"
  assert_success
  run grep -q "/tmp/nr" "$_FETCH_LOG"
  assert_success
}

@test "uri__fetch_asset: --chmod-exec makes dest executable" {
  local _src="${BATS_TEST_TMPDIR}/script.sh"
  printf '#!/bin/sh\necho ok\n' > "$_src"
  chmod 0644 "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out.sh"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --dest "$_dst" --sha256 none --chmod-exec
  assert_success
  [[ -x "$_dst" ]]
}

@test "uri__fetch_asset: direct binary installed to --binary-dest, path on stdout" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/mytool"
  printf '#!/bin/sh\n' > "$_src"
  chmod +x "$_src"
  local _bdest="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_bdest"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --binary-dest "$_bdest" --sha256 none
  assert_success
  assert_output "${_bdest}/mytool"
  [[ -f "${_bdest}/mytool" ]]
}

@test "uri__fetch_asset: archive extracted, binary installed via --binary-src suffix match" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/bin"
    printf '#!/bin/sh\n' > "$2/bin/mytool"
    chmod +x "$2/bin/mytool"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  local _bdest="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_bdest"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --binary-src "bin/mytool" --binary-dest "$_bdest" --sha256 none
  assert_success
  assert_output "${_bdest}/mytool"
  [[ -f "${_bdest}/mytool" ]]
}

@test "uri__fetch_asset: archive auto-discovers all executables when no --binary-src" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2"
    printf '#!/bin/sh\n' > "$2/tool-a"
    printf '#!/bin/sh\n' > "$2/tool-b"
    chmod +x "$2/tool-a" "$2/tool-b"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  local _bdest="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_bdest"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --binary-dest "$_bdest" --sha256 none
  assert_success
  assert_line --partial "tool-a"
  assert_line --partial "tool-b"
  [[ -f "${_bdest}/tool-a" && -f "${_bdest}/tool-b" ]]
}

@test "uri__fetch_asset: GPG verification calls verify__gpg_detached" {
  _stub_fa_common
  net__fetch_url_file() { printf 'stub\n' > "$2"; }
  export -f net__fetch_url_file

  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --dest "$_dst" --sha256 none \
    --gpg-key-url "https://example.com/key.gpg" \
    --gpg-sig-url "https://example.com/payload.asc"
  assert_success
  [[ -s "$_VERIFY_GPG_CALLS" ]]
}

@test "uri__fetch_asset: GPG verification runs independently of --sha256 none" {
  _stub_fa_common
  net__fetch_url_file() { printf 'stub\n' > "$2"; }
  export -f net__fetch_url_file

  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --dest "$_dst" --sha256 none \
    --gpg-key-url "https://example.com/key.gpg" \
    --gpg-sig-url "https://example.com/payload.asc"
  assert_success
  [[ -s "$_VERIFY_GPG_CALLS" ]]
  [[ ! -f "$_VERIFY_SHA_CALLS" ]] || [[ ! -s "$_VERIFY_SHA_CALLS" ]]
}

@test "uri__fetch_asset: --installer-dir places download under that dir" {
  local _src="${BATS_TEST_TMPDIR}/myfile.bin"
  printf 'content\n' > "$_src"
  local _idir="${BATS_TEST_TMPDIR}/idir"
  mkdir -p "$_idir"
  run --separate-stderr uri__fetch_asset \
    --url "$_src" --installer-dir "$_idir" --sha256 none
  assert_success
  assert_output "${_idir}/myfile.bin"
  [[ -f "${_idir}/myfile.bin" ]]
}

@test "uri__resolve wraps uri__fetch_asset (positional args mapped correctly)" {
  local _src="${BATS_TEST_TMPDIR}/data.txt"
  printf 'wrapped\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out.txt"
  run uri__resolve "$_src" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "wrapped"
}
