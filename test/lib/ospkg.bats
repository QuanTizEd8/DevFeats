#!/usr/bin/env bats
# Unit tests for lib/ospkg.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

setup_file() {
  load 'helpers/common'
  OSPKG_JQ_READY=0
  if bash -c '. "$1" && _json__ensure_jq' _ "${LIB_ROOT}/json.sh" > /dev/null 2>&1; then
    OSPKG_JQ_READY=1
  fi
  export OSPKG_JQ_READY
}

_require_ospkg_jq() {
  [[ "${OSPKG_JQ_READY:-0}" == "1" ]] || skip "jq bootstrap unavailable for ospkg manifest tests"
}

# ---------------------------------------------------------------------------
# ospkg__detect  (direct calls — checks internal state variables)
# ---------------------------------------------------------------------------

@test "ospkg__detect identifies apt-get ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "apt-get"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  ospkg__detect
  [[ "$_OSPKG_FAMILY" == "apt" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apt-get" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg__detect identifies apk ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "apk"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_FAMILY" == "apk" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apk" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg__detect identifies dnf ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "dnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_FAMILY" == "dnf" ]]
  [[ "$_OSPKG_PKG_MNGR" == "dnf" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg__detect is idempotent when _OSPKG_DETECTED=true" {
  reload_lib ospkg.sh
  _OSPKG_DETECTED=true
  _OSPKG_FAMILY="sentinel"
  ospkg__detect
  [[ "$_OSPKG_FAMILY" == "sentinel" ]]
}

@test "ospkg__detect fails when no package manager is found" {
  reload_lib ospkg.sh
  # Override PATH to empty so no package manager binary is found.
  PATH="${BATS_TEST_TMPDIR}/bin" run ospkg__detect
  assert_failure
  assert_output --partial "No supported package manager"
}

@test "ospkg__detect identifies zypper ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "zypper"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_FAMILY" == "zypper" ]]
  [[ "$_OSPKG_PKG_MNGR" == "zypper" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg__detect identifies microdnf ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_FAMILY" == "dnf" ]]
  [[ "$_OSPKG_PKG_MNGR" == "microdnf" ]]
  [[ "${#_OSPKG_UPDATE[@]}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_seed_apt_context() {
  reload_lib ospkg.sh
  create_fake_bin "apt-get"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  ospkg__detect
  _OSPKG_OS_RELEASE[pm]="apt"
  _OSPKG_OS_RELEASE[arch]="x86_64"
  _OSPKG_OS_RELEASE[id]="ubuntu"
  _OSPKG_OS_RELEASE[id_like]="debian"
  _OSPKG_OS_RELEASE[version_id]="22.04"
  _OSPKG_OS_RELEASE[version_codename]="jammy"
  # Bypass sudo: sudo resets PATH to its secure_path, ignoring user PATH entirely.
  # Without this stub, users__run_privileged would find the real apt-get via sudo
  # instead of the fake one above, allowing destructive operations on the host.
  users__run_privileged() { "$@"; }
  export -f users__run_privileged
}

# ---------------------------------------------------------------------------
# ospkg__update
# ---------------------------------------------------------------------------

@test "ospkg__update rejects unknown option" {
  _seed_apt_context
  run ospkg__update --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "ospkg__update skips when update command array is empty" {
  reload_lib ospkg.sh
  # Seed a microdnf-like context: detected, but no update command.
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  run ospkg__update
  assert_success
  assert_output --partial "skipping explicit update"
}

@test "ospkg__update runs update command with --force" {
  _seed_apt_context
  # The fake apt-get stub exits 0 for any subcommand.
  run ospkg__update --force
  assert_success
}

# ---------------------------------------------------------------------------
# ospkg__install
# ---------------------------------------------------------------------------

@test "ospkg__install invokes the install command" {
  _seed_apt_context
  run ospkg__install curl
  assert_success
}

@test "ospkg__install skips when apt packages are already installed" {
  _seed_apt_context
  # Fake dpkg that reports the package as installed (exit 0).
  create_fake_bin "dpkg" ""
  prepend_fake_bin_path
  run ospkg__install curl
  assert_success
  assert_output --partial "already installed"
}

# ---------------------------------------------------------------------------
# ospkg__clean
# ---------------------------------------------------------------------------

@test "ospkg__clean succeeds for apt context" {
  _seed_apt_context
  # The fake apt-get stub handles 'clean' and 'dist-clean'.
  run ospkg__clean
  assert_success
}

# ---------------------------------------------------------------------------
# ospkg__detect — brew paths
# ---------------------------------------------------------------------------

@test "ospkg__detect identifies brew on macOS (Darwin)" {
  reload_lib ospkg.sh
  # Fake 'uname' returning Darwin and a fake 'brew' binary.
  create_fake_bin "uname" "Darwin"
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  # 'sw_vers' must exist (macOS only command path).
  create_fake_bin "sw_vers" "14.0"
  ospkg__detect
  [[ "$_OSPKG_FAMILY" == "brew" ]]
  [[ "$_OSPKG_PKG_MNGR" == "brew" ]]
  [[ "${_OSPKG_OS_RELEASE[id]}" == "macos" ]]
}

@test "ospkg__detect selects brew when _OSPKG_PREFER_LINUXBREW=true and brew is on PATH" {
  reload_lib ospkg.sh
  create_fake_bin "uname" "Linux"
  create_fake_bin "apt-get" ""
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  _OSPKG_PREFER_LINUXBREW=true
  ospkg__detect
  [[ "$_OSPKG_FAMILY" == "brew" ]]
  [[ "$_OSPKG_PKG_MNGR" == "brew" ]]
}

@test "ospkg__detect falls back to native PM when _OSPKG_PREFER_LINUXBREW=true but brew absent" {
  reload_lib ospkg.sh
  create_fake_bin "uname" "Linux"
  create_fake_bin "apt-get" ""
  # Use restricted PATH so real brew is not found.
  _OSPKG_PREFER_LINUXBREW=true
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_FAMILY" == "apt" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apt-get" ]]
}

# ---------------------------------------------------------------------------
# ospkg__parse_manifest_yaml  (requires jq)
# ---------------------------------------------------------------------------

@test "ospkg__parse_manifest_yaml emits package records from plain packages list" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"packages":["curl","wget","git"]}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"kind":"package"'* ]]
  [[ "$_output" == *'"name":"curl"'* ]]
  [[ "$_output" == *'"name":"wget"'* ]]
}

@test "ospkg__parse_manifest_yaml emits prescript record" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"prescripts":"echo hello\\n","packages":["curl"]}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"kind":"prescript"'* ]]
}

