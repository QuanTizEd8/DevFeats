#!/usr/bin/env bats
# Unit tests for lib/users.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib users.sh
}

# ---------------------------------------------------------------------------
# users__resolve_list
# ---------------------------------------------------------------------------

@test "users__resolve_list includes SUDO_USER when --current true" {
  SUDO_USER=alice \
    run --separate-stderr users__resolve_list --current true --remote false --container false
  assert_output "alice"
}

@test "users__resolve_list includes _REMOTE_USER when --remote true" {
  _REMOTE_USER=bob \
    run --separate-stderr users__resolve_list --current false --remote true --container false
  assert_output "bob"
}

@test "users__resolve_list includes _CONTAINER_USER when --container true" {
  _CONTAINER_USER=carol \
    run --separate-stderr users__resolve_list --current false --remote false --container true
  assert_output "carol"
}

@test "users__resolve_list includes extra users from --user flags" {
  run --separate-stderr users__resolve_list \
    --current false --remote false --container false \
    --user dave --user eve
  assert_output "dave
eve"
}

@test "users__resolve_list deduplicates users passed via --user" {
  run --separate-stderr users__resolve_list \
    --current false --remote false --container false \
    --user alice --user alice --user bob
  assert_output "alice
bob"
}

@test "users__resolve_list combines --current and --user" {
  SUDO_USER=alice \
    run --separate-stderr users__resolve_list \
    --current true --remote false --container false \
    --user bob
  assert_output "alice
bob"
}

@test "users__resolve_list includes root as fallback when it is the only user" {
  # When the build user is root and no other non-root users are auto-detected,
  # root is included so the feature has a target to configure (e.g. plain
  # container images or standalone macOS use with no remoteUser).
  SUDO_USER=root \
    run --separate-stderr users__resolve_list --current true --remote false --container false
  assert_output "root"
  assert_success
}

@test "users__resolve_list excludes root when a non-root user is also detected" {
  # Root must not be added when a non-root remoteUser / containerUser is present;
  # the build runs as root but the target for configuration is the named user.
  SUDO_USER=root \
    _REMOTE_USER=alice \
    run --separate-stderr users__resolve_list --current true --remote true --container false
  assert_output "alice"
  assert_success
}

@test "users__resolve_list allows root when explicitly passed via --user" {
  # Explicitly listing root via --user is a deliberate override
  # (used by install-podman to configure rootless Podman for the root user).
  run --separate-stderr users__resolve_list \
    --current false --remote false --container false \
    --user root --user alice
  assert_output "root
alice"
}

@test "users__resolve_list returns empty output when all sources are disabled" {
  run --separate-stderr users__resolve_list --current false --remote false --container false
  assert_output ""
  assert_success
}

@test "users__resolve_list auto-discovers all sources when called with no args" {
  SUDO_USER=alice \
    _REMOTE_USER=bob \
    _CONTAINER_USER=carol \
    run --separate-stderr users__resolve_list
  assert_output "alice
bob
carol"
}

