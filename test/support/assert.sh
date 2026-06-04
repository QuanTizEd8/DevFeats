#!/bin/sh
# shellcheck shell=sh disable=SC3043,SC3045
# assert.sh — Shared assertion helpers for all test/ scenarios.
#
# POSIX sh compatible; usable from both #!/bin/bash and #!/bin/sh test scripts.
#
# API-compatible with dev-container-features-test-lib:
#   check "label" <cmd> [args...]                   — passes if <cmd> exits 0
#   fail_check "label" <cmd> [args...]              — passes if <cmd> exits non-zero
#   checkMultiple "label" <min> "cmd1" ["cmd2"...]  — passes if ≥ <min> cmds exit 0
#
# Install-failure scenarios (expect_install_failure in scenarios.yaml) validate
# exit code and output substrings in the test runner — not here.
#   reportResults                                   — print summary; exit 1 if any failed
#
# On failure, check/fail_check print the quoted command and captured output.
# If any check failed, reportResults runs _test_failure_diagnostics when that
# function is defined in the test script (optional hook).
#   log_install_homebrew_shell_init_diagnostics [HOME] [login_file] — stderr dump
#
# macOS block-cleanup helpers:
#   block_cleanup "<marker>" "<file>"   — remove a named block from a file in-place
#   block_cleanup_all "<marker>"        — remove from all standard shell init files
#   shellenv_block_cleanup "<file>"     — remove install-homebrew prefix activation block
#
# File server helpers (dist scenarios):
#   start_file_server <dir> <port>      — start python3 HTTP server in background
#   stop_file_server                    — stop the background server
#   wait_for_port <port> [<timeout_s>]  — block until TCP port is open

_TEST_PASS=0
_TEST_FAIL=0
_TEST_FAILURES="" # Newline-separated failure labels

# Print argv as a space-separated string (best-effort display for failure logs).
_check_quote_argv() {
  printf '%s' "$*"
}

check() {
  local _label="$1"
  shift
  local _out _rc
  _out="$("$@" 2>&1)" && _rc=0 || _rc=$?
  if [ "$_rc" -eq 0 ]; then
    printf '  \xe2\x9c\x85  PASS \xe2\x80\x94 %s\n' "$_label"
    _TEST_PASS=$((_TEST_PASS + 1))
  else
    printf '  \xe2\x9d\x8c  FAIL \xe2\x80\x94 %s (exit %d)\n' "$_label" "$_rc"
    printf '         command: %s\n' "$(_check_quote_argv "$@")"
    [ -n "$_out" ] && printf '         output:\n%s\n' "$_out"
    _TEST_FAILURES="${_TEST_FAILURES:+${_TEST_FAILURES}
}${_label}"
    _TEST_FAIL=$((_TEST_FAIL + 1))
  fi
}

# Inverse of check: passes when <cmd> exits non-zero.
fail_check() {
  local _label="$1"
  shift
  local _out _rc
  _out="$("$@" 2>&1)" && _rc=0 || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    printf '  \xe2\x9c\x85  PASS (expected non-zero, exit %d) \xe2\x80\x94 %s\n' "$_rc" "$_label"
    _TEST_PASS=$((_TEST_PASS + 1))
  else
    printf '  \xe2\x9d\x8c  FAIL (expected non-zero, got 0) \xe2\x80\x94 %s\n' "$_label"
    printf '         command: %s\n' "$(_check_quote_argv "$@")"
    [ -n "$_out" ] && printf '         output:\n%s\n' "$_out"
    _TEST_FAILURES="${_TEST_FAILURES:+${_TEST_FAILURES}
}${_label}"
    _TEST_FAIL=$((_TEST_FAIL + 1))
  fi
}