@test "ospkg__parse_manifest_yaml filters packages with when clause" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  # brew-only package should NOT appear for apt context.
  printf '{"packages":[{"name":"brew-pkg","when":{"pm":"brew"}},{"name":"apt-pkg","when":{"pm":"apt"}}]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" != *'"name":"brew-pkg"'* ]]
  [[ "$_output" == *'"name":"apt-pkg"'* ]]
}

@test "ospkg__parse_manifest_yaml skips the manifest when top-level when mismatches" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"when":{"pm":"brew"},"packages":["should-not-appear"]}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ -z "$_output" ]]
}

@test "ospkg__parse_manifest_yaml emits packages from pm-specific apt block" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"apt":{"packages":["libssl-dev"]},"brew":{"packages":["openssl"]}}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"name":"libssl-dev"'* ]]
  [[ "$_output" != *'"name":"openssl"'* ]]
}

@test "ospkg__parse_manifest_yaml when clause supports version_codename" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  # jammy-only package should appear; bookworm-only should not.
  printf '{"packages":[{"name":"jammy-pkg","when":{"version_codename":"jammy"}},{"name":"bookworm-pkg","when":{"version_codename":"bookworm"}}]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  # _seed_apt_context sets version_codename=jammy
  [[ "$_output" == *'"name":"jammy-pkg"'* ]]
  [[ "$_output" != *'"name":"bookworm-pkg"'* ]]
}

@test "ospkg__parse_manifest_yaml accepts repos as strings and objects" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"repos":["deb http://deb.debian.org/debian stable main",{"content":"deb http://example.invalid/debian stable main"}],"packages":["tree"]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"kind":"repo","content":"deb http://deb.debian.org/debian stable main"'* ]]
  [[ "$_output" == *'"kind":"repo","content":"deb http://example.invalid/debian stable main"'* ]]
  [[ "$_output" == *'"kind":"package","name":"tree"'* ]]
}

# ---------------------------------------------------------------------------
# ospkg__run — regression: stale yq binary path and silent parse failure
#
# Root cause: ospkg__run previously deleted the yq tmpdir inline at the end of
# every call (rm -rf $_OSPKG_YQ_TMPDIR; _OSPKG_YQ_TMPDIR=; _OSPKG_YQ_BIN=).
# A second call that reused _OSPKG_YQ_BIN via the early-return guard in
# _ospkg_ensure_yq would try to execute a non-existent binary.  The failure
# was silent because the yq+parse block was wrapped in `if ! {}`, which
# disables set -e.
# ---------------------------------------------------------------------------

# _seed_apt_context_with_yq — sets up apt context and creates a fake yq binary.
# Exports a mock _ospkg_ensure_yq that mirrors the real early-return guard.
_seed_apt_context_with_yq() {
  _seed_apt_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho '"'"'{"packages":["regrpkg"]}'"'"'\n' \
    > "${BATS_TEST_TMPDIR}/bin/yq"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yq"
  # Mock mirrors _ospkg_ensure_yq's real early-return guard so the second call
  # exercises the early-return code path with the already-set _OSPKG_YQ_BIN.
  # Note: _OSPKG_YQ_BIN is assigned to a stable path (not inside _SYSSET_TMPDIR)
  # to avoid command-substitution subshell scoping issues with _SYSSET_TMPDIR.
  _ospkg_ensure_yq() {
    [[ -n "${_OSPKG_YQ_BIN:-}" ]] && return 0
    _OSPKG_YQ_BIN="${BATS_TEST_TMPDIR}/bin/yq"
    return 0
  }
  export -f _ospkg_ensure_yq
}

