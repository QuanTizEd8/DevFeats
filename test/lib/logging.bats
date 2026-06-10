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
_FILE_LIB="${BATS_TEST_DIRNAME}/../../lib/file.sh"
_LOGGING_API="${BATS_TEST_DIRNAME}/../../lib/logging-api.sh"
_LOGGING_LIB="${BATS_TEST_DIRNAME}/../../lib/logging.sh"
_SOURCE_LOGGING="source '${_FILE_LIB}' && source '${_LOGGING_API}' && source '${_LOGGING_LIB}'"

# ---------------------------------------------------------------------------
# logging__setup / logging__cleanup — isolated subprocess tests
# ---------------------------------------------------------------------------

@test "logging__setup creates a temp log file" {
  run bash -c "
    ${_SOURCE_LOGGING}
    logging__setup
    [[ -f \"\${_LOGGING__LOG_FILE_TMP}\" ]] && echo TMPFILE_EXISTS >&3
    logging__cleanup
  "
  assert_success
  assert_output --partial "TMPFILE_EXISTS"
}

@test "logging__setup sets _LOGGING__LIB_SETUP to true" {
  run bash -c "
    ${_SOURCE_LOGGING}
    logging__setup
    [[ \"\${_LOGGING__LIB_SETUP}\" == true ]] && echo SETUP_TRUE >&3
    logging__cleanup
  "
  assert_success
  assert_output --partial "SETUP_TRUE"
}

@test "logging__cleanup resets _LOGGING__LIB_SETUP to false" {
  run bash -c "
    ${_SOURCE_LOGGING}
    logging__setup
    logging__cleanup
    [[ \"\${_LOGGING__LIB_SETUP}\" == false ]] && echo CLEANED
  "
  assert_success
  assert_output --partial "CLEANED"
}

@test "logging__cleanup removes the temp log file" {
  run bash -c "
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
    logging__cleanup
    [[ \"\${_LOGGING__LIB_SETUP}\" == false ]] && echo NOOP_OK
  "
  assert_success
  assert_output --partial "NOOP_OK"
}

@test "logging__setup uses _FILE__SESSION_ROOT for journal and mux" {
  run bash -c "
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
  run bash -c "
    ${_SOURCE_LOGGING}
    logging__info 'hello'
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  assert_output --partial "ℹ️ hello"
}

@test "logging__feature_entry formats script entry line" {
  run bash -c "
    ${_SOURCE_LOGGING}
    logging__feature_entry 'install-git'
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  assert_output --partial "↪️ Script entry: install-git"
}

@test "logging__set_fn_prefix prepends caller function to structured messages" {
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    logging__set_fn_prefix 1
    _demo_fn() {
      logging__info 'inside demo'
    }
    _demo_fn
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  assert_output --partial "ℹ️ _demo_fn: inside demo"
}

@test "logging__set_fn_prefix includes __ template function names" {
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    logging__set_fn_prefix 1
    __demo_template__() {
      logging__info 'from template fn'
    }
    __demo_template__
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  assert_output --partial "ℹ️ __demo_template__: from template fn"
}

@test "logging__setup --fn-prefix combines feature and function prefixes in file" {
  local _dest="${BATS_TEST_TMPDIR}/fn-prefix-combo.log"
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    _feat_fn() { logging__info 'combo'; }
    _feat_fn
    logging__setup --prefix 'install-demo' --fn-prefix
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'ℹ️ install-demo: combo' "$_dest"
  assert_success
}

@test "LOG_LEVEL=warn suppresses logging__info" {
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=warn
    logging__set_level
    logging__info 'should-not-appear'
    logging__warn 'should-appear'
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  assert_output --partial "should-appear"
  refute_output --partial "should-not-appear"
}

@test "LOG_LEVEL=silent allows only logging__fatal" {
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=silent
    logging__set_level
    logging__error 'no-error'
    logging__warn 'no-warn'
    logging__info 'no-info'
    logging__fatal 'yes-fatal'
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  assert_output --partial "yes-fatal"
  refute_output --partial "no-error"
  refute_output --partial "no-warn"
  refute_output --partial "no-info"
}

@test "LOG_LEVEL=debug enables logging__debug" {
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    logging__set_level
    logging__debug 'hidden'
    logging__finalize_parse_buffer
    LOG_LEVEL=debug
    logging__set_level
    logging__debug 'visible'
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  refute_output --partial "hidden"
  assert_output --partial "🐞 visible"
}

@test "LOG_LEVEL=trace also enables logging__debug" {
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=trace
    logging__set_level
    logging__debug 'visible-in-trace'
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  assert_output --partial "🐞 visible-in-trace"
}

@test "logging__set_level toggles xtrace based on LOG_LEVEL" {
  run bash -c "
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
    LOG_LEVEL=warn
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__debug 'file-only-debug'
    logging__cleanup
  " 4> "${BATS_TEST_TMPDIR}/dual.stderr"
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
  run awk '/MARK_A/{a=NR} /MARK_B/{b=NR} /MARK_C/{c=NR} END{exit !(a&&b&&c&&a < b&&b < c)}' "$_dest"
  assert_success
}

@test "structured logs stay ordered after burst subprocess output" {
  # Structured logs written BEFORE a subprocess block are guaranteed to appear
  # before that block's output (MARK_A < PROC_1) because they write directly to
  # the mux FIFO before any process lines are forwarded.
  # Structured logs written AFTER a subprocess burst (MARK_B) may race with the
  # last in-flight process-ingress writes — this is an acceptable trade-off that
  # avoids the harder failure of DFLOG bytes appearing mid-line for large writes.
  # Verified properties: (1) no output is lost, (2) MARK_A precedes all PROC lines.
  local _dest="${BATS_TEST_TMPDIR}/order-burst.log"
  local _stderr="${BATS_TEST_TMPDIR}/order-burst.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info 'MARK_A'
    for _i in \$(seq 1 40); do
      echo \"PROC_\${_i}\"
    done
    logging__info 'MARK_B'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  # MARK_A < PROC_1 is guaranteed (direct FIFO write precedes process-ingress relay)
  run awk '/MARK_A/{a=NR} /PROC_1$/{p=NR} END{exit !(a&&p&&a < p)}' "$_dest"
  assert_success
  run awk '/MARK_A/{a=NR} /PROC_1$/{p=NR} END{exit !(a&&p&&a < p)}' "$_stderr"
  assert_success
  # All 40 process lines must be present (no data loss)
  run bash -c "for i in \$(seq 1 40); do grep -q \"PROC_\${i}\$\" '${_dest}' || exit 1; done"
  assert_success
  run bash -c "for i in \$(seq 1 40); do grep -q \"PROC_\${i}\$\" '${_stderr}' || exit 1; done"
  assert_success
  # Both MARK_A and MARK_B are present
  run grep -q 'MARK_A' "$_dest"
  assert_success
  run grep -q 'MARK_B' "$_dest"
  assert_success
}

@test "script entry precedes buffered argument logs after parse-phase flush" {
  local _dest="${BATS_TEST_TMPDIR}/entry-first.log"
  local _stderr="${BATS_TEST_TMPDIR}/entry-first.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__feature_entry 'Feature v1'
    logging__info 'Script called with no arguments'
    logging__read 'Argument one'
    logging__setup
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run awk '/Script entry: Feature v1/{e=NR} /Script called with no arguments/{a=NR} /Argument one/{o=NR} END{exit !(e&&a&&o&&e < a&&a < o)}' "$_dest"
  assert_success
  run awk '/Script entry: Feature v1/{e=NR} /Script called with no arguments/{a=NR} END{exit !(e&&a&&e < a)}' "$_stderr"
  assert_success
}

@test "parse buffer replays args when LOG_FILE is set after other options" {
  local _dest="${BATS_TEST_TMPDIR}/late-logfile.log"
  local _stderr="${BATS_TEST_TMPDIR}/late-logfile.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    logging__feature_entry 'Feature v1'
    logging__read 'Argument manifest: /tmp/manifest.yaml'
    LOG_FILE='${_dest}'
    logging__read 'Argument log_file: ${_dest}'
    logging__setup
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'Argument manifest' "$_stderr"
  assert_success
  run grep -q 'Argument manifest' "$_dest"
  assert_success
}

@test "logging__setup --prefix decorates buffered and live structured messages" {
  local _dest="${BATS_TEST_TMPDIR}/msg-prefix.log"
  local _stderr="${BATS_TEST_TMPDIR}/msg-prefix.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    logging__feature_entry 'feat v1'
    logging__info 'buffered-before-setup'
    logging__setup --prefix 'install-demo'
    logging__info 'after-setup'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q '↪️ install-demo: Script entry: feat v1' "$_dest"
  assert_success
  run grep -q 'ℹ️ install-demo: buffered-before-setup' "$_dest"
  assert_success
  run grep -q 'ℹ️ install-demo: after-setup' "$_dest"
  assert_success
  run grep -q 'install-demo: buffered-before-setup' "$_stderr"
  assert_success
}

@test "logging__setup --prefix is idempotent when message already prefixed" {
  local _dest="${BATS_TEST_TMPDIR}/msg-prefix-dup.log"
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    logging__set_prefix 'install-demo'
    logging__info 'install-demo: already tagged'
    logging__setup --prefix 'install-demo'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -c 'install-demo: install-demo:' "$_dest"
  assert_output "0"
}

@test "logging works when logging.sh is sourced before logging-api.sh" {
  local _dest="${BATS_TEST_TMPDIR}/reverse-source.log"
  run bash -c "
    source '${_FILE_LIB}'
    source '${_LOGGING_LIB}'
    source '${_LOGGING_API}'
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    logging__info 'reverse-source-order'
    logging__setup
    logging__info 'after-setup'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'reverse-source-order' "$_dest"
  assert_success
  run grep -q 'after-setup' "$_dest"
  assert_success
}

@test "logging__is_setup returns false before setup and true after setup" {
  run bash -c "
    ${_SOURCE_LOGGING}
    logging__error 'pre-setup'
    if ! logging__is_setup; then echo NOT_SETUP; fi
    logging__setup
    if logging__is_setup; then echo SETUP_ACTIVE >&3; fi
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  assert_output --partial "NOT_SETUP"
  assert_output --partial "SETUP_ACTIVE"
}

@test "logging__finalize_parse_buffer replays buffered error on early exit" {
  local _dest="${BATS_TEST_TMPDIR}/early-exit.log"
  local _stderr="${BATS_TEST_TMPDIR}/early-exit.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    logging__read 'Argument one'
    logging__error 'parse-phase-error'
    logging__finalize_parse_buffer
  "
  assert_success
  run grep -q 'parse-phase-error' "$_stderr"
  assert_success
  run grep -q 'parse-phase-error' "$_dest"
  assert_success
  run grep -q 'Argument one' "$_dest"
  assert_success
}

@test "LOG_LEVEL=silent with LOG_FILE captures parse-phase args in file only" {
  local _dest="${BATS_TEST_TMPDIR}/silent-file.log"
  local _stderr="${BATS_TEST_TMPDIR}/silent-file.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=silent
    LOG_FILE_LEVEL=info
    LOG_FILE='${_dest}'
    logging__read 'file-only-arg'
    logging__finalize_parse_buffer
  "
  assert_success
  run grep -q 'file-only-arg' "$_dest"
  assert_success
  run grep -q 'file-only-arg' "$_stderr"
  assert_failure
}

@test "pending journal is replayed at setup" {
  local _dest="${BATS_TEST_TMPDIR}/bootstrap.log"
  local _pending="${BATS_TEST_TMPDIR}/bootstrap.capture"
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE_LEVEL=info
    LOG_FILE='${_dest}'
    _LOGGING__PENDING_FILE='${_pending}'
    export _LOGGING__PENDING_FILE
    printf '%s\t%s\n' 3 'ℹ️ BOOTSTRAP_A' >> \"\${_LOGGING__PENDING_FILE}\"
    printf '%s\t%s\n' 3 'ℹ️ BOOTSTRAP_B' >> \"\${_LOGGING__PENDING_FILE}\"
    logging__set_level
    logging__setup
    logging__info 'AFTER_SETUP'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run awk '/BOOTSTRAP_A/{a=NR} /BOOTSTRAP_B/{b=NR} /AFTER_SETUP/{s=NR} END{exit !(a&&b&&s&&a < b&&b < s)}' "$_dest"
  assert_success
  run test ! -f "${_pending}"
  assert_success
}

@test "install.sh pending journal reaches LOG_FILE when path is set after parse phase" {
  local _dest="${BATS_TEST_TMPDIR}/late-bootstrap.log"
  local _pending="${BATS_TEST_TMPDIR}/install-sh.capture"
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE_LEVEL=info
    _LOGGING__PENDING_FILE='${_pending}'
    export _LOGGING__PENDING_FILE
    printf '%s\t%s\n' 3 '🚀 Starting install.sh script install-git' >> \"\${_LOGGING__PENDING_FILE}\"
    logging__feature_entry 'Git Installation v1'
    logging__read 'Argument log_file: ${_dest}'
    LOG_FILE='${_dest}'
    logging__setup
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'Starting install.sh script install-git' "$_dest"
  assert_success
  run awk '/Starting install.sh script install-git/{b=NR} /Script entry: Git Installation v1/{e=NR} /Argument log_file/{a=NR} END{exit !(b&&e&&a&&b < e&&e < a)}' "$_dest"
  assert_success
  run test ! -f "${_pending}"
  assert_success
}

@test "logging__setup tail is not xtraced into journal" {
  local _dest="${BATS_TEST_TMPDIR}/setup-tail.log"
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE_LEVEL=trace
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info 'MARK_AFTER_SETUP'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'MARK_AFTER_SETUP' "$_dest"
  assert_success
  run grep -q '_LOGGING__LIB_SETUP=true' "$_dest"
  assert_failure
}

@test "parse buffer flush preserves order in journal" {
  local _dest="${BATS_TEST_TMPDIR}/parsebuf.log"
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE_LEVEL=info
    LOG_FILE='${_dest}'
    logging__read 'one'
    logging__read 'two'
    logging__read 'three'
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
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    logging__finalize_parse_buffer
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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

@test "process output starting with + is not classified as xtrace when file trace enabled" {
  local _dest="${BATS_TEST_TMPDIR}/plus-process.log"
  local _stderr="${BATS_TEST_TMPDIR}/plus-process.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=trace
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    echo '+ plus-output-marker'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q '+ plus-output-marker' "$_stderr"
  assert_success
  run grep -q '+ plus-output-marker' "$_dest"
  assert_success
}

@test "xtrace with foreign PS4 does not leak to console when LOG_LEVEL=debug" {
  local _dest="${BATS_TEST_TMPDIR}/foreign-ps4.log"
  local _stderr="${BATS_TEST_TMPDIR}/foreign-ps4.stderr"
  run bash -c "
    PS4='* '
    export PS4
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=trace
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    _f() { local _e=\"\$1\"; [[ \"\${_e}\" == \"~\"* ]]; }
    _f foo
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -qE '(\[\[|_f |foo)' "$_dest"
  assert_success
  run grep -E '^(\+|\*)' "$_stderr"
  assert_failure
}

@test "structured process and xtrace preserve order on console without trace and on file with trace" {
  local _dest="${BATS_TEST_TMPDIR}/order-xt.log"
  local _stderr="${BATS_TEST_TMPDIR}/order-xt.stderr"
  run bash -c "
    PS4='* '
    export PS4
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=trace
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info 'MARK_A'
    _x=1
    echo 'MARK_B'
    logging__info 'MARK_C'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run awk '/MARK_A/{a=NR} /MARK_B/{b=NR} /MARK_C/{c=NR} END{exit !(a&&b&&c&&a < b&&b < c)}' "$_stderr"
  assert_success
  run awk '/MARK_A/{a=NR} /MARK_B/{b=NR} /MARK_C/{c=NR} END{exit !(a&&b&&c&&a < b&&b < c)}' "$_dest"
  assert_success
  run grep -q '_x=1' "$_dest"
  assert_success
  run grep '_x=1' "$_stderr"
  assert_failure
}

@test "xtrace DFLOG records do not concatenate with partial process output" {
  local _dest="${BATS_TEST_TMPDIR}/partial-proc.log"
  local _stderr="${BATS_TEST_TMPDIR}/partial-proc.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=trace
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    echo -n 'Reading package lists...'
    :
    echo
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'DFLOG' "$_stderr"
  assert_failure
  run grep -q 'Reading package lists...DFLOG' "$_stderr"
  assert_failure
  run grep -q 'Reading package lists...DFLOG' "$_dest"
  assert_failure
  run grep -q 'Reading package lists...' "$_stderr"
  assert_success
}

@test "xtrace appears in file only when LOG_FILE_LEVEL=trace and LOG_LEVEL=info" {
  local _dest="${BATS_TEST_TMPDIR}/xtrace-file.log"
  local _stderr="${BATS_TEST_TMPDIR}/xtrace-file.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
  run awk '/MARK_A/{a=NR} /MARK_B/{b=NR} /MARK_C/{c=NR} END{exit !(a&&b&&c&&a < b&&b < c)}' "$_dest"
  assert_success
  run awk '/MARK_A/{a=NR} /MARK_B/{b=NR} /MARK_C/{c=NR} END{exit !(a&&b&&c&&a < b&&b < c)}' "$_stderr"
  assert_success
}

@test "logging__error file-only when LOG_LEVEL=silent and LOG_FILE_LEVEL=error" {
  local _dest="${BATS_TEST_TMPDIR}/err-file.log"
  local _stderr="${BATS_TEST_TMPDIR}/err-file.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE='${_dest}'
    logging__info 'buffered-until-setup'
    [[ -n \"\${_LOGGING__PENDING_FILE:-}\" && -s \"\${_LOGGING__PENDING_FILE}\" ]] && echo HAS_BUFFER
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
    ${_SOURCE_LOGGING}
    LOG_LEVEL=silent
    logging__set_level
    logging__fatal 'always-console'
    logging__finalize_parse_buffer
  " 2>&1
  assert_success
  assert_output --partial "always-console"
}

@test "logging__set_level warns on unknown LOG_LEVEL before setup" {
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_LEVEL=notalevel
    logging__set_level
  " 2>&1
  assert_success
  assert_output --partial "Unknown LOG_LEVEL"
  assert_output --partial "notalevel"
}

@test "logging__set_level warns on unknown LOG_FILE_LEVEL before setup" {
  run bash -c "
    ${_SOURCE_LOGGING}
    LOG_FILE_LEVEL=notalevel
    logging__set_level
  " 2>&1
  assert_success
  assert_output --partial "Unknown LOG_FILE_LEVEL"
}

@test "logging__setup is idempotent" {
  run bash -c "
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
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
    ${_SOURCE_LOGGING}
    logging__setup
    _dir=\"\${_FILE__SESSION_ROOT}\"
    logging__cleanup
    [[ -d \"\${_dir}\" ]] && echo STILL_THERE
    file__session_cleanup
  "
  assert_success
  assert_output --partial "STILL_THERE"
}

@test "ERR trap aborts on unlogged command failure after logging__setup" {
  run bash -c "
    ${_SOURCE_LOGGING}
    set -E
    __err__() {
      local _rc=\$?
      local _cmd=\"\${BASH_COMMAND}\"
      logging__is_setup || exit \"\$_rc\"
      logging__error \"command failed (exit \${_rc}): \${_cmd}\"
      exit \"\$_rc\"
    }
    trap '__err__' ERR
    LOG_LEVEL=info
    logging__setup --prefix err-trap
    logging__info 'phase-one'
    false
    logging__info 'phase-two'
    logging__cleanup
  "
  assert_failure
  assert_output --partial 'phase-one'
  assert_output --partial 'command failed (exit 1): false'
  refute_output --partial 'phase-two'
}

@test "ERR trap logs command failure location even when helper logs its own error" {
  run bash -c "
    ${_SOURCE_LOGGING}
    set -E
    __err__() {
      local _rc=\$?
      local _cmd=\"\${BASH_COMMAND}\"
      logging__is_setup || exit \"\$_rc\"
      logging__error \"command failed (exit \${_rc}): \${_cmd}\"
      exit \"\$_rc\"
    }
    trap '__err__' ERR
    LOG_LEVEL=info
    logging__setup --prefix err-trap
    helper__fail() { logging__error 'specific failure'; return 1; }
    run__flow() { logging__info 'before'; helper__fail; logging__info 'after'; }
    run__flow
    logging__cleanup
  "
  assert_failure
  assert_output --partial 'before'
  assert_output --partial 'specific failure'
  assert_output --partial 'command failed'
  refute_output --partial 'after'
}

@test "newline in structured message is encoded for FIFO" {
  local _dest="${BATS_TEST_TMPDIR}/newline.log"
  run bash -c "
    ${_SOURCE_LOGGING}
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

# ---------------------------------------------------------------------------
# Output integrity — no raw DFLOG in any sink
# ---------------------------------------------------------------------------
# These tests guard against the DFLOG-leakage bug where internal FIFO protocol
# records (prefixed with "DFLOG<TAB>") escaped into visible console or file output.

@test "no raw DFLOG prefix in console or file for structured messages" {
  # Structured log records travel through the mux as DFLOG S records.
  # After dispatch the DFLOG prefix must be stripped; the consumer sees only
  # the formatted message (emoji + text).
  # Uses $'DFLOG\t' (literal tab) to match only unstripped protocol records,
  # not xtrace lines that happen to contain the string "DFLOG" as text.
  local _dest="${BATS_TEST_TMPDIR}/integrity-struct.log"
  local _stderr="${BATS_TEST_TMPDIR}/integrity-struct.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE_LEVEL=info
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info 'alpha'
    logging__warn 'beta'
    logging__error 'gamma'
    logging__success 'delta'
    logging__feature_entry 'feat v1'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q $'DFLOG\t' "${_stderr}"
  assert_failure
  run grep -q $'DFLOG\t' "${_dest}"
  assert_failure
}

@test "no raw DFLOG prefix in console or file for process output" {
  # Process output travels through the process-ingress coprocess as DFLOG O records.
  # The coprocess encodes each echo line and forwards it to the mux; the mux reader
  # must strip the prefix before dispatching to console / file.
  local _dest="${BATS_TEST_TMPDIR}/integrity-proc.log"
  local _stderr="${BATS_TEST_TMPDIR}/integrity-proc.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    echo 'proc-line-one'
    echo 'proc-line-two'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q $'DFLOG\t' "${_stderr}"
  assert_failure
  run grep -q $'DFLOG\t' "${_dest}"
  assert_failure
}

@test "no raw DFLOG prefix in console or file when xtrace enabled" {
  # Xtrace output travels via a dedicated coprocess as DFLOG X records written
  # directly to the mux FIFO. The mux reader must strip the prefix.
  # Note: xtrace of internal printf calls shows the literal string "DFLOG\t" (with
  # backslash-t, not a real tab) in the file — those are harmless and excluded by
  # the $'DFLOG\t' (real tab) pattern.
  local _dest="${BATS_TEST_TMPDIR}/integrity-xtrace.log"
  local _stderr="${BATS_TEST_TMPDIR}/integrity-xtrace.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    LOG_FILE_LEVEL=trace
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    _v=calculated
    logging__info 'after-xtrace-ops'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q $'DFLOG\t' "${_stderr}"
  assert_failure
  run grep -q $'DFLOG\t' "${_dest}"
  assert_failure
  # Verify xtrace content was actually present so the test exercises the path.
  run grep -q '^+' "${_dest}"
  assert_success
}

@test "no raw DFLOG when process output line exceeds PIPE_BUF (4096 bytes)" {
  # A subprocess line longer than PIPE_BUF triggers a non-atomic write to the mux
  # FIFO. The process-ingress must cap the encoded payload at 4081 bytes so the
  # total printf write (prefix+payload+newline = 4092) stays within one atomic write.
  local _dest="${BATS_TEST_TMPDIR}/large-proc.log"
  local _stderr="${BATS_TEST_TMPDIR}/large-proc.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    python3 -c \"print('X' * 8192)\"
    logging__info 'AFTER_LARGE'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q $'DFLOG\t' "${_stderr}"
  assert_failure
  run grep -q $'DFLOG\t' "${_dest}"
  assert_failure
  run grep -q 'AFTER_LARGE' "${_dest}"
  assert_success
  # Verify the large line was captured but truncated to <=4081 bytes
  run bash -c "grep '^X' '${_dest}' | awk '{print length}' | awk '\$1 > 4081 {exit 1}'"
  assert_success
}

# ---------------------------------------------------------------------------
# Ordering — multiple sequential subprocess invocations
# ---------------------------------------------------------------------------

@test "multiple interleaved logging and process calls preserve order on both sinks" {
  # Tests the common A→echo1→B→echo2→C pattern. A single for-loop burst (existing
  # test 34) does not cover separate subprocess boundaries between structured logs.
  local _dest="${BATS_TEST_TMPDIR}/multi-proc-order.log"
  local _stderr="${BATS_TEST_TMPDIR}/multi-proc-order.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    LOG_FILE_LEVEL=debug
    LOG_FILE='${_dest}'
    logging__set_level
    logging__setup
    logging__info 'MARK_A'
    echo 'PROC_1'
    logging__info 'MARK_B'
    echo 'PROC_2'
    logging__info 'MARK_C'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run awk '/MARK_A/{a=NR} /PROC_1/{p1=NR} /MARK_B/{b=NR} /PROC_2/{p2=NR} /MARK_C/{c=NR} \
    END{exit !(a&&p1&&b&&p2&&c&&a<p1&&p1<b&&b<p2&&p2<c)}' "${_dest}"
  assert_success
  run awk '/MARK_A/{a=NR} /PROC_1/{p1=NR} /MARK_B/{b=NR} /PROC_2/{p2=NR} /MARK_C/{c=NR} \
    END{exit !(a&&p1&&b&&p2&&c&&a<p1&&p1<b&&b<p2&&p2<c)}' "${_stderr}"
  assert_success
}

# ---------------------------------------------------------------------------
# Ordering — console-only sink (no LOG_FILE)
# ---------------------------------------------------------------------------

@test "structured and process output preserve order on console when LOG_FILE is not set" {
  # All existing ordering tests also set LOG_FILE. This verifies ordering holds
  # for the console sink in isolation (LOG_FILE unset, LOG_LEVEL=debug).
  local _stderr="${BATS_TEST_TMPDIR}/order-console-only.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    logging__set_level
    logging__setup
    logging__info 'MARK_A'
    echo 'MARK_B'
    logging__info 'MARK_C'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run awk '/MARK_A/{a=NR} /MARK_B/{b=NR} /MARK_C/{c=NR} \
    END{exit !(a&&b&&c&&a<b&&b<c)}' "${_stderr}"
  assert_success
}

# ---------------------------------------------------------------------------
# Level filtering — process output routing with no LOG_FILE
# ---------------------------------------------------------------------------

@test "process output reaches console when LOG_LEVEL=debug and LOG_FILE is not set" {
  # Counterpart to test "process output suppressed when both sinks below debug"
  # (which also sets LOG_FILE). Verifies the positive path on console alone.
  local _stderr="${BATS_TEST_TMPDIR}/proc-console-only.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=debug
    logging__set_level
    logging__setup
    echo 'MARK_PROC_CONSOLE'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'MARK_PROC_CONSOLE' "${_stderr}"
  assert_success
}

@test "process output is suppressed from console when LOG_LEVEL=info and LOG_FILE is not set" {
  # Verifies that when neither sink wants process output (LOG_LEVEL=info, no file),
  # stdout is routed to /dev/null and does not appear anywhere.
  local _stderr="${BATS_TEST_TMPDIR}/proc-suppressed-nofile.stderr"
  run bash -c "
    exec 2>'${_stderr}'
    ${_SOURCE_LOGGING}
    LOG_LEVEL=info
    logging__set_level
    logging__setup
    echo 'SHOULD_NOT_APPEAR'
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  run grep -q 'SHOULD_NOT_APPEAR' "${_stderr}"
  assert_failure
}
