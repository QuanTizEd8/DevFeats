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
  run bash -c "source '${LIB_ROOT}/uri.sh'; _uri__gh_to_https 'gh://quantized8/sysset@v1.2.3:docs/README.md'"
  assert_success
  assert_output "https://raw.githubusercontent.com/quantized8/sysset/v1.2.3/docs/README.md"
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
  _expect="$(checksum__sha256_file "$_src")"
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