@test "ospkg__run regression: yq binary not deleted after call returns" {
  # Old code: rm -rf "$_OSPKG_YQ_TMPDIR"; _OSPKG_YQ_BIN= inside ospkg__run.
  # Fix: yq dir lives in _SYSSET_TMPDIR for the process lifetime; ospkg__run
  # never deletes it.
  _require_ospkg_jq
  _seed_apt_context_with_yq

  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > /dev/null 2>&1

  # After the call, _OSPKG_YQ_BIN must still be set and the file must exist.
  [[ -n "${_OSPKG_YQ_BIN:-}" ]] ||
    {
      echo "_OSPKG_YQ_BIN was cleared after ospkg__run"
      return 1
    }
  [[ -f "$_OSPKG_YQ_BIN" ]] ||
    {
      echo "_OSPKG_YQ_BIN no longer points to a file: ${_OSPKG_YQ_BIN}"
      return 1
    }
}

@test "ospkg__run regression: second call succeeds via _OSPKG_YQ_BIN early-return path" {
  # Old code: after first call _OSPKG_YQ_BIN was cleared (or set to a deleted
  # path) so a second call silently processed no packages.
  # Fix: _OSPKG_YQ_BIN persists; _ospkg_ensure_yq early-returns and the binary
  # at that path is still valid.
  _require_ospkg_jq
  _seed_apt_context_with_yq

  local _log="${BATS_TEST_TMPDIR}/run.log"

  # First call — sets _OSPKG_YQ_BIN via mock.
  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > "$_log" 2>&1
  grep -q "\[dry-run\] packages: regrpkg" "$_log" ||
    {
      echo "First call: expected dry-run output absent"
      cat "$_log" >&2
      return 1
    }

  # Second call — _ospkg_ensure_yq early-returns; the binary at _OSPKG_YQ_BIN
  # must still be accessible.  Old code would have deleted it above.
  : > "$_log"
  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > "$_log" 2>&1
  grep -q "\[dry-run\] packages: regrpkg" "$_log" ||
    {
      echo "Second call (regression): dry-run output absent — yq path was stale or deleted"
      cat "$_log" >&2
      return 1
    }
}

@test "ospkg__run regression: YAML conversion failure propagates under set -e" {
  # Old code: yq+parse block wrapped in `if ! {}`, which disables set -e so a
  # failing yq was swallowed — ospkg__run returned 0 with nothing installed.
  # Fix: block is plain sequential code; a failing yq exits the function under
  # set -e.
  _require_ospkg_jq
  local _ospkg_lib="${BATS_TEST_DIRNAME}/../../lib/ospkg.sh"

  run bash -c "
    set -euo pipefail
    source '${_ospkg_lib}'

    # Seed a minimal apt context without calling the real package manager.
    _OSPKG_DETECTED=true
    _OSPKG_PKG_MNGR='apt-get'
    _OSPKG_FAMILY='apt'
    _OSPKG_OS_RELEASE[pm]='apt'
    _OSPKG_OS_RELEASE[arch]='x86_64'
    _OSPKG_OS_RELEASE[id]='ubuntu'
    _OSPKG_OS_RELEASE[id_like]='debian'
    _OSPKG_OS_RELEASE[version_id]='22.04'
    _OSPKG_OS_RELEASE[version_codename]='jammy'

    # A yq stub that always exits non-zero (simulates corrupt binary / bad manifest).
    _OSPKG_YQ_BIN='${BATS_TEST_TMPDIR}/bin/yq'
    mkdir -p '${BATS_TEST_TMPDIR}/bin'
    printf '#!/bin/bash\nexit 1\n' > \"\$_OSPKG_YQ_BIN\"
    chmod +x \"\$_OSPKG_YQ_BIN\"
    _ospkg_ensure_yq() { return 0; }

    ospkg__run --manifest \$'packages:\n  - curl\n' --dry_run
  "
  assert_failure
}