@test "users__resolve_list skips empty _REMOTE_USER when --remote true" {
  _REMOTE_USER="" \
    run --separate-stderr users__resolve_list --current false --remote true --container false
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# users__set_login_shell
# ---------------------------------------------------------------------------

@test "users__set_login_shell warns when chsh is not installed" {
  reload_lib users.sh
  # Isolate PATH so chsh is not found.
  begin_path_isolation
  run users__set_login_shell "/usr/bin/zsh" "alice"
  end_path_isolation
  assert_success
  assert_output --partial "chsh not found"
}

@test "users__set_login_shell skips user whose shell is already set" {
  reload_lib users.sh
  ospkg__run() { return 0; } # chsh already on PATH; skip package install
  create_fake_bin "chsh" ""
  # fake getent returns a passwd line where the shell is already /usr/bin/zsh
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'alice:x:1000:1000::/home/alice:/usr/bin/zsh\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users__set_login_shell "/usr/bin/zsh" "alice"
  assert_success
  assert_output --partial "already set"
}

@test "users__set_login_shell changes the shell when it differs" {
  reload_lib users.sh
  ospkg__run() { return 0; }        # chsh already on PATH; skip package install
  users__run_privileged() { "$@"; } # run directly (no sudo) so fake PATH is used
  create_fake_bin "chsh" ""
  # fake getent returns a passwd line with a different shell
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'alice:x:1000:1000::/home/alice:/bin/bash\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users__set_login_shell "/usr/bin/zsh" "alice"
  assert_success
  assert_output --partial "set to '/usr/bin/zsh'"
}

# ---------------------------------------------------------------------------
# users__resolve_home
# ---------------------------------------------------------------------------

@test "users__resolve_home resolves home via getent" {
  create_fake_bin "getent" "alice:x:1000:1000::/home/alice:/bin/bash"
  prepend_fake_bin_path
  run users__resolve_home "alice"
  assert_success
  assert_output "/home/alice"
}

@test "users__resolve_home falls back to /etc/passwd when getent is absent" {
  begin_path_isolation grep
  local _expected
  _expected="$(eval echo '~root')"
  run users__resolve_home "root"
  end_path_isolation
  assert_success
  assert_output "$_expected"
}

@test "users__resolve_home uses tilde expansion when user not in /etc/passwd" {
  begin_path_isolation grep
  run users__resolve_home "___no_such_user_xyz___"
  end_path_isolation
  assert_success
  assert_output "~___no_such_user_xyz___"
}

# ---------------------------------------------------------------------------
# users__run_as
# ---------------------------------------------------------------------------

@test "users__run_as runs in-process when user matches" {
  reload_lib os.sh
  _me="$(id -un)"
  run users__run_as "$_me" -- echo "ran"
  assert_output "ran"
  assert_success
}

@test "users__run_as same user: --cwd changes directory" {
  reload_lib os.sh
  _me="$(id -un)"
  run users__run_as "$_me" --cwd "$BATS_TEST_TMPDIR" -- pwd
  assert_success
  assert_output "$BATS_TEST_TMPDIR"
}

@test "users__run_as same user: --cwd with spaces in path" {
  reload_lib os.sh
  _me="$(id -un)"
  _dir="$BATS_TEST_TMPDIR/path with spaces"
  mkdir -p "$_dir"
  run users__run_as "$_me" --cwd "$_dir" -- pwd
  assert_success
  assert_output "$_dir"
}

@test "users__run_as returns failure when user argument is empty" {
  reload_lib os.sh
  run users__run_as "" -- echo "nope"
  assert_failure
}

@test "users__run_as returns failure when no command given" {
  reload_lib os.sh
  _me="$(id -un)"
  run users__run_as "$_me" --
  assert_failure
}

# ---------------------------------------------------------------------------
# users__run_as — different-user path (su stubbed with eval)
# In these tests, `id` is faked to return "notme" so the current-user check
# fails and execution proceeds to the su path.  `su` is overridden as a shell
# function that eval's its 4th argument (the -c command string) so we can
# verify the constructed command string is correctly quoted and executable.
# ---------------------------------------------------------------------------

@test "users__run_as different user: runs command via su" {
  reload_lib os.sh
  create_fake_bin "id" "notme"
  prepend_fake_bin_path
  su() { eval "$4"; }
  users__run_privileged() { "$@"; }
  export -f su users__run_privileged
  run users__run_as "otheruser" -- echo "via-su"
  assert_success
  assert_output "via-su"
}

@test "users__run_as different user: preserves args with spaces" {
  reload_lib os.sh
  create_fake_bin "id" "notme"
  prepend_fake_bin_path
  su() { eval "$4"; }
  users__run_privileged() { "$@"; }
  export -f su users__run_privileged
  run users__run_as "otheruser" -- echo "hello world"
  assert_success
  assert_output "hello world"
}

@test "users__run_as different user: --cwd with spaces in path" {
  reload_lib os.sh
  create_fake_bin "id" "notme"
  prepend_fake_bin_path
  _dir="$BATS_TEST_TMPDIR/path with spaces"
  mkdir -p "$_dir"
  su() { eval "$4"; }
  users__run_privileged() { "$@"; }
  export -f su users__run_privileged
  run users__run_as "otheruser" --cwd "$_dir" -- pwd
  assert_success
  assert_output "$_dir"
}

@test "users__run_as different user: --cwd with single quote in path" {
  reload_lib os.sh
  create_fake_bin "id" "notme"
  prepend_fake_bin_path
  _dir="$BATS_TEST_TMPDIR/user's dir"
  mkdir -p "$_dir"
  su() { eval "$4"; }
  users__run_privileged() { "$@"; }
  export -f su users__run_privileged
  run users__run_as "otheruser" --cwd "$_dir" -- pwd
  assert_success
  assert_output "$_dir"
}

@test "users__run_as fails with error when bash is not on PATH" {
  reload_lib os.sh
  create_fake_bin "id" "notme"
  begin_path_isolation # only fake bin dir; bash not present
  run users__run_as "otheruser" -- echo "nope"
  end_path_isolation
  assert_failure
  assert_output --partial "bash is required"
}

# ---------------------------------------------------------------------------
# users__uid_of_path_owner
# ---------------------------------------------------------------------------

@test "users__uid_of_path_owner: returns numeric UID for an existing directory" {
  run users__uid_of_path_owner "$BATS_TEST_TMPDIR"
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "users__uid_of_path_owner: returns numeric UID for an existing file" {
  local _f="$BATS_TEST_TMPDIR/testfile"
  touch "$_f"
  run users__uid_of_path_owner "$_f"
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

# ---------------------------------------------------------------------------
# users__home_of_path_owner
# ---------------------------------------------------------------------------

@test "users__home_of_path_owner: path under HOME returns HOME immediately" {
  HOME="/home/alice" run users__home_of_path_owner "/home/alice/.local/bin"
  assert_output "/home/alice"
  assert_success
}

@test "users__home_of_path_owner: non-root, path outside HOME returns HOME fallback" {
  HOME="/home/alice" run users__home_of_path_owner "/usr/local/bin"
  assert_output "/home/alice"
  assert_success
}

@test "users__home_of_path_owner: root, path under HOME returns HOME via fast path" {
  users__is_root() { return 0; }
  export -f users__is_root
  HOME="/root" run users__home_of_path_owner "/root/.local/bin"
  assert_output "/root"
  assert_success
}

@test "users__home_of_path_owner: root, getent returns entry for regular user" {
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '1001\n'; }
  getent() { printf 'vscode:x:1001:1001::/home/vscode:/bin/bash\n'; }
  export -f users__is_root users__uid_of_path_owner getent
  HOME="/root" run users__home_of_path_owner "/home/vscode/.local/bin"
  assert_output "/home/vscode"
  assert_success
}

@test "users__home_of_path_owner: root, getent returns nothing and awk fallback finds entry" {
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '1001\n'; }
  getent() { :; } # no output (e.g. macOS where getent is absent)
  awk() { printf '/home/vscode\n'; }
  export -f users__is_root users__uid_of_path_owner getent awk
  HOME="/root" run users__home_of_path_owner "/home/vscode/.local/bin"
  assert_output "/home/vscode"
  assert_success
}

@test "users__home_of_path_owner: root, orphaned UID returns HOME fallback" {
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '58392\n'; }
  getent() { :; }
  export -f users__is_root users__uid_of_path_owner getent
  HOME="/root" run users__home_of_path_owner "/home/gone/.config"
  assert_output "/root"
  assert_success
}

