#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ===========================================================================
# _bootstrap__yq_compatible
# ===========================================================================

@test "_bootstrap__yq_compatible returns 1 for empty argument" {
  reload_lib
  run _bootstrap__yq_compatible ""
  assert_failure
}

@test "_bootstrap__yq_compatible returns 1 for non-existent binary" {
  reload_lib
  # /nonexistent/path/yq does not exist; bash exits 127 (command not found).
  run -127 _bootstrap__yq_compatible "/nonexistent/path/yq"
  assert_failure
}

@test "_bootstrap__yq_compatible returns 0 for a binary that accepts -o=json" {
  reload_lib
  # Create a fake yq that exits 0 when called with -o=json
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nif [ "$1" = "-o=json" ]; then exit 0; fi\nexit 1\n' \
    > "${BATS_TEST_TMPDIR}/bin/fake-yq"
  chmod +x "${BATS_TEST_TMPDIR}/bin/fake-yq"
  run _bootstrap__yq_compatible "${BATS_TEST_TMPDIR}/bin/fake-yq"
  assert_success
}

@test "_bootstrap__yq_compatible returns 1 for a binary that rejects -o=json" {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/fake-yq-bad"
  chmod +x "${BATS_TEST_TMPDIR}/bin/fake-yq-bad"
  run _bootstrap__yq_compatible "${BATS_TEST_TMPDIR}/bin/fake-yq-bad"
  assert_failure
}

# ===========================================================================
# bootstrap__yq — fast paths (no network)
# ===========================================================================

@test "bootstrap__yq returns existing PATH yq when compatible" {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nif [ "$1" = "-o=json" ]; then exit 0; fi\nexit 1\n' \
    > "${BATS_TEST_TMPDIR}/bin/yq"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yq"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"

  run bootstrap__yq
  assert_success
  assert_output "${BATS_TEST_TMPDIR}/bin/yq"
}

@test "bootstrap__yq skips incompatible PATH yq and uses cached state" {
  reload_lib
  # Provide an incompatible yq on PATH (Python jq-wrapper style).
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/yq"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yq"

  # Create a fake cached binary that is compatible; use BATS_TEST_TMPDIR (exported).
  printf '#!/bin/sh\nif [ "$1" = "-o=json" ]; then exit 0; fi\nexit 1\n' \
    > "${BATS_TEST_TMPDIR}/cached-yq"
  chmod +x "${BATS_TEST_TMPDIR}/cached-yq"

  # Stub install__read_state to return our cached binary.
  # BATS_TEST_TMPDIR is exported so it's accessible in the run subshell.
  install__read_state() {
    local _tool="$1" _ctx_var="$2" _path_var="$3" _grp_var="$4"
    [[ "${_tool}" == "yq" ]] || return 1
    printf -v "${_ctx_var}" '%s' "internal"
    printf -v "${_path_var}" '%s' "${BATS_TEST_TMPDIR}/cached-yq"
    printf -v "${_grp_var}" '%s' "devfeats-bootstrap-yq"
  }
  export -f install__read_state

  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"

  run bootstrap__yq
  assert_success
  assert_output "${BATS_TEST_TMPDIR}/cached-yq"
}

# ===========================================================================
# bootstrap__oras — fast paths (no network)
# ===========================================================================

@test "bootstrap__oras returns existing PATH oras" {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nprintf "oras version 1.2.3\\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/oras"
  chmod +x "${BATS_TEST_TMPDIR}/bin/oras"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"

  run bootstrap__oras
  assert_success
  assert_output "${BATS_TEST_TMPDIR}/bin/oras"
}

@test "bootstrap__oras returns cached state when oras not on PATH" {
  reload_lib
  # Create the fake binary BEFORE isolating PATH so that chmod is available.
  printf '#!/bin/sh\nprintf "oras version 1.2.3\\n"\n' \
    > "${BATS_TEST_TMPDIR}/cached-oras"
  chmod +x "${BATS_TEST_TMPDIR}/cached-oras"

  begin_path_isolation

  install__read_state() {
    local _tool="$1" _ctx_var="$2" _path_var="$3" _grp_var="$4"
    [[ "${_tool}" == "oras" ]] || return 1
    printf -v "${_ctx_var}" '%s' "internal"
    printf -v "${_path_var}" '%s' "${BATS_TEST_TMPDIR}/cached-oras"
    printf -v "${_grp_var}" '%s' "devfeats-bootstrap-oras"
  }
  export -f install__read_state

  run bootstrap__oras
  assert_success
  assert_output "${BATS_TEST_TMPDIR}/cached-oras"

  end_path_isolation
}

# ===========================================================================
# ospkg__untrack_resource
# ===========================================================================

@test "ospkg__untrack_resource removes tracked paths from sidecar" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  ospkg__track_resource "abc" "/tmp/one" "/tmp/two"

  run ospkg__untrack_resource "abc" "/tmp/one"
  assert_success
  run grep -F -- "/tmp/one" "${BATS_TEST_TMPDIR}/ospkg/resources/abc"
  assert_failure
  run grep -F -- "/tmp/two" "${BATS_TEST_TMPDIR}/ospkg/resources/abc"
  assert_success
}
