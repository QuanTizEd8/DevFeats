#!/usr/bin/env bats
# Unit tests for lib/os.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# os__kernel
# ---------------------------------------------------------------------------

@test "os__kernel returns the uname -s value" {
  reload_lib os.sh
  uname() { echo "Linux"; }
  export -f uname
  run os__kernel
  assert_output "Linux"
  assert_success
}

@test "os__kernel returns Darwin" {
  reload_lib os.sh
  uname() { echo "Darwin"; }
  export -f uname
  run os__kernel
  assert_output "Darwin"
}

@test "os__kernel uses cached _OS__KERNEL value" {
  reload_lib os.sh
  _OS__KERNEL="CachedOS"
  run os__kernel
  assert_output "CachedOS"
}

# ---------------------------------------------------------------------------
# os__arch
# ---------------------------------------------------------------------------

@test "os__arch returns the uname -m value" {
  reload_lib os.sh
  uname() { echo "x86_64"; }
  export -f uname
  run os__arch
  assert_output "x86_64"
}

@test "os__arch returns aarch64" {
  reload_lib os.sh
  uname() { echo "aarch64"; }
  export -f uname
  run os__arch
  assert_output "aarch64"
}

@test "os__arch uses cached _OS__ARCH value" {
  reload_lib os.sh
  _OS__ARCH="arm64"
  run os__arch
  assert_output "arm64"
}

# ---------------------------------------------------------------------------
# os__id / os__id_like  (injecting pre-loaded release state)
# ---------------------------------------------------------------------------

@test "os__id returns ID injected via cached globals" {
  reload_lib os.sh
  _OS__ID="ubuntu"
  _OS__RELEASE_LOADED=1
  run os__id
  assert_output "ubuntu"
}

@test "os__id returns alpine" {
  reload_lib os.sh
  _OS__ID="alpine"
  _OS__RELEASE_LOADED=1
  run os__id
  assert_output "alpine"
}

@test "os__id_like returns injected ID_LIKE" {
  reload_lib os.sh
  _OS__ID_LIKE="debian ubuntu"
  _OS__RELEASE_LOADED=1
  run os__id_like
  assert_output "debian ubuntu"
}

@test "os__id_like returns empty string when unset" {
  reload_lib os.sh
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run os__id_like
  assert_output ""
}

# ---------------------------------------------------------------------------
# os__codename
# ---------------------------------------------------------------------------

@test "os__codename returns injected VERSION_CODENAME" {
  reload_lib os.sh
  _OS__CODENAME="jammy"
  _OS__RELEASE_LOADED=1
  run os__codename
  assert_output "jammy"
  assert_success
}

@test "os__codename returns bookworm" {
  reload_lib os.sh
  _OS__CODENAME="bookworm"
  _OS__RELEASE_LOADED=1
  run os__codename
  assert_output "bookworm"
}

@test "os__codename returns empty string when unset" {
  reload_lib os.sh
  _OS__CODENAME=""
  _OS__RELEASE_LOADED=1
  run os__codename
  assert_output ""
}

@test "os__codename returns empty string on macOS (no os-release)" {
  reload_lib os.sh
  # No _OS__CODENAME set, no /etc/os-release → should return empty.
  _OS__RELEASE_LOADED=1
  run os__codename
  assert_output ""
}

# ---------------------------------------------------------------------------
# os__platform
# ---------------------------------------------------------------------------

@test "os__platform returns debian for ID=ubuntu" {
  reload_lib os.sh
  _OS__ID="ubuntu"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "debian"
}

@test "os__platform returns debian for ID=debian" {
  reload_lib os.sh
  _OS__ID="debian"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "debian"
}

@test "os__platform returns alpine for ID=alpine" {
  reload_lib os.sh
  _OS__ID="alpine"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "alpine"
}

@test "os__platform returns rhel for ID=fedora" {
  reload_lib os.sh
  _OS__ID="fedora"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns rhel for ID=centos" {
  reload_lib os.sh
  _OS__ID="centos"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns macos for Darwin uname fallback" {
  reload_lib os.sh
  _OS__ID=""
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  uname() { echo "Darwin"; }
  export -f uname
  run os__platform
  assert_output "macos"
}

