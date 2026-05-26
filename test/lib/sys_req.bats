#!/usr/bin/env bats
# Unit tests for lib/sys_req.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# sys_req__require_platform
# ---------------------------------------------------------------------------

@test "sys_req__require_platform: succeeds when first spec group matches" {
  os__match_spec() { [[ "$1" == "id=debian" ]]; }
  export -f os__match_spec
  run sys_req__require_platform -- id=debian
  assert_success
}

@test "sys_req__require_platform: succeeds when second spec group matches" {
  os__match_spec() { [[ "$1" == "id=ubuntu" ]]; }
  export -f os__match_spec
  run sys_req__require_platform -- id=debian -- id=ubuntu
  assert_success
}

@test "sys_req__require_platform: fails when no spec group matches" {
  os__match_spec() { return 1; }
  export -f os__match_spec
  run --separate-stderr sys_req__require_platform -- id=debian
  assert_failure
  [[ "${stderr}" =~ "id=debian" ]]
}

@test "sys_req__require_platform: error message lists all groups" {
  os__match_spec() { return 1; }
  export -f os__match_spec
  run --separate-stderr sys_req__require_platform -- id=debian -- id=ubuntu
  assert_failure
  [[ "${stderr}" =~ "id=debian" ]]
  [[ "${stderr}" =~ "id=ubuntu" ]]
}

@test "sys_req__require_platform: AND logic within a group" {
  # Both keys must match for the group to match.
  os__match_spec() {
    [[ "$1" == "id=debian" && "$2" == "arch=amd64" ]]
  }
  export -f os__match_spec
  run sys_req__require_platform -- id=debian arch=amd64
  assert_success
}

@test "sys_req__require_platform: stops at first matching group" {
  local _calls=0
  os__match_spec() {
    (( _calls++ )) || true
    [[ "$1" == "id=debian" ]]
  }
  export -f os__match_spec
  run sys_req__require_platform -- id=debian -- id=ubuntu
  assert_success
}

# ---------------------------------------------------------------------------
# sys_req__require_root — unconditional
# ---------------------------------------------------------------------------

@test "sys_req__require_root: succeeds when privileged (no args)" {
  users__is_privileged() { return 0; }
  export -f users__is_privileged
  run sys_req__require_root
  assert_success
}

@test "sys_req__require_root: fails when not privileged (no args)" {
  users__is_privileged() { return 1; }
  export -f users__is_privileged
  run --separate-stderr sys_req__require_root
  assert_failure
  [[ "${stderr}" =~ "root" ]]
}

# ---------------------------------------------------------------------------
# sys_req__require_root — conditional (with spec groups)
# ---------------------------------------------------------------------------

@test "sys_req__require_root: succeeds when platform matches and privileged" {
  os__match_spec() { [[ "$1" == "id=debian" ]]; }
  users__is_privileged() { return 0; }
  export -f os__match_spec users__is_privileged
  run sys_req__require_root -- id=debian
  assert_success
}

@test "sys_req__require_root: fails when platform matches and not privileged" {
  os__match_spec() { [[ "$1" == "id=debian" ]]; }
  users__is_privileged() { return 1; }
  export -f os__match_spec users__is_privileged
  run --separate-stderr sys_req__require_root -- id=debian
  assert_failure
  [[ "${stderr}" =~ "root" ]]
}

@test "sys_req__require_root: succeeds when platform does not match even if not privileged" {
  os__match_spec() { return 1; }
  users__is_privileged() { return 1; }
  export -f os__match_spec users__is_privileged
  run sys_req__require_root -- id=debian
  assert_success
}

@test "sys_req__require_root: succeeds when second spec group matches and privileged" {
  os__match_spec() { [[ "$1" == "id=ubuntu" ]]; }
  users__is_privileged() { return 0; }
  export -f os__match_spec users__is_privileged
  run sys_req__require_root -- id=debian -- id=ubuntu
  assert_success
}

@test "sys_req__require_root: fails when second spec group matches and not privileged" {
  os__match_spec() { [[ "$1" == "id=ubuntu" ]]; }
  users__is_privileged() { return 1; }
  export -f os__match_spec users__is_privileged
  run sys_req__require_root -- id=debian -- id=ubuntu
  assert_failure
}