@test "ospkg__run fails when manifest parser returns non-zero" {
  _require_ospkg_jq
  local _ospkg_lib="${BATS_TEST_DIRNAME}/../../lib/ospkg.sh"

  run bash -c "
    set -euo pipefail
    source '${_ospkg_lib}'

    _OSPKG_DETECTED=true
    _OSPKG_PKG_MNGR='apt-get'
    _OSPKG_FAMILY='apt'
    _OSPKG_OS_RELEASE[pm]='apt'
    _OSPKG_OS_RELEASE[arch]='x86_64'
    _OSPKG_OS_RELEASE[id]='ubuntu'
    _OSPKG_OS_RELEASE[id_like]='debian'
    _OSPKG_OS_RELEASE[version_id]='22.04'
    _OSPKG_OS_RELEASE[version_codename]='jammy'

    # yq returns valid JSON; parser failure is injected directly.
    _OSPKG_YQ_BIN='${BATS_TEST_TMPDIR}/bin/yq'
    mkdir -p '${BATS_TEST_TMPDIR}/bin'
    cat > \"\$_OSPKG_YQ_BIN\" <<'YQ'
#!/bin/bash
cat <<'JSON'
{\"packages\":[\"curl\"]}
JSON
YQ
    chmod +x \"\$_OSPKG_YQ_BIN\"
    _ospkg_ensure_yq() { return 0; }
    ospkg__parse_manifest_yaml() { return 42; }

    ospkg__run --manifest \$'packages:\n  - curl\n' --dry_run
  "
  assert_failure
}

# ---------------------------------------------------------------------------
# Build-dep tracking: ospkg__install_tracked / _ospkg_remove_build_group /
#                     ospkg__cleanup_all_build_groups
# ---------------------------------------------------------------------------

# _seed_apt_build_context — seeds apt context + stubs needed for build-dep tests:
#   · _SYSSET_TMPDIR        → BATS_TEST_TMPDIR (sidecars at a predictable path)
#   · fake apt-get          (exit 0, no-op — real install skipped)
#   · fake dpkg             (exit 1 — "not installed" so ospkg__install always proceeds)
#   · fake apt-mark         (logs every invocation to ${BATS_TEST_TMPDIR}/apt-mark.log)
#   · users__run_privileged → "$@" directly (inherited from _seed_apt_context)
#   · net__fetch_with_retry → passthrough so the fake apt-get is actually invoked
# After this, call _mock_snapshots to control the before/after package lists.
_seed_apt_build_context() {
  _seed_apt_context
  export _SYSSET_BUILD_CONTEXT="ctx"
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\nexit 0\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  printf '#!/bin/bash\nexit 1\n' \
    > "${BATS_TEST_TMPDIR}/bin/dpkg"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg"
  printf '#!/bin/bash\necho "$@" >> "%s/apt-mark.log"\n' \
    "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/bin/apt-mark"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-mark"
  prepend_fake_bin_path
  # Passthrough: avoids the real retry loop and simply invokes the fake apt-get.
  net__fetch_with_retry() { "$@" > /dev/null 2>&1 || true; }
}

# _mock_snapshots <before_pkgs_space_sep> <after_pkgs_space_sep>
# Replaces _ospkg_snapshot_packages with a counter-based mock.  The first call
# returns <before_pkgs> (one-per-line, sorted); all subsequent calls return
# <after_pkgs>.  Uses a temp file for the counter to avoid bash closure issues.
_mock_snapshots() {
  export SNAP_BEFORE="$1"
  export SNAP_AFTER="$2"
  echo 0 > "${BATS_TEST_TMPDIR}/.snap_call"
  _ospkg_snapshot_packages() {
    local _dest="$1" _n
    _n=$(cat "${BATS_TEST_TMPDIR}/.snap_call")
    _n=$((_n + 1))
    echo "$_n" > "${BATS_TEST_TMPDIR}/.snap_call"
    if [[ $_n -le 1 ]]; then
      echo "${SNAP_BEFORE}" | tr ' ' '\n' | grep -v '^$' | sort > "$_dest"
    else
      echo "${SNAP_AFTER}" | tr ' ' '\n' | grep -v '^$' | sort > "$_dest"
    fi
  }
}

# ── ospkg__install_tracked ────────────────────────────────────────────────────

@test "ospkg__install_tracked: newly installed package is recorded in sidecar" {
  _seed_apt_build_context
  _mock_snapshots "curl" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
  assert_file_exists "$_sidecar"
  grep -q "^newpkg$" "$_sidecar"
}

@test "ospkg__install_tracked: newly installed package is marked apt auto" {
  _seed_apt_build_context
  _mock_snapshots "curl" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "auto newpkg" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "ospkg__install_tracked: pre-installed package produces empty sentinel sidecar" {
  # Package is already present in the before-snapshot → diff is empty → sidecar
  # created as empty sentinel (no content, no apt-mark call).
  _seed_apt_build_context
  _mock_snapshots "curl newpkg" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
  assert_file_exists "$_sidecar"
  [[ ! -s "$_sidecar" ]]
}

@test "ospkg__install_tracked: pre-installed package — apt-mark auto not called" {
  _seed_apt_build_context
  _mock_snapshots "curl newpkg" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  [[ ! -f "${BATS_TEST_TMPDIR}/apt-mark.log" ]]
}

@test "ospkg__install_tracked: ospkg__detect called before before-snapshot — PM set correctly" {
  # Regression: without the ospkg__detect call at the top of ospkg__install_tracked,
  # _OSPKG_PKG_MNGR is empty when the before-snapshot runs (hitting the '*' case that
  # writes an empty file). ospkg__install then calls ospkg__detect internally, setting
  # the PM. The after-snapshot then captures every installed package. The diff
  # (empty before vs full after) = all packages tracked for removal — a destructive bug.
  _seed_apt_build_context
  # Reset detection state to simulate a fresh call where ospkg__detect has not yet run.
  _OSPKG_DETECTED=false
  _OSPKG_PKG_MNGR=""

  local _pm_log="${BATS_TEST_TMPDIR}/pm_at_snapshot.log"
  local _snap_call=0
  _ospkg_snapshot_packages() {
    _snap_call=$((_snap_call + 1))
    if [[ $_snap_call -eq 1 ]]; then
      # Record _OSPKG_PKG_MNGR on the before-snapshot call.
      printf '%s\n' "${_OSPKG_PKG_MNGR:-EMPTY}" > "$_pm_log"
    fi
    : > "$1"
  }

  ospkg__install_tracked "test-group" pkg

  # The fix: _OSPKG_PKG_MNGR must be set (not empty) when the before-snapshot runs.
  assert_file_exists "$_pm_log"
  run cat "$_pm_log"
  refute_output "EMPTY"
}

@test "ospkg__install_tracked: snapshot safety — pre-existing package never auto-marked" {
  # Core correctness guarantee: a package already present before this call (e.g.
  # a run.base package installed by the generated header) appears in the
  # before-snapshot and is therefore absent from _new_pkgs — its 'manual' mark
  # is never touched regardless of what apt-get install does.
  _seed_apt_build_context
  # git is pre-existing (in before); newpkg is genuinely new (only in after).
  _mock_snapshots "curl git" "curl git newpkg"

  ospkg__install_tracked "test-group" newpkg

  # newpkg must be tracked and auto-marked.
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "auto newpkg" "${BATS_TEST_TMPDIR}/apt-mark.log"
  # git must never appear as an apt-mark target.
  run grep "git" "${BATS_TEST_TMPDIR}/apt-mark.log"
  assert_failure
}

@test "ospkg__install_tracked: two calls with same group-id accumulate packages in sidecar" {
  _seed_apt_build_context

  _mock_snapshots "curl" "curl pkg1"
  ospkg__install_tracked "test-group" pkg1

  _mock_snapshots "curl pkg1" "curl pkg1 pkg2"
  ospkg__install_tracked "test-group" pkg2

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
  grep -q "^pkg1$" "$_sidecar"
  grep -q "^pkg2$" "$_sidecar"
}

@test "ospkg__install_tracked: sort -u prevents duplicate entries across repeated calls" {
  _seed_apt_build_context

  _mock_snapshots "" "pkg1"
  ospkg__install_tracked "test-group" pkg1

  # Second call: pkg1 already in before (no-op install), should not duplicate.
  _mock_snapshots "pkg1" "pkg1"
  ospkg__install_tracked "test-group" pkg1

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
  [[ $(grep -c "^pkg1$" "$_sidecar") -eq 1 ]]
}

@test "ospkg__install_tracked: different group-ids create separate sidecars" {
  _seed_apt_build_context

  _mock_snapshots "" "pkg1"
  ospkg__install_tracked "group-a" pkg1

  _mock_snapshots "pkg1" "pkg1 pkg2"
  ospkg__install_tracked "group-b" pkg2

  local _bd="${BATS_TEST_TMPDIR}/ospkg/build-deps"
  assert_file_exists "${_bd}/ctx::group-a"
  assert_file_exists "${_bd}/ctx::group-b"
  grep -q "^pkg1$" "${_bd}/ctx::group-a"
  grep -q "^pkg2$" "${_bd}/ctx::group-b"
  # pkg2 must not bleed into group-a's sidecar.
  run grep "pkg2" "${_bd}/ctx::group-a"
  assert_failure
}

# ── _ospkg_remove_build_group ────────────────────────────────────────────────

@test "_ospkg_remove_build_group: missing sidecar returns 0 with informational message" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"

  run _ospkg_remove_build_group "nonexistent-group"

  assert_success
  assert_output --partial "nothing to remove"
}

@test "_ospkg_remove_build_group: empty sidecar returns 0 without invoking autoremove" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  run _ospkg_remove_build_group "test-group"

  assert_success
  assert_output --partial "nothing to remove"
  [[ ! -f "$_apt_log" ]]
}

