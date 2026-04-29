#!/usr/bin/env bats
# Unit tests for lib/checksum.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib checksum.sh
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write "hello" (no newline) to a temp file and return its path via stdout.
_make_hello_file() {
  local _f="${BATS_TEST_TMPDIR}/hello.bin"
  printf 'hello' > "$_f"
  echo "$_f"
}

# Known SHA-256 of the string "hello" (no newline).
_HELLO_SHA256="2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
# Known SHA-512 of the string "hello" (no newline).
_HELLO_SHA512="9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043"

# ---------------------------------------------------------------------------
# checksum__hash_file
# ---------------------------------------------------------------------------

@test "checksum__hash_file prints known SHA-256 digest (default)" {
  local _f
  _f="$(_make_hello_file)"
  run checksum__hash_file "$_f"
  assert_success
  assert_output "$_HELLO_SHA256"
}

@test "checksum__hash_file prints known SHA-256 digest (explicit algo)" {
  local _f
  _f="$(_make_hello_file)"
  run checksum__hash_file "$_f" 256
  assert_success
  assert_output "$_HELLO_SHA256"
}

@test "checksum__hash_file prints known SHA-512 digest" {
  local _f
  _f="$(_make_hello_file)"
  run checksum__hash_file "$_f" 512
  assert_success
  assert_output "$_HELLO_SHA512"
}

@test "checksum__hash_file fails for nonexistent file" {
  run checksum__hash_file "/nonexistent/path/file.bin"
  assert_failure
}

# ---------------------------------------------------------------------------
# checksum__verify
# ---------------------------------------------------------------------------

@test "checksum__verify succeeds for correct SHA-256 hash (default)" {
  local _f
  _f="$(_make_hello_file)"
  run checksum__verify "$_f" "$_HELLO_SHA256"
  assert_success
  assert_output --partial "passed"
}

@test "checksum__verify succeeds for correct SHA-256 hash (explicit algo)" {
  local _f
  _f="$(_make_hello_file)"
  run checksum__verify "$_f" "$_HELLO_SHA256" 256
  assert_success
  assert_output --partial "passed"
}

@test "checksum__verify succeeds for correct SHA-512 hash" {
  local _f
  _f="$(_make_hello_file)"
  run checksum__verify "$_f" "$_HELLO_SHA512" 512
  assert_success
  assert_output --partial "passed"
}

@test "checksum__verify fails for wrong hash" {
  local _f
  _f="$(_make_hello_file)"
  run checksum__verify "$_f" "000000000000000000000000000000000000000000000000000000000000dead"
  assert_failure
  assert_output --partial "failed"
}

@test "checksum__verify prints expected and actual on mismatch" {
  local _f
  _f="$(_make_hello_file)"
  run checksum__verify "$_f" "deadbeef"
  assert_output --partial "Expected: deadbeef"
  assert_output --partial "Actual:"
}

# ---------------------------------------------------------------------------
# checksum__verify_sidecar
# ---------------------------------------------------------------------------

@test "checksum__verify_sidecar succeeds when sidecar matches (default SHA-256)" {
  local _f
  _f="$(_make_hello_file)"
  local _sidecar="${BATS_TEST_TMPDIR}/hello.bin.sha256"
  printf '%s  hello.bin\n' "$_HELLO_SHA256" > "$_sidecar"
  run checksum__verify_sidecar "$_f" "$_sidecar"
  assert_success
}

@test "checksum__verify_sidecar succeeds when sidecar matches (explicit SHA-256)" {
  local _f
  _f="$(_make_hello_file)"
  local _sidecar="${BATS_TEST_TMPDIR}/hello.bin.sha256"
  printf '%s  hello.bin\n' "$_HELLO_SHA256" > "$_sidecar"
  run checksum__verify_sidecar "$_f" "$_sidecar" 256
  assert_success
}

@test "checksum__verify_sidecar succeeds when sidecar matches (SHA-512)" {
  local _f
  _f="$(_make_hello_file)"
  local _sidecar="${BATS_TEST_TMPDIR}/hello.bin.sha512"
  printf '%s  hello.bin\n' "$_HELLO_SHA512" > "$_sidecar"
  run checksum__verify_sidecar "$_f" "$_sidecar" 512
  assert_success
}

@test "checksum__verify_sidecar fails when sidecar is wrong" {
  local _f
  _f="$(_make_hello_file)"
  local _sidecar="${BATS_TEST_TMPDIR}/bad.sha256"
  printf '0000000000000000000000000000000000000000000000000000000000000000  hello.bin\n' \
    > "$_sidecar"
  run checksum__verify_sidecar "$_f" "$_sidecar"
  assert_failure
}

@test "checksum__verify_sidecar fails for empty sidecar file" {
  local _f
  _f="$(_make_hello_file)"
  local _sidecar="${BATS_TEST_TMPDIR}/empty.sha256"
  touch "$_sidecar"
  run checksum__verify_sidecar "$_f" "$_sidecar"
  assert_failure
  assert_output --partial "could not read hash"
}
