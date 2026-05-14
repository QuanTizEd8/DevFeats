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