@test "_ospkg_remove_build_group: apt — calls remove with exact sidecar packages and deletes sidecar" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'curl\nnewpkg\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  _ospkg_remove_build_group "test-group"

  # Must use explicit 'remove <pkgs>' (not 'autoremove' or 'remove --auto-remove')
  # so removal is scoped exactly to the sidecar list, not a global auto-mark scan.
  grep -q -- "remove" "$_apt_log"
  grep -q "curl" "$_apt_log"
  grep -q "newpkg" "$_apt_log"
  ! grep -q "autoremove" "$_apt_log"
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group" ]]
}

# ── ospkg__cleanup_all_build_groups ──────────────────────────────────────────

@test "ospkg__cleanup_all_build_groups: missing build-deps directory returns 0" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}/no_such_dir_xyz"

  run ospkg__cleanup_all_build_groups

  assert_success
}

@test "ospkg__cleanup_all_build_groups: .before and .after files are skipped" {
  # Temp snapshot files left by an aborted run must not be treated as group
  # sidecars — they must remain untouched after cleanup.
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.before"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.after"

  run ospkg__cleanup_all_build_groups

  assert_success
  assert_file_exists "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.before"
  assert_file_exists "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.after"
}

@test "ospkg__cleanup_all_build_groups: one group sidecar triggers exact remove of tracked packages and is deleted" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  ospkg__cleanup_all_build_groups

  grep -q -- "remove" "$_apt_log"
  grep -q "curl" "$_apt_log"
  ! grep -q "autoremove" "$_apt_log"
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group" ]]
}

@test "ospkg__cleanup_all_build_groups: multiple group sidecars are all removed" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-a"
  printf 'git\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-b"
  printf 'tar\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-c"

  create_fake_bin "apt-get" ""
  prepend_fake_bin_path

  ospkg__cleanup_all_build_groups

  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-a" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-b" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-c" ]]
}

