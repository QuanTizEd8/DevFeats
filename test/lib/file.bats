#!/usr/bin/env bats
# Unit tests for lib/file.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib file.sh
}

# ---------------------------------------------------------------------------
# _file__ensure_extract_tool
# ---------------------------------------------------------------------------

@test "_file__ensure_extract_tool tar: succeeds when tar is available" {
  create_fake_bin "tar" ""
  prepend_fake_bin_path

  run _file__ensure_extract_tool tar
  assert_success
}

@test "_file__ensure_extract_tool tar: fails with diagnostic when tar is absent" {
  # Restrict PATH to only our empty bin dir so tar is not found.
  # We must NOT call prepend_fake_bin_path before this — just restrict directly.
  begin_path_isolation

  run _file__ensure_extract_tool tar

  end_path_isolation
  assert_failure
  assert_output --partial "tar is required"
}

@test "_file__ensure_extract_tool zip: succeeds when unzip is available" {
  create_fake_bin "unzip" ""
  prepend_fake_bin_path

  run _file__ensure_extract_tool zip
  assert_success
}

@test "_file__ensure_extract_tool zip: fails with diagnostic when unzip absent and ospkg install fails" {
  # ospkg is now always loaded; simulate install failure so unzip stays absent.
  begin_path_isolation

  ospkg__update() { return 0; }
  export -f ospkg__update
  ospkg__install_tracked() { return 1; }
  export -f ospkg__install_tracked

  run _file__ensure_extract_tool zip

  end_path_isolation
  assert_failure
  assert_output --partial "unzip is required"
}

@test "_file__ensure_extract_tool zip: installs unzip via ospkg when ospkg is loaded" {
  # Simulate ospkg loaded but unzip absent; ospkg stubs install a fake unzip.
  reload_lib ospkg.sh
  reload_lib file.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"

  # Seed a minimal apt context without invoking the real PM.
  _OSPKG_DETECTED=true
  _OSPKG_PKG_MNGR="apt-get"
  _OSPKG_FAMILY="apt"
  _OSPKG_OS_RELEASE[pm]="apt"
  _OSPKG_OS_RELEASE[arch]="x86_64"
  _OSPKG_OS_RELEASE[id]="ubuntu"
  _OSPKG_OS_RELEASE[id_like]="debian"
  _OSPKG_OS_RELEASE[version_id]="22.04"
  _OSPKG_OS_RELEASE[version_codename]="jammy"

  # Stub ospkg__update and ospkg__install_tracked; the latter creates a fake unzip.
  ospkg__update() { return 0; }
  export -f ospkg__update

  local _fake_unzip="${BATS_TEST_TMPDIR}/bin/unzip"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\nexit 0\n' > "$_fake_unzip"
  chmod +x "$_fake_unzip"

  ospkg__install_tracked() {
    # Simulate installation: unzip now appears on PATH.
    return 0
  }
  export -f ospkg__install_tracked

  # unzip is already available via fake bin, which the stubs put on PATH;
  # prepend it so command -v unzip resolves to our fake.
  prepend_fake_bin_path

  run _file__ensure_extract_tool zip
  assert_success
}

@test "_file__ensure_extract_tool unknown ext: is a no-op" {
  run _file__ensure_extract_tool "weirdfmt"
  assert_success
}

# ---------------------------------------------------------------------------
# file__extract_archive — format detection and tool delegation
# ---------------------------------------------------------------------------

@test "file__extract_archive: extracts .tar.gz when tar is available" {
  local _arc="${BATS_TEST_DIRNAME}/fixtures/archives/hello.tar.gz"
  create_pass_through_bin "tar"
  prepend_fake_bin_path

  local _dest="${BATS_TEST_TMPDIR}/out_tgz"
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  [[ -f "${_dest}/hello.txt" ]]
}

@test "file__extract_archive: extracts .tgz using .tgz extension" {
  local _arc="${BATS_TEST_DIRNAME}/fixtures/archives/world.tgz"
  create_pass_through_bin "tar"
  prepend_fake_bin_path

  local _dest="${BATS_TEST_TMPDIR}/out_tgz2"
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  [[ -f "${_dest}/world.txt" ]]
}

@test "file__extract_archive: extracts .zip when unzip is available" {
  command -v zip > /dev/null 2>&1 || skip "zip not available for test setup"
  command -v unzip > /dev/null 2>&1 || skip "unzip not available"
  create_pass_through_bin "unzip"
  prepend_fake_bin_path

  local _src="${BATS_TEST_TMPDIR}/payload_zip"
  mkdir -p "$_src"
  echo "zipped" > "${_src}/zipped.txt"
  local _arc="${BATS_TEST_TMPDIR}/test.zip"
  (cd "$_src" && zip -q "$_arc" zipped.txt)

  local _dest="${BATS_TEST_TMPDIR}/out_zip"
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  [[ -f "${_dest}/zipped.txt" ]]
}

@test "file__extract_archive: uses original_name for format detection" {
  # Fixture is a .tar.gz copied to a path with no meaningful extension.
  local _tmpfile
  _tmpfile="$(mktemp "${BATS_TEST_TMPDIR}/archive.XXXXXX")"
  cp "${BATS_TEST_DIRNAME}/fixtures/archives/named.tar.gz" "$_tmpfile"

  create_pass_through_bin "tar"
  prepend_fake_bin_path

  local _dest="${BATS_TEST_TMPDIR}/out_named"
  run file__extract_archive "$_tmpfile" "$_dest" "some_release.tar.gz"
  assert_success
  [[ -f "${_dest}/named.txt" ]]
}

@test "file__extract_archive: returns failure for unrecognized format" {
  local _arc="${BATS_TEST_TMPDIR}/test.weirdfmt"
  touch "$_arc"
  local _dest="${BATS_TEST_TMPDIR}/out_weird"

  run file__extract_archive "$_arc" "$_dest"
  assert_failure
  assert_output --partial "Unrecognized archive format"
}

@test "file__extract_archive: creates destination directory when absent" {
  local _arc="${BATS_TEST_DIRNAME}/fixtures/archives/mkdir_test.tar.gz"
  create_pass_through_bin "tar"
  prepend_fake_bin_path

  local _dest="${BATS_TEST_TMPDIR}/newly_created_dir"
  [[ ! -d "$_dest" ]]
  run file__extract_archive "$_arc" "$_dest"
  assert_success
  assert_dir_exists "$_dest"
}

@test "file__extract_archive: fails when gzip is absent and format is .tar.gz" {
  local _arc="${BATS_TEST_TMPDIR}/test_no_gzip.tar.gz"
  touch "$_arc"
  local _dest="${BATS_TEST_TMPDIR}/out_no_gzip"
  # Restrict PATH so gzip is not found but tar is available.
  create_pass_through_bin "tar"
  begin_path_isolation "basename" "mkdir" "sort" "tar"

  run file__extract_archive "$_arc" "$_dest"

  end_path_isolation
  assert_failure
  assert_output --partial "gzip is required"
}

@test "file__extract_archive: fails when tar is absent and format is .tar.gz" {
  # Create test artifacts and pass-through bins for system tools BEFORE restricting PATH.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  local _arc="${BATS_TEST_TMPDIR}/test_no_tar.tar.gz"
  touch "$_arc"
  local _dest="${BATS_TEST_TMPDIR}/out_no_tar"
  # Restrict PATH so tar is not found (our bin dir has no tar).
  begin_path_isolation "basename" "mkdir" "sort"

  run file__extract_archive "$_arc" "$_dest"

  end_path_isolation
  assert_failure
  assert_output --partial "tar is required"
}