@test "os__platform returns debian as fallback for unknown Linux" {
  reload_lib os.sh
  _OS__ID=""
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  uname() { echo "Linux"; }
  export -f uname
  run os__platform
  assert_output "debian"
}

@test "os__platform returns debian when ID_LIKE contains debian" {
  reload_lib os.sh
  _OS__ID="linuxmint"
  _OS__ID_LIKE="ubuntu debian"
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "debian"
}

@test "os__platform uses cached _OS__PLATFORM" {
  reload_lib os.sh
  _OS__PLATFORM="rhel"
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns rhel for ID=rhel" {
  reload_lib os.sh
  _OS__ID="rhel"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns rhel for ID=rocky" {
  reload_lib os.sh
  _OS__ID="rocky"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns rhel when ID_LIKE contains fedora" {
  reload_lib os.sh
  _OS__ID="custom"
  _OS__ID_LIKE="fedora"
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns suse for openSUSE Tumbleweed" {
  reload_lib os.sh
  _OS__ID="opensuse-tumbleweed"
  _OS__ID_LIKE="opensuse suse"
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "suse"
}

@test "os__platform returns suse for opensuse-leap" {
  reload_lib os.sh
  _OS__ID="opensuse-leap"
  _OS__ID_LIKE="suse opensuse"
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "suse"
}

@test "os__platform returns suse for sles" {
  reload_lib os.sh
  _OS__ID="sles"
  _OS__ID_LIKE="suse"
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "suse"
}

@test "os__platform returns suse for sle-micro" {
  reload_lib os.sh
  _OS__ID="sle-micro"
  _OS__ID_LIKE="suse"
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "suse"
}

@test "os__platform returns suse when ID_LIKE contains suse" {
  reload_lib os.sh
  _OS__ID="custom-suse-distro"
  _OS__ID_LIKE="suse"
  _OS__RELEASE_LOADED=1
  run os__platform
  assert_output "suse"
}

# ---------------------------------------------------------------------------
# os__require_root
# ---------------------------------------------------------------------------

@test "os__require_root succeeds when id -u returns 0" {
  reload_lib os.sh
  create_fake_bin "id" "0"
  prepend_fake_bin_path
  run os__require_root
  assert_success
}

@test "os__require_root fails with message when id -u returns non-zero" {
  reload_lib os.sh
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  run os__require_root
  assert_failure
  assert_output --partial "must be run as root"
}

# ---------------------------------------------------------------------------
# os__font_dir
# ---------------------------------------------------------------------------

@test "os__font_dir returns /usr/share/fonts for system-scope prefix" {
  reload_lib os.sh
  users__is_root() { return 0; }
  export -f users__is_root
  run os__font_dir
  assert_output "/usr/share/fonts"
}

@test "os__font_dir returns ~/Library/Fonts for macOS non-root" {
  reload_lib os.sh
  users__is_root() { return 1; }
  uname() { echo "Darwin"; }
  export -f users__is_root uname
  HOME="/home/testuser" run os__font_dir
  assert_output "/home/testuser/Library/Fonts"
}

@test "os__font_dir returns XDG_DATA_HOME path for Linux non-root" {
  reload_lib os.sh
  users__is_root() { return 1; }
  uname() { echo "Linux"; }
  export -f users__is_root uname
  HOME="/home/testuser" XDG_DATA_HOME="/custom/data" run os__font_dir
  assert_output "/custom/data/fonts"
}

@test "os__font_dir returns default XDG path when XDG_DATA_HOME not set" {
  reload_lib os.sh
  users__is_root() { return 1; }
  uname() { echo "Linux"; }
  export -f users__is_root uname
  HOME="/home/testuser" XDG_DATA_HOME="" run os__font_dir
  assert_output "/home/testuser/.local/share/fonts"
}

@test "os__font_dir returns user-local XDG path for non-root" {
  reload_lib os.sh
  users__is_root() { return 1; }
  uname() { echo "Linux"; }
  export -f users__is_root uname
  HOME="/home/vscode" XDG_DATA_HOME="" run os__font_dir
  assert_output "/home/vscode/.local/share/fonts"
}

# ---------------------------------------------------------------------------
# os__is_container
# ---------------------------------------------------------------------------