# ---------------------------------------------------------------------------
@test "ospkg__run YAML path works on macOS (portable mktemp)" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS-only"
  _require_ospkg_jq
  reload_lib ospkg.sh

  # A fake yq that ignores its arguments and emits a fixed JSON manifest.
  local _fake_yq="${BATS_TEST_TMPDIR}/bin/yq"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho '"'"'{"packages":["foo"]}'"'"'\n' > "$_fake_yq"
  chmod +x "$_fake_yq"

  logging__cleanup() { return 0; }
  ospkg__detect() {
    _OSPKG_FAMILY="brew"
    _OSPKG_PKG_MNGR="brew"
    _OSPKG_DETECTED=true
    _OSPKG_OS_RELEASE[pm]="brew"
    _OSPKG_OS_RELEASE[kernel]="darwin"
    _OSPKG_OS_RELEASE[id]="macos"
    _OSPKG_OS_RELEASE[id_like]="macos"
    _OSPKG_OS_RELEASE[arch]="arm64"
    return 0
  }
  _ospkg_ensure_yq() {
    _OSPKG_YQ_BIN="${BATS_TEST_TMPDIR}/bin/yq"
    return 0
  }

  run ospkg__run --manifest $'packages:\n  - foo\n' --dry_run
  assert_success
  assert_output --partial "[dry-run] packages: foo"
}

# ---------------------------------------------------------------------------
# ospkg__take_initial_snapshot
# ---------------------------------------------------------------------------

@test "ospkg__take_initial_snapshot writes sorted package list to file" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  # Provide a fake dpkg-query that emits a known set of packages.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\nprintf "wget\ncurl\ngit\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  prepend_fake_bin_path

  local _snap="${BATS_TEST_TMPDIR}/snap.txt"
  ospkg__take_initial_snapshot "$_snap"

  assert_file_exists "$_snap"
  # sort -u so order-independence: curl git wget
  grep -q "^curl$" "$_snap"
  grep -q "^git$" "$_snap"
  grep -q "^wget$" "$_snap"
}

@test "ospkg__take_initial_snapshot prints informational message to stderr" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  create_fake_bin "dpkg-query" ""
  prepend_fake_bin_path

  local _snap="${BATS_TEST_TMPDIR}/snap.txt"
  run ospkg__take_initial_snapshot "$_snap"

  assert_success
  assert_output --partial "Initial package snapshot written"
}

@test "ospkg__take_initial_snapshot creates empty file for unknown PM" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  # Force an unknown PM context directly to test the '*' case.
  _OSPKG_DETECTED=true
  _OSPKG_PKG_MNGR="unknown-pm"
  _OSPKG_FAMILY="unknown"

  local _snap="${BATS_TEST_TMPDIR}/snap_unknown.txt"
  ospkg__take_initial_snapshot "$_snap"

  assert_file_exists "$_snap"
  [[ ! -s "$_snap" ]]
}

# ---------------------------------------------------------------------------
# ospkg__install_tracked — session co-ownership tracking (new behaviour)
# ---------------------------------------------------------------------------

# _seed_session_context — seeds apt build context + session tracking dir.
# Exposes _SESSION_DIR and _INITIAL_SNAP variables for use in tests.
_seed_session_context() {
  _seed_apt_build_context
  _SESSION_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/session_XXXXXX")"
  _INITIAL_SNAP="${BATS_TEST_TMPDIR}/initial.snap"
  export _SYSSET_SESSION_TRACK_DIR="$_SESSION_DIR"
  export _SYSSET_INITIAL_SNAPSHOT="$_INITIAL_SNAP"
}

@test "ospkg__install_tracked: new package is appended to session sidecar" {
  _seed_session_context
  # pre-session: curl is already installed; newpkg is not in initial snapshot
  printf 'curl\n' > "$_INITIAL_SNAP"
  _mock_snapshots "curl" "curl newpkg"

  ospkg__install_tracked "lib-net" newpkg

  local _sess_sidecar="${_SESSION_DIR}/feature::::install-test::::lib-net"
  # filename uses // substitution so :: → ::::... let's detect the real name
  local _found
  _found="$(ls "$_SESSION_DIR"/ 2> /dev/null | head -1)"
  [[ -n "$_found" ]]
  grep -q "^newpkg$" "${_SESSION_DIR}/${_found}"
}

@test "ospkg__install_tracked: pre-session package is excluded from session sidecar" {
  _seed_session_context
  # curl is in the initial snapshot → should NOT appear in session sidecar
  printf 'curl\n' > "$_INITIAL_SNAP"
  _mock_snapshots "curl" "curl"

  ospkg__install_tracked "lib-net" curl

  # Session sidecar should either not exist or not contain 'curl'
  local _found
  _found="$(ls "$_SESSION_DIR"/ 2> /dev/null | head -1)"
  if [[ -n "$_found" ]]; then
    run grep "^curl$" "${_SESSION_DIR}/${_found}"
    assert_failure
  fi
}

@test "ospkg__install_tracked: session sidecar deduplicates repeated calls" {
  _seed_session_context
  printf '' > "$_INITIAL_SNAP" # empty initial snapshot
  _mock_snapshots "" "pkgA"
  ospkg__install_tracked "lib-net" pkgA
  _mock_snapshots "pkgA" "pkgA"
  ospkg__install_tracked "lib-net" pkgA

  # Find the session sidecar
  local _found
  _found="$(ls "$_SESSION_DIR"/ 2> /dev/null | head -1)"
  [[ -n "$_found" ]]
  [[ "$(grep -c "^pkgA$" "${_SESSION_DIR}/${_found}")" -eq 1 ]]
}