# Runs each remaining argument as a shell string via eval.
# Passes if at least <min_passed> of them exit 0.
# Usage: checkMultiple "label" <min_passed> "cmd1" ["cmd2" ...]
checkMultiple() {
  local _label="$1" _min="$2"
  shift 2
  local _passed=0 _expr _rc
  printf '\n\xf0\x9f\x94\x84 Testing (multiple) "%s"\n' "$_label"
  for _expr in "$@"; do
    [ -z "$_expr" ] && continue
    _rc=0
    eval "$_expr" > /dev/null 2>&1 || _rc=$?
    [ "$_rc" -eq 0 ] && _passed=$((_passed + 1))
  done
  if [ "$_passed" -ge "$_min" ]; then
    printf '  \xe2\x9c\x85  PASS \xe2\x80\x94 %s (%d/%d)\n' "$_label" "$_passed" "$_min"
    _TEST_PASS=$((_TEST_PASS + 1))
  else
    printf '  \xe2\x9d\x8c  FAIL \xe2\x80\x94 %s (%d/%d required)\n' "$_label" "$_passed" "$_min"
    _TEST_FAILURES="${_TEST_FAILURES:+${_TEST_FAILURES}
}${_label}"
    _TEST_FAIL=$((_TEST_FAIL + 1))
  fi
}

reportResults() {
  printf '\n'
  printf 'Results: %d passed, %d failed.\n' "$_TEST_PASS" "$_TEST_FAIL"
  if [ "$_TEST_FAIL" -gt 0 ]; then
    printf 'Failed checks:\n'
    printf '%s\n' "$_TEST_FAILURES" | while IFS= read -r _f; do
      [ -z "$_f" ] && continue
      printf '  \xe2\x80\x94 %s\n' "$_f"
    done
    if command -v _test_failure_diagnostics > /dev/null 2>&1; then
      printf '\n'
      printf '\xe2\x94\x80\xe2\x94\x80 Failure diagnostics \xe2\x94\x80\xe2\x94\x80\n'
      _test_failure_diagnostics || true
    fi
    exit 1
  fi
}

# Verbose dump for macOS install-homebrew tests that depend on bash login files.
# Non-fatal; prints to stderr. Args: [HOME] [resolved_login_file]
log_install_homebrew_shell_init_diagnostics() {
  local _home="${1:-$HOME}"
  local _login="${2:-}"
  [ -z "$_login" ] && _login="$(detect_bash_login_file)"
  {
    printf 'HOME=%s USER=%s\n' "${_home}" "${USER-}"
    printf 'detect_bash_login_file -> %s\n' "${_login}"
    local _cand
    for _cand in "${_home}/.bash_profile" "${_home}/.bash_login" "${_home}/.profile"; do
      printf '\n'
      if [ ! -e "$_cand" ]; then
        printf '%s (missing)\n' "$_cand"
        continue
      fi
      printf '%s \xe2\x80\x94 ' "$_cand"
      if [ -f "$_cand" ]; then
        printf 'regular file'
      elif [ -L "$_cand" ]; then
        printf 'symlink -> %s' "$(readlink "$_cand" 2> /dev/null || printf '?')"
      else
        printf 'exists (not a regular file)'
      fi
      printf '\n'
      command -v ls > /dev/null && ls -l "$_cand" 2> /dev/null || true
      command -v file > /dev/null && file "$_cand" 2> /dev/null || true
      printf '--- cat -v (visible non-printing chars) ---\n'
      cat -v "$_cand" 2> /dev/null || printf '(unreadable)\n'
      printf '--- od -An -tx1 (first 192 bytes) ---\n'
      head -c 192 "$_cand" 2> /dev/null | od -An -tx1 || true
    done
    printf '\n'
    printf '--- prefix activation block lines inside resolved login file (awk) ---\n'
    if [ -f "$_login" ]; then
      awk '/# >>> prefix activation \(install-homebrew\) >>>/{in=1;next} /# <<< prefix activation \(install-homebrew\) <<</{in=0} in{print}' "$_login" 2> /dev/null || true
    else
      printf '(resolved login file missing)\n'
    fi
  } >&2
}

# ── macOS block-cleanup helpers ───────────────────────────────────────────────

