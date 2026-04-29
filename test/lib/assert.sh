#!/usr/bin/env bash
# assert.sh — Shared assertion helpers for all test/ scenarios.
#
# API-compatible with dev-container-features-test-lib:
#   check "label" <cmd> [args...]                   — passes if <cmd> exits 0
#   fail_check "label" <cmd> [args...]              — passes if <cmd> exits non-zero
#   checkMultiple "label" <min> "cmd1" ["cmd2"...]  — passes if ≥ <min> cmds exit 0
#   reportResults                                   — print summary; exit 1 if any failed
#
# macOS block-cleanup helpers:
#   block_cleanup "<marker>" "<file>"   — remove a named block from a file in-place
#   block_cleanup_all "<marker>"        — remove from all standard shell init files
#   shellenv_block_cleanup "<file>"     — remove install-homebrew shellenv block
#
# File server helpers (dist scenarios):
#   start_file_server <dir> <port>      — start python3 HTTP server in background
#   stop_file_server                    — stop the background server
#   wait_for_port <port> [<timeout_s>]  — block until TCP port is open

_TEST_PASS=0
_TEST_FAIL=0
_TEST_FAILURES=()

check() {
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '  ✅  PASS — %s\n' "$label"
    ((_TEST_PASS++)) || true
  else
    printf '  ❌  FAIL — %s (exit %d)\n' "$label" "$rc"
    [[ -n "$out" ]] && printf '         %s\n' "$out"
    _TEST_FAILURES+=("$label")
    ((_TEST_FAIL++)) || true
  fi
}

# Inverse of check: passes when <cmd> exits non-zero.
fail_check() {
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '  ✅  PASS (expected non-zero, exit %d) — %s\n' "$rc" "$label"
    ((_TEST_PASS++)) || true
  else
    printf '  ❌  FAIL (expected non-zero, got 0) — %s\n' "$label"
    [[ -n "$out" ]] && printf '         %s\n' "$out"
    _TEST_FAILURES+=("$label")
    ((_TEST_FAIL++)) || true
  fi
}