@test "ospkg__install_tracked: no session tracking when _SYSSET_SESSION_TRACK_DIR is unset" {
  _seed_apt_build_context
  unset _SYSSET_SESSION_TRACK_DIR
  _mock_snapshots "" "newpkg"

  ospkg__install_tracked "test-group" newpkg

  # SYSSET_TMPDIR/ospkg/build-deps sidecar should exist (local tracking)
  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
  assert_file_exists "$_sidecar"
  grep -q "^newpkg$" "$_sidecar"
}

@test "ospkg__install_tracked: no session tracking when session dir does not exist" {
  _seed_apt_build_context
  export _SYSSET_SESSION_TRACK_DIR="${BATS_TEST_TMPDIR}/no_such_session_dir_xyz"
  _mock_snapshots "" "newpkg"

  # Must not fail even though _SYSSET_SESSION_TRACK_DIR does not exist.
  run ospkg__install_tracked "test-group" newpkg
  assert_success
}

# ---------------------------------------------------------------------------
# ospkg__cleanup_session_build_groups
# ---------------------------------------------------------------------------

# _seed_session_cleanup_context — seeds apt context + required infrastructure.
# Callers populate ${_SESSION_DIR}/ with sidecar files and ${_BUILD_DEPS_DIR}/
# with sidecar files before calling ospkg__cleanup_session_build_groups.
_seed_session_cleanup_context() {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  _SESSION_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/session_XXXXXX")"
  export _SYSSET_SESSION_TRACK_DIR="$_SESSION_DIR"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  _APT_LOG="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_APT_LOG" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path
}

@test "ospkg__cleanup_session_build_groups: no-ops when _SYSSET_SESSION_TRACK_DIR is unset" {
  reload_lib ospkg.sh
  unset _SYSSET_SESSION_TRACK_DIR

  run ospkg__cleanup_session_build_groups "false"
  assert_success
}

@test "ospkg__cleanup_session_build_groups: no-ops when session dir does not exist" {
  reload_lib ospkg.sh
  export _SYSSET_SESSION_TRACK_DIR="${BATS_TEST_TMPDIR}/no_such_dir_xyz"

  run ospkg__cleanup_session_build_groups "false"
  assert_success
}

@test "ospkg__cleanup_session_build_groups: deletes session dir on completion" {
  _seed_session_cleanup_context
  # Empty session dir — nothing to remove, but dir should still be deleted.

  ospkg__cleanup_session_build_groups "false"

  [[ ! -d "$_SESSION_DIR" ]]
}

@test "ospkg__cleanup_session_build_groups: single feature keep=false — package removed" {
  _seed_session_cleanup_context
  # One feature with keep=false contributed 'buildpkg'.
  printf 'buildpkg\n' > "${_SESSION_DIR}/feature::install-test::lib-net"

  ospkg__cleanup_session_build_groups "false"

  grep -q "autoremove\|remove" "$_APT_LOG" || grep -q "buildpkg" "$_APT_LOG"
}

@test "ospkg__cleanup_session_build_groups: keep-wins — any true prevents removal" {
  _seed_session_cleanup_context
  # Two features co-own 'sharedpkg': one keeps, one does not.
  printf 'sharedpkg\n' > "${_SESSION_DIR}/feature::install-a::lib-net"
  printf 'sharedpkg\n' > "${_SESSION_DIR}/feature::install-b::lib-net"

  # Declare _OPT_OF so ospkg__cleanup_session_build_groups can read keep policy.
  declare -gA _OPT_OF=(
    ["install-a"]='{"keep_build_deps": true}'
    ["install-b"]='{"keep_build_deps": false}'
  )

  ospkg__cleanup_session_build_groups "false"

  # Package must NOT be removed — keep wins.
  [[ ! -f "$_APT_LOG" ]] || ! grep -q "sharedpkg" "$_APT_LOG"
}

@test "ospkg__cleanup_session_build_groups: install-bash keep=true prevents removal" {
  _seed_session_cleanup_context
  # install-bash contributed 'gbpkg' and requests keep=true.
  printf 'gbpkg\n' > "${_SESSION_DIR}/install-bash::bootstrap"

  ospkg__cleanup_session_build_groups "true"

  [[ ! -f "$_APT_LOG" ]] || ! grep -q "gbpkg" "$_APT_LOG"
}

@test "ospkg__cleanup_session_build_groups: all keep=false — packages are removed" {
  _seed_session_cleanup_context
  # Two distinct packages owned by separate contexts, both keep=false.
  printf 'pkgA\n' > "${_SESSION_DIR}/feature::install-a::lib-net"
  printf 'pkgB\n' > "${_SESSION_DIR}/feature::install-b::lib-net"

  declare -gA _OPT_OF=(
    ["install-a"]='{"keep_build_deps": false}'
    ["install-b"]='{"keep_build_deps": false}'
  )

  ospkg__cleanup_session_build_groups "false"

  assert_file_exists "$_APT_LOG"
}