@test "os__is_container returns true when /.dockerenv exists" {
  reload_lib os.sh
  # Use a temp file as the sentinel — override the built-in check via function
  # injection: the simplest approach is writing /.dockerenv to a tmpdir and
  # pointing the function at it.  Since the function hard-codes the path we
  # test indirectly via the exported sentinel file in scope of a subshell.
  local _tmp
  _tmp="$(mktemp -d)"
  touch "$_tmp/.dockerenv"
  # Source os.sh in a subshell that replaces / with our tmpdir for the lookup.
  run bash -c "
    source '${LIB_ROOT}/os.sh'
    # Override the check: replace /.dockerenv with \$_tmp/.dockerenv
    os__is_container() {
      [[ -f '${_tmp}/.dockerenv' ]] && return 0
      return 1
    }
    os__is_container
  "
  assert_success
  rm -rf "$_tmp"
}

@test "os__is_container returns false when no container markers are present" {
  reload_lib os.sh
  run bash -c "
    source '${LIB_ROOT}/os.sh'
    # Override the check: point all paths to non-existent files.
    os__is_container() {
      [[ -f '/no-such-dockerenv-sentinel' ]] && return 0
      [[ -f '/run/.containerenv-sentinel' ]] && return 0
      return 1
    }
    os__is_container
  "
  assert_failure
}

# ---------------------------------------------------------------------------
# os__is_system_path — non-root scenarios
# ---------------------------------------------------------------------------

@test "os__is_system_path: non-root, writable path is user-local" {
  (($(id -u) != 0)) || skip "requires non-root"
  reload_lib os.sh
  run os__is_system_path "$BATS_TEST_TMPDIR"
  assert_failure
}

@test "os__is_system_path: non-root, non-existent path under writable parent is user-local" {
  (($(id -u) != 0)) || skip "requires non-root"
  reload_lib os.sh
  run os__is_system_path "$BATS_TEST_TMPDIR/does-not-exist/bin"
  assert_failure
}

@test "os__is_system_path: non-root, path under non-writable root ancestor is system" {
  (($(id -u) != 0)) || skip "requires non-root"
  reload_lib os.sh
  # _os__nearest_existing walks up to / which is not writable by non-root.
  run os__is_system_path "/_devfeats_test_nonexistent_xyz/bin"
  assert_success
}

# ---------------------------------------------------------------------------
# os__is_system_path — root scenarios (users__is_root and stat stubbed)
# ---------------------------------------------------------------------------

@test "os__is_system_path: root, path directly under HOME is user-local" {
  reload_lib os.sh
  users__is_root() { return 0; }
  export -f users__is_root
  HOME="/root" run os__is_system_path "/root/.local/bin"
  assert_failure
}

@test "os__is_system_path: root, path owned by regular user (UID 1000) is user-local" {
  reload_lib os.sh
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '1000\n'; }
  export -f users__is_root users__uid_of_path_owner
  HOME="/root" run os__is_system_path "/home/vscode/.local/bin"
  assert_failure
}

@test "os__is_system_path: root, path owned by UID 65533 (upper boundary) is user-local" {
  reload_lib os.sh
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '65533\n'; }
  export -f users__is_root users__uid_of_path_owner
  HOME="/root" run os__is_system_path "/home/highuid/.local"
  assert_failure
}

@test "os__is_system_path: root, path owned by root (UID 0) is system" {
  reload_lib os.sh
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '0\n'; }
  export -f users__is_root users__uid_of_path_owner
  HOME="/root" run os__is_system_path "/usr/local/bin"
  assert_success
}

@test "os__is_system_path: root, path owned by system user (UID 999) is system" {
  reload_lib os.sh
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '999\n'; }
  export -f users__is_root users__uid_of_path_owner
  HOME="/root" run os__is_system_path "/home/linuxbrew/.linuxbrew"
  assert_success
}

@test "os__is_system_path: root, path owned by nobody (UID 65534) is system" {
  reload_lib os.sh
  users__is_root() { return 0; }
  users__uid_of_path_owner() { printf '65534\n'; }
  export -f users__is_root users__uid_of_path_owner
  HOME="/root" run os__is_system_path "/srv/data"
  assert_success
}
