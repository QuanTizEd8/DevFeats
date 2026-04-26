# shellcheck shell=bash
# helpers/stubs.bash — PATH-based stub/fake binary helpers.
#
# Provides create_fake_bin() and prepend_fake_bin_path() for injecting
# lightweight fake executables that shadow real ones during a test.

# create_fake_bin <name> [<stdout_line>]
#
# Creates a tiny executable under ${BATS_TEST_TMPDIR}/bin named <name>.
# When invoked, the fake prints <stdout_line> to stdout (ignoring all
# arguments) and exits 0.  If <stdout_line> is omitted the fake prints
# nothing.
create_fake_bin() {
  local _name="$1"
  local _stdout="${2:-}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # Use printf to avoid issues with special chars in _stdout.
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$_stdout" \
    > "${BATS_TEST_TMPDIR}/bin/${_name}"
  chmod +x "${BATS_TEST_TMPDIR}/bin/${_name}"
}

# prepend_fake_bin_path
#
# Puts ${BATS_TEST_TMPDIR}/bin at the front of PATH so fake binaries
# shadow their real counterparts for the remainder of the test.
prepend_fake_bin_path() {
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

# create_pass_through_bin <name>
#
# Adds a symlink inside ${BATS_TEST_TMPDIR}/bin that points to the real
# <name> binary on the host.  Use this when a test restricts PATH to
# ${BATS_TEST_TMPDIR}/bin for isolation but still needs certain system
# tools (e.g. uname) to be accessible.  No-op if the binary is not found.
create_pass_through_bin() {
  local _name="$1"
  local _real
  _real="$(command -v "$_name")" || return 0
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  ln -sf "$_real" "${BATS_TEST_TMPDIR}/bin/${_name}"
}

# begin_path_isolation [<allowed_cmd>...]
#
# Replaces PATH with ${BATS_TEST_TMPDIR}/bin and optionally injects pass-through
# symlinks for selected host commands. Useful for lean tests that need to prove
# a tool is absent while keeping a minimal set of core utilities available.
begin_path_isolation() {
  if [[ -z "${_STUBS_PATH_SAVED+x}" ]]; then
    _STUBS_PATH_SAVED="$PATH"
  fi
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  local _cmd
  for _cmd in "$@"; do
    create_pass_through_bin "$_cmd"
  done

  export PATH="${BATS_TEST_TMPDIR}/bin"
}

# end_path_isolation
#
# Restores PATH captured by begin_path_isolation.
end_path_isolation() {
  if [[ -n "${_STUBS_PATH_SAVED+x}" ]]; then
    export PATH="$_STUBS_PATH_SAVED"
    unset _STUBS_PATH_SAVED
  fi
}