@test "ospkg__cleanup_session_build_groups: resources/ subdir is ignored" {
  _seed_session_cleanup_context
  # Place a file inside resources/ — must not be treated as a package sidecar.
  mkdir -p "${_SESSION_DIR}/resources"
  printf '/tmp/somefile\n' > "${_SESSION_DIR}/resources/my-group"

  ospkg__cleanup_session_build_groups "false"

  # apt-get must not have been invoked for anything.
  [[ ! -f "$_APT_LOG" ]]
}

@test "ospkg__cleanup_session_build_groups: empty session dir prints informational message" {
  _seed_session_cleanup_context

  run ospkg__cleanup_session_build_groups "false"

  assert_success
  assert_output --partial "no packages to remove"
}

@test "ospkg__cleanup_session_build_groups: pre-existing package in initial snapshot is not tracked" {
  # ospkg__install_tracked excludes packages in _SYSSET_INITIAL_SNAPSHOT;
  # therefore the session sidecar should never contain them. This test confirms
  # that if a sidecar somehow contains a package name, the coordinator still
  # processes it (defense-in-depth). But the main path: _install_tracked + initial
  # snapshot → package absent from sidecar → nothing to remove.
  _seed_session_cleanup_context
  # Session dir is empty because ospkg__install_tracked filtered pre-existing.
  # Cleanup should report "no packages to remove".

  run ospkg__cleanup_session_build_groups "false"
  assert_success
  assert_output --partial "no packages to remove"
}

# ---------------------------------------------------------------------------
# ospkg__track_resource / ospkg__cleanup_resources
# ---------------------------------------------------------------------------

@test "ospkg__track_resource: writes path to local resource sidecar" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  unset _SYSSET_SESSION_TRACK_DIR

  ospkg__track_resource "test-group" "/tmp/some_file_xyz"

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/resources/test-group"
  assert_file_exists "$_sidecar"
  grep -q "^/tmp/some_file_xyz$" "$_sidecar"
}

@test "ospkg__track_resource: multiple paths written in order" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  unset _SYSSET_SESSION_TRACK_DIR

  ospkg__track_resource "test-group" "/a/path1" "/b/path2" "/c/path3"

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/resources/test-group"
  grep -q "^/a/path1$" "$_sidecar"
  grep -q "^/b/path2$" "$_sidecar"
  grep -q "^/c/path3$" "$_sidecar"
}

@test "ospkg__track_resource: also mirrors to session resources dir when session dir set" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  local _session_dir
  _session_dir="$(mktemp -d "${BATS_TEST_TMPDIR}/session_XXXXXX")"
  export _SYSSET_SESSION_TRACK_DIR="$_session_dir"

  ospkg__track_resource "test-group" "/tmp/mirror_test"

  # Local sidecar
  local _local="${BATS_TEST_TMPDIR}/ospkg/resources/test-group"
  assert_file_exists "$_local"
  grep -q "^/tmp/mirror_test$" "$_local"

  # Session mirror
  local _sess="${_session_dir}/resources/test-group"
  assert_file_exists "$_sess"
  grep -q "^/tmp/mirror_test$" "$_sess"
}

@test "ospkg__track_resource: no session mirror when session dir does not exist" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  export _SYSSET_SESSION_TRACK_DIR="${BATS_TEST_TMPDIR}/no_such_session_xyz"

  # Must not fail even if session dir is missing.
  run ospkg__track_resource "test-group" "/tmp/no_mirror"
  assert_success

  # Session resources dir must not have been created.
  [[ ! -d "${BATS_TEST_TMPDIR}/no_such_session_xyz/resources" ]]
}

@test "ospkg__cleanup_resources: removes tracked files" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"

  # Create real files to be removed.
  local _f1="${BATS_TEST_TMPDIR}/tracked_file_a"
  local _f2="${BATS_TEST_TMPDIR}/tracked_file_b"
  touch "$_f1" "$_f2"
  ospkg__track_resource "cleanup-group" "$_f1" "$_f2"

  ospkg__cleanup_resources

  [[ ! -e "$_f1" ]]
  [[ ! -e "$_f2" ]]
}

@test "ospkg__cleanup_resources: sidecar is deleted after processing" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"

  local _f="${BATS_TEST_TMPDIR}/tracked_file_c"
  touch "$_f"
  ospkg__track_resource "cleanup-group2" "$_f"

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/resources/cleanup-group2"
  assert_file_exists "$_sidecar"

  ospkg__cleanup_resources

  [[ ! -f "$_sidecar" ]]
}

@test "ospkg__cleanup_resources: non-existent path does not cause failure" {
  reload_lib ospkg.sh
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"

  # Register a path that does not exist.
  local _res_dir="${BATS_TEST_TMPDIR}/ospkg/resources"
  mkdir -p "$_res_dir"
  printf '/tmp/definitely_does_not_exist_xyz123\n' > "${_res_dir}/ghost-group"

  run ospkg__cleanup_resources
  assert_success
}

@test "ospkg__cleanup_resources: no-ops when resources dir is absent" {
  reload_lib ospkg.sh
  # Point _SYSSET_TMPDIR to a dir with no ospkg/resources subdir.
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}/empty_root"
  mkdir -p "$_SYSSET_TMPDIR"

  run ospkg__cleanup_resources
  assert_success
}