# Remove a named block (identified by marker) from a file, in-place.
# No-op when the file does not exist or contains no block.
# Usage: block_cleanup "<marker>" "<file>"
block_cleanup() {
  local _marker="$1" _f="$2"
  [ -f "$_f" ] || return 0
  local _bm="# >>> ${_marker} >>>" _em="# <<< ${_marker} <<<"
  local _tmp
  _tmp="$(mktemp)"
  awk -v bm="$_bm" -v em="$_em" '
    $0 == bm { skip=1; next }
    $0 == em { skip=0; next }
    !skip    { print }
  ' "$_f" > "$_tmp" && mv "$_tmp" "$_f"
  local _rc=$?
  [ "$_rc" -ne 0 ] && rm -f "$_tmp"
  return "$_rc"
}

# Remove a named block from every standard user init file in $HOME.
# Usage: block_cleanup_all "<marker>"
block_cleanup_all() {
  local _marker="$1" _f
  for _f in "${HOME}/.bash_profile" "${HOME}/.bash_login" "${HOME}/.profile" \
    "${HOME}/.bashrc" "${HOME}/.zprofile" "${HOME}/.zshenv" "${HOME}/.zshrc"; do
    block_cleanup "$_marker" "$_f"
  done
}

# Resolve the effective bash login startup file for the current user.
# Probes in order: ~/.bash_profile, ~/.bash_login, ~/.profile.
# Falls back to ~/.bash_profile if none exist.
detect_bash_login_file() {
  local _f
  for _f in "${HOME}/.bash_profile" "${HOME}/.bash_login" "${HOME}/.profile"; do
    [ -f "$_f" ] && {
      printf '%s\n' "$_f"
      return 0
    }
  done
  printf '%s\n' "${HOME}/.bash_profile"
}

# Remove the install-homebrew prefix activation block from a file, in-place.
# No-op when the file does not exist or contains no block.
shellenv_block_cleanup() {
  block_cleanup "prefix activation (install-homebrew)" "$1"
}

# ── File server helpers ───────────────────────────────────────────────────────

_FILE_SERVER_PID=""

# start_file_server <dir> <port>
# Starts 'python3 -m http.server <port>' in <dir> in the background.
# Stores the PID in _FILE_SERVER_PID. Call stop_file_server in a trap.
start_file_server() {
  local _dir="$1" _port="$2"
  python3 -m http.server "$_port" --directory "$_dir" \
    > /tmp/file-server-"$_port".log 2>&1 &
  _FILE_SERVER_PID=$!
  wait_for_port "$_port" 10
}

# stop_file_server
# Kills the background file server started by start_file_server.
stop_file_server() {
  if [ -n "$_FILE_SERVER_PID" ]; then
    kill "$_FILE_SERVER_PID" 2> /dev/null || true
    _FILE_SERVER_PID=""
  fi
}

# wait_for_port <port> [<timeout_s>]
# Blocks until 127.0.0.1:<port> accepts TCP connections.
wait_for_port() {
  local _port="$1" _timeout="${2:-10}" _limit _i
  _limit=$((_timeout * 5))
  _i=0
  while ! nc -z 127.0.0.1 "$_port" 2> /dev/null; do
    sleep 0.2
    _i=$((_i + 1))
    if [ "$_i" -ge "$_limit" ]; then
      printf '\xe2\x9b\x94 Timed out waiting for port %s\n' "$_port" >&2
      return 1
    fi
  done
}

# ── OCI registry push helper ──────────────────────────────────────────────────

