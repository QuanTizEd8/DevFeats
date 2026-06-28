#!/usr/bin/env bats
# Unit tests for lib/json.bash
#
# All json__* function tests require a real jq binary and live in
# test/lib/integration/json.bats. Only the bootstrap stub test lives here.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
}

# ---------------------------------------------------------------------------
# bootstrap__jq — auto-installs jq when absent
# ---------------------------------------------------------------------------

@test "bootstrap__jq: calls ospkg__install_tracked when jq absent" {
  reload_lib

  local _install_log="${BATS_TEST_TMPDIR}/install.log"
  local _fake_jq="${BATS_TEST_TMPDIR}/bin/jq"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  ospkg__update() { return 0; }
  export -f ospkg__update

  # Stub installs a fake jq so the post-install command -v check passes.
  ospkg__install_tracked() {
    echo "install_tracked $*" >> "$_install_log"
    printf '#!/bin/sh\nexit 0\n' > "$_fake_jq"
    chmod +x "$_fake_jq"
    return 0
  }
  export -f ospkg__install_tracked

  begin_path_isolation
  run bootstrap__jq
  local _rc=$?
  end_path_isolation

  [[ $_rc -eq 0 ]]
  assert_file_exists "$_install_log"
  grep -q "jq" "$_install_log"
}
