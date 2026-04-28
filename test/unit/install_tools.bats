#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
}

@test "install__oras promotes internal ownership to user and untracks resource" {
  reload_lib install/oras.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  local _bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_bin_dir"
  cat > "${_bin_dir}/oras" << 'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == "version" ]]; then
  echo "Version: 1.3.2"
  exit 0
fi
exit 0
EOF
  chmod +x "${_bin_dir}/oras"
  export PATH="${_bin_dir}:${PATH}"
  hash -r

  ospkg__track_resource "old-group" "${_bin_dir}/oras"
  install__state_record "oras" "internal" "release" "${_bin_dir}/oras" "old-group"

  run install__oras --context user --if-exists skip --owner-group feature::install-oras
  assert_success
  assert_output "${_bin_dir}/oras"
  run install__state_context "oras"
  assert_success
  assert_output "user"
  run bash -c "rg \"${_bin_dir}/oras\" \"${BATS_TEST_TMPDIR}/ospkg/resources/old-group\""
  assert_failure
}

@test "ospkg__untrack_resource removes tracked paths from sidecar" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  ospkg__track_resource "abc" "/tmp/one" "/tmp/two"

  run ospkg__untrack_resource "abc" "/tmp/one"
  assert_success
  run bash -c "rg \"/tmp/one\" \"${BATS_TEST_TMPDIR}/ospkg/resources/abc\""
  assert_failure
  run bash -c "rg \"/tmp/two\" \"${BATS_TEST_TMPDIR}/ospkg/resources/abc\""
  assert_success
}

@test "install__oras rejects removed --verify option" {
  reload_lib install/oras.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  run install__oras --context internal --method repos --verify strict
  assert_failure
  [[ "$output" == *"unknown option '--verify'"* ]]
}

@test "install__oras rejects --download-url because verification is mandatory" {
  reload_lib install/oras.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  run install__oras \
    --context internal \
    --method release \
    --version 1.3.2 \
    --if-exists reinstall \
    --download-url "https://example.com/oras.tar.gz"
  assert_failure
  [[ "$output" == *"--download-url is not supported because checksum+GPG verification is mandatory."* ]]
}