@test "users__home_of_path_owner: root, path owned by root (UID 0) returns HOME fallback" {
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '0\n'; }
  export -f users__is_root users__uid_of_path_owner
  HOME="/root" run users__home_of_path_owner "/usr/local/bin"
  assert_output "/root"
  assert_success
}

@test "users__home_of_path_owner: root, path owned by system user (UID 999) returns HOME fallback" {
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '999\n'; }
  export -f users__is_root users__uid_of_path_owner
  HOME="/root" run users__home_of_path_owner "/home/linuxbrew/.linuxbrew"
  assert_output "/root"
  assert_success
}

@test "users__home_of_path_owner: path under HOME matching prefix prefix is returned directly" {
  HOME="/home/alice" run users__home_of_path_owner "/home/alice/.local"
  assert_output "/home/alice"
  assert_success
}

# ---------------------------------------------------------------------------
# users__run_privileged — sudo absent
# ---------------------------------------------------------------------------

@test "users__run_privileged: exits with error when sudo is not installed" {
  users__is_root() { return 1; }
  export -f users__is_root
  begin_path_isolation # sudo not in isolated PATH
  run users__run_privileged echo "should not run"
  end_path_isolation
  assert_failure
  assert_output --partial "sudo is not installed"
}

# ---------------------------------------------------------------------------
# users__is_privileged
# ---------------------------------------------------------------------------

@test "users__is_privileged: returns 0 when running as root" {
  users__is_root() { return 0; }
  export -f users__is_root
  run users__is_privileged
  assert_success
}

@test "users__is_privileged: returns 0 when non-root and sudo is passwordless" {
  users__is_root() { return 1; }
  export -f users__is_root
  create_fake_bin "sudo" ""
  prepend_fake_bin_path
  run users__is_privileged
  assert_success
}

@test "users__is_privileged: returns 1 when non-root and sudo is not installed" {
  users__is_root() { return 1; }
  export -f users__is_root
  begin_path_isolation
  run users__is_privileged
  end_path_isolation
  assert_failure
}

@test "users__is_privileged: returns 1 when non-root and sudo requires a password" {
  users__is_root() { return 1; }
  export -f users__is_root
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # Fake sudo: exists in PATH but 'sudo -n ...' exits 1 (simulates interactive password prompt).
  printf '#!/bin/bash\n[[ "$1" == "-n" ]] && exit 1 || exit 0\n' \
    > "${BATS_TEST_TMPDIR}/bin/sudo"
  chmod +x "${BATS_TEST_TMPDIR}/bin/sudo"
  prepend_fake_bin_path
  run users__is_privileged
  assert_failure
}

# ---------------------------------------------------------------------------
# users__can_write
# ---------------------------------------------------------------------------

@test "users__can_write: returns 0 for a writable existing directory" {
  run users__can_write "$BATS_TEST_TMPDIR"
  assert_success
}

@test "users__can_write: returns 0 for a nonexistent path under a writable directory" {
  run users__can_write "$BATS_TEST_TMPDIR/new/subdir"
  assert_success
}

@test "users__can_write: returns 1 when nearest ancestor is not writable and sudo is unavailable" {
  file__nearest_existing() { printf '/__devfeats_nonexistent__\n'; }
  users__is_privileged() { return 1; }
  export -f file__nearest_existing users__is_privileged
  run users__can_write "/some/path"
  assert_failure
}

@test "users__can_write: returns 0 when nearest ancestor is not writable but sudo is available" {
  file__nearest_existing() { printf '/__devfeats_nonexistent__\n'; }
  users__is_privileged() { return 0; }
  export -f file__nearest_existing users__is_privileged
  run users__can_write "/some/path"
  assert_success
}