# Runs each remaining argument as a shell string via eval.
# Passes if at least <min_passed> of them exit 0.
# Usage: checkMultiple "label" <min_passed> "cmd1" ["cmd2" ...]
checkMultiple() {
  local label="$1" min_passed="$2"
  shift 2
  local passed=0 expr out rc
  printf '\n🔄 Testing (multiple) "%s"\n' "$label"
  while [[ $# -gt 0 ]]; do
    expr="$1"
    shift
    [[ -z "$expr" ]] && continue
    rc=0
    out="$(eval "$expr" 2>&1)" || rc=$?
    if [[ $rc -eq 0 ]]; then ((passed++)) || true; fi
  done
  if ((passed >= min_passed)); then
    printf '  ✅  PASS — %s (%d/%d)\n' "$label" "$passed" "$min_passed"
    ((_TEST_PASS++)) || true
  else
    printf '  ❌  FAIL — %s (%d/%d required)\n' "$label" "$passed" "$min_passed"
    _TEST_FAILURES+=("$label")
    ((_TEST_FAIL++)) || true
  fi
}

reportResults() {
  echo ""
  echo "Results: ${_TEST_PASS} passed, ${_TEST_FAIL} failed."
  if [[ ${_TEST_FAIL} -gt 0 ]]; then
    echo "Failed checks:"
    for _f in "${_TEST_FAILURES[@]}"; do
      printf '  — %s\n' "$_f"
    done
    exit 1
  fi
}

# ── macOS block-cleanup helpers ───────────────────────────────────────────────

# Remove a named block (identified by marker) from a file, in-place.
# No-op when the file does not exist or contains no block.
# Usage: block_cleanup "<marker>" "<file>"
block_cleanup() {
  local marker="$1" f="$2"
  [[ -f "$f" ]] || return 0
  local bm="# >>> ${marker} >>>" em="# <<< ${marker} <<<"
  local tmp
  tmp="$(mktemp)"
  awk -v bm="$bm" -v em="$em" '
    $0 == bm { skip=1; next }
    $0 == em { skip=0; next }
    !skip    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
  local rc=$?
  [[ $rc -ne 0 ]] && rm -f "$tmp"
  return $rc
}

# Remove a named block from every standard user init file in $HOME.
# Usage: block_cleanup_all "<marker>"
block_cleanup_all() {
  local marker="$1"
  local f
  for f in "${HOME}/.bash_profile" "${HOME}/.bash_login" "${HOME}/.profile" \
    "${HOME}/.bashrc" "${HOME}/.zprofile" "${HOME}/.zshenv" "${HOME}/.zshrc"; do
    block_cleanup "$marker" "$f"
  done
}

# Remove the install-homebrew shellenv block from a file, in-place.
# No-op when the file does not exist or contains no block.
shellenv_block_cleanup() {
  block_cleanup "brew shellenv (install-homebrew)" "$1"
}

# ── File server helpers ───────────────────────────────────────────────────────

_FILE_SERVER_PID=""

# start_file_server <dir> <port>
# Starts 'python3 -m http.server <port>' in <dir> in the background.
# Stores the PID in _FILE_SERVER_PID. Call stop_file_server in a trap.
start_file_server() {
  local _dir="$1"
  local _port="$2"
  python3 -m http.server "$_port" --directory "$_dir" \
    > /tmp/file-server-"$_port".log 2>&1 &
  _FILE_SERVER_PID=$!
  wait_for_port "$_port" 10
}

# stop_file_server
# Kills the background file server started by start_file_server.
stop_file_server() {
  if [[ -n "$_FILE_SERVER_PID" ]]; then
    kill "$_FILE_SERVER_PID" 2> /dev/null || true
    _FILE_SERVER_PID=""
  fi
}

# wait_for_port <port> [<timeout_s>]
# Blocks until 127.0.0.1:<port> accepts TCP connections.
wait_for_port() {
  local _port="$1"
  local _timeout="${2:-10}"
  # Use integer counter in tenths-of-a-second (avoids bc dependency).
  local _limit=$((_timeout * 5))
  local _i=0
  while ! bash -c "echo > /dev/tcp/127.0.0.1/${_port}" 2> /dev/null; do
    sleep 0.2
    ((_i++)) || true
    if ((_i >= _limit)); then
      echo "⛔ Timed out waiting for port ${_port}" >&2
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

  # Empty-JSON config blob — sha256('{}') is well-known.
  local _cfg_dig="sha256:44136fa355ba77b9ad7b3537ed8669bed197405c2ec3cd0a3e8e62c1e78c40b7"
  local _cfg_size=2

  # Init a blob upload session; print the PUT URL (with digest appended) or return 1.
  _pof_upload_url() {
    local _b="${1-}" _d="${2-}" _l
    _l="$(curl -sf -X POST -D - "${_b}/blobs/uploads/" 2> /dev/null |
      grep -i '^location:' | tr -d '\r\n' |
      sed 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//')"
    [[ -n "$_l" ]] || return 1
    [[ "$_l" == http* ]] || _l="http://${_host}${_l}"
    if [[ "$_l" == *'?'* ]]; then
      printf '%s&digest=%s\n' "$_l" "$_d"
    else
      printf '%s?digest=%s\n' "$_l" "$_d"
    fi
  }

  # Upload config blob via a temp file so curl determines Content-Length from file size.
  _tmp="$(mktemp)"
  printf '{}' > "$_tmp"
  _url="$(_pof_upload_url "$_base" "$_cfg_dig")" || {
    rm -f "$_tmp"
    printf 'push_oci_feature: config upload init failed for %s:%s\n' "$_repo" "$_tag" >&2
    return 1
  }
  _http="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$_url" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${_tmp}")"
  rm -f "$_tmp"
  [[ "$_http" == "201" ]] || {
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
  [[ "$_http" == "201" ]] || {
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
  [[ "$_http" == "201" ]] || {
    printf 'push_oci_feature: manifest push failed (HTTP %s) for %s:%s\n' \
      "$_http" "$_repo" "$_tag" >&2
    return 1
  }
}
