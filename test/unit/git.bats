#!/usr/bin/env bats
# Unit tests for lib/git.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib git.sh
}

# ---------------------------------------------------------------------------
# git__clone argument validation
# ---------------------------------------------------------------------------

@test "git__clone fails when --url is missing" {
  run git__clone --dir "${BATS_TEST_TMPDIR}/repo"
  assert_failure
  assert_output --partial "missing --url"
}

@test "git__clone fails when --dir is missing" {
  run git__clone --url "https://example.com/repo.git"
  assert_failure
  assert_output --partial "missing --dir"
}

@test "git__clone rejects unknown options" {
  run git__clone --url "https://example.com/repo.git" --dir "/tmp/x" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

# ---------------------------------------------------------------------------
# git__clone idempotency
# ---------------------------------------------------------------------------

@test "git__clone skips when target .git already exists" {
  local _dir="${BATS_TEST_TMPDIR}/existing"
  mkdir -p "${_dir}/.git"
  run git__clone --url "https://example.com/repo.git" --dir "$_dir"
  assert_success
  assert_output --partial "already exists"
}

# ---------------------------------------------------------------------------
# git__clone real clone (shallow, local bare repo as server)
# ---------------------------------------------------------------------------

@test "git__clone installs git when absent and clones via stub" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  local _install_log="${BATS_TEST_TMPDIR}/install.log"
  local _fake_git="${BATS_TEST_TMPDIR}/bin/git"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  ospkg__detect() { return 0; }
  export -f ospkg__detect
  ospkg__install_tracked() {
    echo "install_tracked $*" >> "$_install_log"
    cat > "$_fake_git" << 'EOF'
#!/usr/bin/env bash
if [[ "${1-}" = "clone" ]]; then
  _dst="${@: -1}"
  mkdir -p "${_dst}/.git"
  printf 'ref: refs/heads/main\n' > "${_dst}/.git/HEAD"
  exit 0
fi
exit 1
EOF
    chmod +x "$_fake_git"
    return 0
  }
  export -f ospkg__install_tracked

  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin:/bin:/usr/sbin:/sbin"
  run git__clone --url "file:///tmp/fake.git" --dir "$_dst"
  export PATH="$_saved"

  assert_success
  assert_file_exists "${_dst}/.git/HEAD"
  assert_file_exists "$_install_log"
  grep -q "lib-git git" "$_install_log"
}

@test "git__clone removes partial directory on clone failure" {
  local _dst="${BATS_TEST_TMPDIR}/bad_dst"
  run git__clone --url "https://0.0.0.0/nonexistent.git" --dir "$_dst"
  assert_failure
  [[ ! -d "$_dst" ]]
}