# push_oci_feature <registry_host> <repo/path:tag> <tarball>
# Pushes a single-layer OCI artifact to a local registry using the v2 HTTP
# API (curl only — no docker or oras required for the push step).
#
# The layer is pushed as media type application/vnd.devcontainers.layer.v1+tgz
# with the org.opencontainers.image.title annotation set to "feature.tgz" so
# that `oras pull` materialises a .tgz file that oci__pull_feature_tgz can find.
push_oci_feature() {
  local _host="${1-}" _repo_tag="${2-}" _tgz="${3-}"
  local _repo="${_repo_tag%%:*}" _tag="${_repo_tag#*:}"
  local _base="http://${_host}/v2/${_repo}"
  local _url _http _tmp

  local _layer_hash _layer_size
  if command -v sha256sum > /dev/null 2>&1; then
    _layer_hash="$(sha256sum "$_tgz" | awk '{print $1}')"
  else
    _layer_hash="$(shasum -a 256 "$_tgz" | awk '{print $1}')"
  fi
  _layer_size="$(wc -c < "$_tgz" | tr -d '[:space:]')"
  local _layer_dig="sha256:${_layer_hash}"

  # Config blob is a minimal empty-JSON object; compute digest dynamically so
  # it always matches the actual bytes written (avoids DIGEST_INVALID on PUT).
  local _cfg_hash _cfg_size _cfg_dig
  _tmp="$(mktemp)"
  printf '{}' > "$_tmp"
  if command -v sha256sum > /dev/null 2>&1; then
    _cfg_hash="$(sha256sum "$_tmp" | awk '{print $1}')"
  else
    _cfg_hash="$(shasum -a 256 "$_tmp" | awk '{print $1}')"
  fi
  _cfg_size="$(wc -c < "$_tmp" | tr -d '[:space:]')"
  _cfg_dig="sha256:${_cfg_hash}"

  # Init a blob upload session; print the PUT URL (with digest appended) or return 1.
  _pof_upload_url() {
    local _b="${1-}" _d="${2-}" _l
    _l="$(curl -sf -X POST -D - "${_b}/blobs/uploads/" 2> /dev/null |
      grep -i '^location:' | tr -d '\r\n' |
      sed 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//')"
    [ -n "$_l" ] || return 1
    case "$_l" in
      http*) : ;;
      *) _l="http://${_host}${_l}" ;;
    esac
    case "$_l" in
      *'?'*) printf '%s&digest=%s\n' "$_l" "$_d" ;;
      *) printf '%s?digest=%s\n' "$_l" "$_d" ;;
    esac
  }

  # Upload config blob (temp file already written above).
  _url="$(_pof_upload_url "$_base" "$_cfg_dig")" || {
    rm -f "$_tmp"
    printf 'push_oci_feature: config upload init failed for %s:%s\n' "$_repo" "$_tag" >&2
    return 1
  }
  _http="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$_url" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${_tmp}")"
  rm -f "$_tmp"
  [ "$_http" = "201" ] || {
    printf 'push_oci_feature: config blob upload failed (HTTP %s) for %s:%s\n' \
      "$_http" "$_repo" "$_tag" >&2
    return 1
  }

  # Upload layer blob.
  _url="$(_pof_upload_url "$_base" "$_layer_dig")" || {
    printf 'push_oci_feature: layer upload init failed for %s:%s\n' "$_repo" "$_tag" >&2
    return 1
  }
  _http="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$_url" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${_tgz}")"
  [ "$_http" = "201" ] || {
    printf 'push_oci_feature: layer blob upload failed (HTTP %s) for %s:%s\n' \
      "$_http" "$_repo" "$_tag" >&2
    return 1
  }

  # Build and push OCI manifest via a temp file so curl sets Content-Length from file.
  local _manifest
  _manifest="$(printf '{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "%s",
    "size": %s
  },
  "layers": [
    {
      "mediaType": "application/vnd.devcontainers.layer.v1+tgz",
      "digest": "%s",
      "size": %s,
      "annotations": {
        "org.opencontainers.image.title": "feature.tgz"
      }
    }
  ]
}' "$_cfg_dig" "$_cfg_size" "$_layer_dig" "$_layer_size")"
  _tmp="$(mktemp)"
  printf '%s' "$_manifest" > "$_tmp"
  _http="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "${_base}/manifests/${_tag}" \
    -H "Content-Type: application/vnd.oci.image.manifest.v1+json" \
    --data-binary "@${_tmp}")"
  rm -f "$_tmp"
  [ "$_http" = "201" ] || {
    printf 'push_oci_feature: manifest push failed (HTTP %s) for %s:%s\n' \
      "$_http" "$_repo" "$_tag" >&2
    return 1
  }
}
