#!/usr/bin/env bats
# Unit tests for lib/logging.sh
#
# logging__setup uses 'exec 3>&1 4>&2' to save/redirect file descriptors.
# Bats itself uses fd 3 internally for TAP output, so tests that call
# logging__setup must run in isolated subprocesses via 'run bash -c' to
# avoid corrupting bats' own fd setup.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
}

# Absolute paths to lib files for use inside bash -c subshells.
_LOGGING_LIB="${BATS_TEST_DIRNAME}/../../lib/logging.sh"
_FILE_LIB="${BATS_TEST_DIRNAME}/../../lib/file.sh"

# ---------------------------------------------------------------------------
# logging__setup / logging__cleanup — isolated subprocess tests
# ---------------------------------------------------------------------------

@test "logging__setup creates a temp log file" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    [[ -f \"\${_LOGGING__LOG_FILE_TMP}\" ]] && echo TMPFILE_EXISTS >&3
    logging__cleanup
  "
  assert_success
  assert_output --partial "TMPFILE_EXISTS"
}

@test "logging__setup sets _LOGGING__LIB_SETUP to true" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    [[ \"\${_LOGGING__LIB_SETUP}\" == true ]] && echo SETUP_TRUE >&3
    logging__cleanup
  "
  assert_success
  assert_output --partial "SETUP_TRUE"
}

@test "logging__cleanup resets _LOGGING__LIB_SETUP to false" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    logging__cleanup
    [[ \"\${_LOGGING__LIB_SETUP}\" == false ]] && echo CLEANED
  "
  assert_success
  assert_output --partial "CLEANED"
}

@test "logging__cleanup removes the temp log file" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    _tmp=\"\${_LOGGING__LOG_FILE_TMP}\"
    logging__cleanup
    file__session_cleanup
    [[ ! -f \"\${_tmp}\" ]] && echo FILE_GONE
  "
  assert_success
  assert_output --partial "FILE_GONE"
}

@test "logging__cleanup writes captured output to LOG_FILE when set" {
  local _dest="${BATS_TEST_TMPDIR}/out.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    echo 'hello log'
    logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "hello log" "$_dest"
  assert_success
}

@test "logging__cleanup is a no-op when setup was never called" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__cleanup
    [[ \"\${_LOGGING__LIB_SETUP}\" == false ]] && echo NOOP_OK
  "
  assert_success
  assert_output --partial "NOOP_OK"
}

@test "logging__setup uses _FILE__SESSION_ROOT for journal and mux" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    [[ -d \"\${_FILE__SESSION_ROOT}\" ]] && echo DIR_EXISTS >&3
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  assert_output --partial "DIR_EXISTS"
}

@test "file__session_cleanup removes session scratch tree" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    _dir=\"\${_FILE__SESSION_ROOT}\"
    logging__cleanup
    file__session_cleanup
    [[ ! -d \"\${_dir}\" ]] && echo DIR_GONE
  "
  assert_success
  assert_output --partial "DIR_GONE"
}

@test "file__session_cleanup resets _FILE__SESSION_ROOT to empty" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    logging__cleanup
    file__session_cleanup
    [[ -z \"\${_FILE__SESSION_ROOT}\" ]] && echo CLEARED
  "
  assert_success
  assert_output --partial "CLEARED"
}

@test "file__session_cleanup removes tree when logging__setup was never called" {
  run bash -c "
    source '${_FILE_LIB}'
    file__session_ensure
    _sub=\"\$(file__tmpdir 'orphan')\"
    _root=\"\${_FILE__SESSION_ROOT}\"
    file__session_cleanup
    [[ ! -d \"\${_root}\" ]] && echo ORPHAN_GONE
  "
  assert_success
  assert_output --partial "ORPHAN_GONE"
}

@test "file__session_cleanup does not rm injected session root" {
  local _pin="${BATS_TEST_TMPDIR}/pinned-session"
  mkdir -p "$_pin"
  run bash -c "
    export _FILE__SESSION_ROOT='${_pin}'
    source '${_FILE_LIB}'
    file__session_cleanup
    [[ -d '${_pin}' ]] && echo PIN_STILL_THERE
  "
  assert_success
  assert_output --partial "PIN_STILL_THERE"
}

@test "file__mktmpdir after file__session_ensure uses same session root" {
  run bash -c "
    source '${_FILE_LIB}'
    file__session_ensure
    _d=\"\$(file__mktmpdir 'probe')\"
    [[ \"\${_d}\" == \"\${_FILE__SESSION_ROOT}\"/* ]] && echo UNDER_ROOT
    file__session_cleanup
  "
  assert_success
  assert_output --partial "UNDER_ROOT"
}

@test "file__tmpdir creates a subdirectory inside _FILE__SESSION_ROOT" {
  run bash -c "
    source '${_LOGGING_LIB}'
    source '${_FILE_LIB}'
    logging__setup
    _sub=\"\$(file__tmpdir 'mymod')\"
    [[ -d \"\${_sub}\" ]] && echo SUBDIR_EXISTS >&3
    [[ \"\${_sub}\" == \"\${_FILE__SESSION_ROOT}/mymod\" ]] && echo PATH_CORRECT >&3
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  assert_output --partial "SUBDIR_EXISTS"
  assert_output --partial "PATH_CORRECT"
}

@test "file__tmpdir is idempotent" {
  run bash -c "
    source '${_LOGGING_LIB}'
    source '${_FILE_LIB}'
    logging__setup
    _p1=\"\$(file__tmpdir 'x')\"
    _p2=\"\$(file__tmpdir 'x')\"
    [[ \"\${_p1}\" == \"\${_p2}\" ]] && echo SAME_PATH >&3
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  assert_output --partial "SAME_PATH"
}

@test "file__tmpdir lazy-inits _FILE__SESSION_ROOT without logging__setup" {
  run bash -c "
    source '${_FILE_LIB}'
    _sub=\"\$(file__tmpdir 'lazy')\"
    [[ -d \"\${_sub}\" ]] && echo LAZY_OK
  "
  assert_success
  assert_output --partial "LAZY_OK"
}

# ---------------------------------------------------------------------------
# logging__mask_secret / GITHUB_TOKEN masking
# ---------------------------------------------------------------------------

@test "logging__mask_secret redacts registered value in LOG_FILE" {
  local _dest="${BATS_TEST_TMPDIR}/masked.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__mask_secret 'supersecret'
    echo 'value is supersecret here'
    logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "supersecret" "$_dest"
  assert_failure # must NOT appear literally
  run grep '\*\*\*' "$_dest"
  assert_success # placeholder must appear
}

@test "logging__mask_secret does not redact unregistered values" {
  local _dest="${BATS_TEST_TMPDIR}/plain.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    echo 'value is notasecret here'
    logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "notasecret" "$_dest"
  assert_success # must appear unchanged
}

@test "logging__mask_secret redacts multiple values in LOG_FILE" {
  local _dest="${BATS_TEST_TMPDIR}/multi.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    logging__set_level
    logging__setup
    logging__mask_secret 'token-aaa'
    logging__mask_secret 'token-bbb'
    echo 'first token-aaa second token-bbb done'
    LOG_FILE='${_dest}' logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "token-aaa" "$_dest"
  assert_failure
  run grep "token-bbb" "$_dest"
  assert_failure
}

@test "logging__setup auto-masks GITHUB_TOKEN in LOG_FILE" {
  local _dest="${BATS_TEST_TMPDIR}/ghtoken.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    export GITHUB_TOKEN='ghp_testtoken123'
    LOG_LEVEL=debug
    logging__set_level
    logging__setup
    echo \"token value is \${GITHUB_TOKEN}\"
    LOG_FILE='${_dest}' logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "ghp_testtoken123" "$_dest"
  assert_failure # must NOT appear literally
}

@test "logging__cleanup resets _LOGGING__SYSSET_MASKED_VALUES to empty" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    logging__mask_secret 'some-secret'
    logging__cleanup
    [[ \${#_LOGGING__SYSSET_MASKED_VALUES[@]} -eq 0 ]] && echo EMPTY
  "
  assert_success
  assert_output --partial "EMPTY"
}

# ---------------------------------------------------------------------------
# logging__* message helpers + LOG_LEVEL
# ---------------------------------------------------------------------------

@test "logging__info prints one line to stderr" {
  run bash -c "source '${_LOGGING_LIB}'; logging__info 'hello'" 2>&1
  assert_success
  assert_output --partial "ℹ️ hello"
}

@test "logging__feature_entry formats script entry line" {
  run bash -c "source '${_LOGGING_LIB}'; logging__feature_entry 'install-git'" 2>&1
  assert_success
  assert_output --partial "↪️ Script entry: install-git"
}

@test "logging__fn_entry and logging__fn_exit use trace emojis" {
  run bash -c "source '${_LOGGING_LIB}'; logging__fn_entry 'foo'; logging__fn_exit 'foo (ok)'" 2>&1
  assert_success
  assert_output --partial "↪️ Function entry: foo"
  assert_output --partial "↩️ Function exit: foo (ok)"
}

@test "LOG_LEVEL=warn suppresses logging__info" {
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=warn
    logging__set_level
    logging__info 'should-not-appear'
    logging__warn 'should-appear'
  " 2>&1
  assert_success
  assert_output --partial "should-appear"
  refute_output --partial "should-not-appear"
}

@test "LOG_LEVEL=silent allows only logging__fatal" {
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=silent
    logging__set_level
    logging__error 'no-error'
    logging__warn 'no-warn'
    logging__info 'no-info'
    logging__fatal 'yes-fatal'
  " 2>&1
  assert_success
  assert_output --partial "yes-fatal"
  refute_output --partial "no-error"
  refute_output --partial "no-warn"
  refute_output --partial "no-info"
}

@test "LOG_LEVEL=debug enables logging__debug" {
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    logging__set_level
    logging__debug 'hidden'
    LOG_LEVEL=debug
    logging__set_level
    logging__debug 'visible'
  " 2>&1
  assert_success
  refute_output --partial "hidden"
  assert_output --partial "🐞 visible"
}

@test "LOG_LEVEL=trace also enables logging__debug" {
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=trace
    logging__set_level
    logging__debug 'visible-in-trace'
  " 2>&1
  assert_success
  assert_output --partial "🐞 visible-in-trace"
}

@test "logging__set_level toggles xtrace based on LOG_LEVEL" {
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=trace
    logging__set_level
    logging__setup
    [[ \"\$-\" == *x* ]] && echo on >&3 || echo off >&3
    LOG_LEVEL=info
    logging__set_level
    [[ \"\$-\" == *x* ]] && echo on >&3 || echo off >&3
    logging__cleanup
  "
  assert_success
  assert_output --partial "on"
  assert_output --partial "off"
}

# ---------------------------------------------------------------------------
# Dual thresholds, ordering, parse buffer
# ---------------------------------------------------------------------------

@test "LOG_FILE_LEVEL=debug shows logging__debug only in file not console" {
  local _dest="${BATS_TEST_TMPDIR}/dual.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=warn
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__debug 'file-only-debug'
    logging__cleanup
  " 4>"${BATS_TEST_TMPDIR}/dual.stderr"
  assert_success
  run grep -q 'file-only-debug' "${BATS_TEST_TMPDIR}/dual.stderr"
  assert_failure
  run grep -q '🐞 file-only-debug' "$_dest"
  assert_success
}

@test "LOG_LEVEL=debug shows logging__debug on console but not in file when LOG_FILE_LEVEL=warn" {
  local _dest="${BATS_TEST_TMPDIR}/dual2.log"
  local _stderr="${BATS_TEST_TMPDIR}/dual2.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=warn
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__debug 'console-only-debug'
    logging__cleanup
  "
  assert_success
  run grep -q 'console-only-debug' "$_stderr"
  assert_success
  run grep -q 'console-only-debug' "$_dest"
  assert_failure
}

@test "structured and process output preserve execution order in file" {
  local _dest="${BATS_TEST_TMPDIR}/order.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info 'MARK_A'
    echo 'MARK_B'
    logging__info 'MARK_C'
    logging__cleanup
  "
  assert_success
  run awk '/MARK_A/{a=1} /MARK_B/{b=1} /MARK_C/{c=1} END{exit !(a&&b&&c)}' "$_dest"
  assert_success
}

@test "parse buffer flush preserves order in journal" {
  local _dest="${BATS_TEST_TMPDIR}/parsebuf.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    LOG_FILE_LEVEL=info
    LOG_FILE='${_dest}'
    logging__read 'one'
    logging__read 'two'
    logging__read 'three'
    logging__set_level
    logging__setup
    logging__cleanup
  "
  assert_success
  run grep 'one' "$_dest"
  assert_success
  run awk '/one/{a=1} /two/{b=1} /three/{c=1} END{exit !(a&&b&&c)}' "$_dest"
  assert_success
}

@test "logging__error before setup is not duplicated after flush" {
  local _dest="${BATS_TEST_TMPDIR}/errdup.log"
  local _stderr="${BATS_TEST_TMPDIR}/errdup.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    logging__set_level
    logging__error 'parse-error-once'
    logging__setup
    logging__cleanup
  "
  assert_success
  run grep -c 'parse-error-once' "$_stderr"
  assert_output "1"
  run grep -c 'parse-error-once' "$_dest"
  assert_output "1"
}

@test "LOG_FILE empty ignores LOG_FILE_LEVEL for journal" {
  local _dest="${BATS_TEST_TMPDIR}/nofile.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    LOG_FILE_LEVEL=trace
    logging__set_level
    logging__setup
    logging__debug 'no-journal'
    LOG_FILE='' logging__cleanup
    [[ ! -f '${_dest}' ]]
  "
  assert_success
}

@test "logging__fatal appears in LOG_FILE when log_file_level is silent" {
  local _dest="${BATS_TEST_TMPDIR}/fatal.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=silent
    LOG_FILE_LEVEL=silent
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__fatal 'must-be-in-file'
    logging__cleanup
  "
  assert_success
  run grep -q 'must-be-in-file' "$_dest"
  assert_success
}

@test "structured log with tab in message does not break FIFO dispatch" {
  local _dest="${BATS_TEST_TMPDIR}/tab.log"
  local _stderr="${BATS_TEST_TMPDIR}/tab.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info \$'line\twith\ttabs'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'with' "$_dest"
  assert_success
  run grep -q 'tabs' "$_dest"
  assert_success
}

@test "logging__phase helpers emit expected emoji" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__detect 'd1'
    logging__inspect 'i1'
    logging__install 'p1'
    logging__download 'dl'
    logging__build 'b1'
    logging__remove 'r1'
    logging__clean 'c1'
    logging__launch 'l1'
    logging__read 'rd'
    logging__success 'ok'
  " 2>&1
  assert_success
  assert_output --partial "🛠️ d1"
  assert_output --partial "🔍 i1"
  assert_output --partial "📦 p1"
  assert_output --partial "📥 dl"
  assert_output --partial "🔨 b1"
  assert_output --partial "🗑️ r1"
  assert_output --partial "🧹 c1"
  assert_output --partial "🚀 l1"
  assert_output --partial "📩 rd"
  assert_output --partial "✅ ok"
}

# ---------------------------------------------------------------------------
# Dual thresholds — process output, xtrace, edge cases
# ---------------------------------------------------------------------------

@test "process output suppressed when both sinks below debug" {
  local _dest="${BATS_TEST_TMPDIR}/proc-suppressed.log"
  local _stderr="${BATS_TEST_TMPDIR}/proc-suppressed.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    LOG_FILE_LEVEL=info
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    echo 'MARK_PROCESS'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'MARK_PROCESS' "$_dest"
  assert_failure
  run grep -q 'MARK_PROCESS' "$_stderr"
  assert_failure
}

@test "process output captured in file only when LOG_FILE_LEVEL=debug and LOG_LEVEL=warn" {
  local _dest="${BATS_TEST_TMPDIR}/proc-file.log"
  local _stderr="${BATS_TEST_TMPDIR}/proc-file.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=warn
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    echo 'MARK_PROCESS'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'MARK_PROCESS' "$_dest"
  assert_success
  run grep -q 'MARK_PROCESS' "$_stderr"
  assert_failure
}

@test "xtrace appears in file only when LOG_FILE_LEVEL=trace and LOG_LEVEL=info" {
  local _dest="${BATS_TEST_TMPDIR}/xtrace-file.log"
  local _stderr="${BATS_TEST_TMPDIR}/xtrace-file.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    LOG_FILE_LEVEL=trace
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    :
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q '^+' "$_dest"
  assert_success
  run grep -q '^+' "$_stderr"
  assert_failure
}

@test "xtrace appears on console only when LOG_LEVEL=trace and LOG_FILE_LEVEL=info" {
  local _dest="${BATS_TEST_TMPDIR}/xtrace-console.log"
  local _stderr="${BATS_TEST_TMPDIR}/xtrace-console.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=trace
    LOG_FILE_LEVEL=info
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    :
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q '^+' "$_stderr"
  assert_success
  run grep -q '^+' "$_dest"
  assert_failure
}

@test "console and file preserve interleaved order on both sinks" {
  local _dest="${BATS_TEST_TMPDIR}/order-both.log"
  local _stderr="${BATS_TEST_TMPDIR}/order-both.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info 'MARK_A'
    echo 'MARK_B'
    logging__info 'MARK_C'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run awk '/MARK_A/{a=1} /MARK_B/{b=1} /MARK_C/{c=1} END{exit !(a&&b&&c)}' "$_dest"
  assert_success
  run awk '/MARK_A/{a=1} /MARK_B/{b=1} /MARK_C/{c=1} END{exit !(a&&b&&c)}' "$_stderr"
  assert_success
}

@test "logging__error file-only when LOG_LEVEL=silent and LOG_FILE_LEVEL=error" {
  local _dest="${BATS_TEST_TMPDIR}/err-file.log"
  local _stderr="${BATS_TEST_TMPDIR}/err-file.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=silent
    LOG_FILE_LEVEL=error
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__error 'file-only-error'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'file-only-error' "$_dest"
  assert_success
  run grep -q 'file-only-error' "$_stderr"
  assert_failure
}

@test "parse-phase logging__info is buffered until setup then appears once per sink" {
  local _dest="${BATS_TEST_TMPDIR}/parse-info.log"
  local _stderr="${BATS_TEST_TMPDIR}/parse-info.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    logging__set_level
    logging__info 'buffered-until-setup'
    [[ \${#_LOGGING__PARSE_BUFFER[@]} -gt 0 ]] && echo HAS_BUFFER
    logging__setup
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  assert_output --partial "HAS_BUFFER"
  run grep -c 'buffered-until-setup' "$_stderr"
  assert_output "1"
  run grep -c 'buffered-until-setup' "$_dest"
  assert_output "1"
}

@test "logging__fatal always reaches console when LOG_LEVEL=silent" {
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=silent
    logging__set_level
    logging__fatal 'always-console'
  " 2>&1
  assert_success
  assert_output --partial "always-console"
}

@test "logging__set_level warns on unknown LOG_LEVEL before setup" {
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=notalevel
    logging__set_level
  " 2>&1
  assert_success
  assert_output --partial "Unknown LOG_LEVEL"
  assert_output --partial "notalevel"
}

@test "logging__set_level warns on unknown LOG_FILE_LEVEL before setup" {
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_FILE_LEVEL=notalevel
    logging__set_level
  " 2>&1
  assert_success
  assert_output --partial "Unknown LOG_FILE_LEVEL"
}

@test "logging__setup is idempotent" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    _pid1=\"\${_LOGGING__MUX_READER_PID}\"
    logging__setup
    [[ \"\${_LOGGING__MUX_READER_PID}\" == \"\${_pid1}\" ]] && echo SAME_READER >&3
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  assert_output --partial "SAME_READER"
}

@test "logging__cleanup appends to existing LOG_FILE" {
  local _dest="${BATS_TEST_TMPDIR}/append.log"
  printf 'prior-line\n' > "$_dest"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info 'new-line'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'prior-line' "$_dest"
  assert_success
  run grep -q 'new-line' "$_dest"
  assert_success
}

@test "logging__feature_exit recorded in LOG_FILE when level allows" {
  local _dest="${BATS_TEST_TMPDIR}/feat-exit.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=info
    LOG_FILE_LEVEL=info
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__feature_exit 'feat v1.0'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'Script exit: feat v1.0' "$_dest"
  assert_success
}

@test "logging__cleanup without file__session_cleanup leaves owned session dir" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    _dir=\"\${_FILE__SESSION_ROOT}\"
    logging__cleanup
    [[ -d \"\${_dir}\" ]] && echo STILL_THERE
    file__session_cleanup
  "
  assert_success
  assert_output --partial "STILL_THERE"
}

@test "newline in structured message is encoded for FIFO" {
  local _dest="${BATS_TEST_TMPDIR}/newline.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info \$'line1\nline2'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -c 'line1 line2' "$_dest"
  assert_output "1"
}
