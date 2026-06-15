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
# os__expand_release_pattern
# ---------------------------------------------------------------------------

@test "os__expand_release_pattern substitutes {VERSION} and {TAG}" {
  reload_lib os.sh
  run os__expand_release_pattern "tool-{VERSION}-{TAG}" "1.2.3" "v1.2.3"
  assert_success
  assert_output "tool-1.2.3-v1.2.3"
}

@test "os__expand_release_pattern substitutes plain {OS} and {ARCH} tokens" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  _OS__ARCH="x86_64"
  run os__expand_release_pattern "tool-{OS}-{ARCH}" "1.0" "v1.0"
  assert_success
  assert_output "tool-linux-amd64"
}

@test "os__expand_release_pattern {OS:gh} returns gh-flavor OS" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__expand_release_pattern "{OS:gh}" "1.0" "v1.0"
  assert_success
  assert_output "linux"
}

@test "os__expand_release_pattern {ARCH:gh} returns gh-flavor arch" {
  reload_lib os.sh
  _OS__ARCH="x86_64"
  run os__expand_release_pattern "{ARCH:gh}" "1.0" "v1.0"
  assert_success
  assert_output "amd64"
}

@test "os__expand_release_pattern {VERSION>=X?a:b} returns 'a' when version matches" {
  reload_lib os.sh
  run os__expand_release_pattern "{VERSION>=1.7?new:old}" "2.0.0" "v2.0.0"
  assert_success
  assert_output "new"
}

@test "os__expand_release_pattern {VERSION>=X?a:b} returns 'b' when version is lower" {
  reload_lib os.sh
  run os__expand_release_pattern "{VERSION>=1.7?new:old}" "1.6.0" "v1.6.0"
  assert_success
  assert_output "old"
}

@test "os__expand_release_pattern {VERSION<X?a:b} returns 'a' when version is lower" {
  reload_lib os.sh
  run os__expand_release_pattern "{VERSION<1.7?legacy:modern}" "1.6.0" ""
  assert_success
  assert_output "legacy"
}

@test "os__expand_release_pattern {OS==VALUE?a:b} conditional on linux" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__expand_release_pattern "{OS==linux?islinux:notlinux}" "1.0" ""
  assert_success
  assert_output "islinux"
}

@test "os__expand_release_pattern {OS:gh==VALUE?a:b} uses flavor in condition" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  # On Linux os__release_kernel gh → linux; condition linux==macOS → false
  run os__expand_release_pattern "{OS:gh==macOS?zip:tar.gz}" "1.0" ""
  assert_success
  assert_output "tar.gz"
}

@test "os__expand_release_pattern nested conditional evaluates inner tokens" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  _OS__ARCH="x86_64"
  # jq 1.7+ naming: jq-linux-amd64
  run os__expand_release_pattern "jq-{VERSION>=1.7?{OS==darwin?macos:{OS}}-{ARCH}:LEGACY}" \
    "1.8.0" "jq-1.8.0"
  assert_success
  assert_output "jq-linux-amd64"
}

@test "os__expand_release_pattern nested conditional: false branch selected" {
  reload_lib os.sh
  run os__expand_release_pattern "jq-{VERSION>=1.7?{OS==darwin?macos:{OS}}-{ARCH}:LEGACY}" \
    "1.6.0" "jq-1.6.0"
  assert_success
  assert_output "jq-LEGACY"
}

@test "os__expand_release_pattern full gh-style URI pattern" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  _OS__ARCH="x86_64"
  run os__expand_release_pattern \
    "https://github.com/cli/cli/releases/download/{TAG}/gh_{VERSION}_{OS:gh}_{ARCH:gh}.{OS:gh==macOS?zip:tar.gz}" \
    "2.89.0" "v2.89.0"
  assert_success
  assert_output "https://github.com/cli/cli/releases/download/v2.89.0/gh_2.89.0_linux_amd64.tar.gz"
}

@test "os__expand_release_pattern {RUST_TRIPLE} still works" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  _OS__ARCH="x86_64"
  run os__expand_release_pattern "{RUST_TRIPLE}" "1.0" ""
  assert_success
  assert_output "x86_64-unknown-linux-musl"
}

@test "os__expand_release_pattern passes through unmatched brace literally" {
  reload_lib os.sh
  run os__expand_release_pattern "foo-{VERSION" "1.0" ""
  assert_success
  assert_output "foo-{VERSION"
}

@test "os__expand_release_pattern passes through unknown token unchanged" {
  reload_lib os.sh
  run os__expand_release_pattern "{UNKNOWN_TOKEN}" "1.0" ""
  assert_success
  assert_output "{UNKNOWN_TOKEN}"
}

# ---------------------------------------------------------------------------
# os__release_kernel
# ---------------------------------------------------------------------------

@test "os__release_kernel returns freebsd for FreeBSD kernel" {
  reload_lib os.sh
  _OS__KERNEL="FreeBSD"
  run os__release_kernel
  assert_success
  assert_output "freebsd"
}

@test "os__release_kernel returns linux for Linux kernel" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__release_kernel
  assert_success
  assert_output "linux"
}

@test "os__release_kernel returns darwin for Darwin with github flavor" {
  reload_lib os.sh
  _OS__KERNEL="Darwin"
  run os__release_kernel github
  assert_success
  assert_output "darwin"
}

@test "os__release_kernel returns 1 for unsupported kernel" {
  reload_lib os.sh
  _OS__KERNEL="SunOS"
  run os__release_kernel
  assert_failure
}

# ---------------------------------------------------------------------------
# os__libc
# ---------------------------------------------------------------------------

@test "os__libc returns 1 on non-Linux (Darwin)" {
  reload_lib os.sh
  _OS__KERNEL="Darwin"
  run os__libc
  assert_failure
}

@test "os__libc returns musl when ldd output contains musl" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  # Stub ldd to return musl-style output (ls glob will fail on glibc host)
  ldd() { printf '/lib/ld-musl-x86_64.so.1 (0x7f000000)\n'; }
  export -f ldd
  run os__libc
  assert_success
  assert_output "musl"
}

@test "os__libc returns gnu when no musl markers are present" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  ldd() { printf '/lib/x86_64-linux-gnu/libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6\n/lib64/ld-linux-x86-64.so.2\n'; }
  export -f ldd
  run os__libc
  assert_success
  assert_output "gnu"
}

# ---------------------------------------------------------------------------
# os__rust_triple
# ---------------------------------------------------------------------------

@test "os__rust_triple returns x86_64-unknown-linux-musl for Linux x86_64" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple x86_64
  assert_success
  assert_output "x86_64-unknown-linux-musl"
}

@test "os__rust_triple accepts amd64 alias for Linux" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple amd64
  assert_success
  assert_output "x86_64-unknown-linux-musl"
}

@test "os__rust_triple returns i686-unknown-linux-musl for Linux i686" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple i686
  assert_success
  assert_output "i686-unknown-linux-musl"
}

@test "os__rust_triple returns i686-unknown-linux-musl for Linux i386" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple i386
  assert_success
  assert_output "i686-unknown-linux-musl"
}

@test "os__rust_triple returns aarch64-unknown-linux-musl for Linux aarch64" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple aarch64
  assert_success
  assert_output "aarch64-unknown-linux-musl"
}

@test "os__rust_triple accepts arm64 alias for Linux" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple arm64
  assert_success
  assert_output "aarch64-unknown-linux-musl"
}

@test "os__rust_triple returns arm-unknown-linux-musleabihf for Linux armv6l" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple armv6l
  assert_success
  assert_output "arm-unknown-linux-musleabihf"
}

@test "os__rust_triple returns armv7-unknown-linux-musleabihf for Linux armv7l with NEON" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  grep() { return 0; }
  export -f grep
  run os__rust_triple armv7l
  assert_success
  assert_output "armv7-unknown-linux-musleabihf"
}

@test "os__rust_triple returns arm-unknown-linux-musleabihf for Linux armv7l without NEON" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  grep() { return 1; }
  export -f grep
  run os__rust_triple armv7l
  assert_success
  assert_output "arm-unknown-linux-musleabihf"
}

@test "os__rust_triple returns loongarch64-unknown-linux-musl for Linux loongarch64" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple loongarch64
  assert_success
  assert_output "loongarch64-unknown-linux-musl"
}

@test "os__rust_triple returns powerpc64le-unknown-linux-gnu for Linux ppc64le" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple ppc64le
  assert_success
  assert_output "powerpc64le-unknown-linux-gnu"
}

@test "os__rust_triple returns s390x-unknown-linux-gnu for Linux s390x" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple s390x
  assert_success
  assert_output "s390x-unknown-linux-gnu"
}

@test "os__rust_triple returns riscv64gc-unknown-linux-musl for Linux riscv64 on musl" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  os__libc() { printf 'musl\n'; }
  export -f os__libc
  run os__rust_triple riscv64
  assert_success
  assert_output "riscv64gc-unknown-linux-musl"
}

@test "os__rust_triple returns riscv64gc-unknown-linux-gnu for Linux riscv64 on glibc" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  os__libc() { printf 'gnu\n'; }
  export -f os__libc
  run os__rust_triple riscv64
  assert_success
  assert_output "riscv64gc-unknown-linux-gnu"
}

@test "os__rust_triple returns x86_64-apple-darwin for Darwin x86_64" {
  reload_lib os.sh
  _OS__KERNEL="Darwin"
  sysctl() { return 1; }
  export -f sysctl
  run os__rust_triple x86_64
  assert_success
  assert_output "x86_64-apple-darwin"
}

@test "os__rust_triple returns aarch64-apple-darwin for Darwin x86_64 under Rosetta 2" {
  reload_lib os.sh
  _OS__KERNEL="Darwin"
  sysctl() { printf '1\n'; }
  export -f sysctl
  run os__rust_triple x86_64
  assert_success
  assert_output "aarch64-apple-darwin"
}

@test "os__rust_triple returns aarch64-apple-darwin for Darwin aarch64" {
  reload_lib os.sh
  _OS__KERNEL="Darwin"
  run os__rust_triple aarch64
  assert_success
  assert_output "aarch64-apple-darwin"
}

@test "os__rust_triple accepts arm64 alias for Darwin" {
  reload_lib os.sh
  _OS__KERNEL="Darwin"
  run os__rust_triple arm64
  assert_success
  assert_output "aarch64-apple-darwin"
}

@test "os__rust_triple returns x86_64-unknown-freebsd for FreeBSD x86_64" {
  reload_lib os.sh
  _OS__KERNEL="FreeBSD"
  run os__rust_triple x86_64
  assert_success
  assert_output "x86_64-unknown-freebsd"
}

@test "os__rust_triple detects 32-bit x86 userland on a 64-bit kernel via getconf" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  getconf() { printf '32\n'; }
  export -f getconf
  run os__rust_triple x86_64
  assert_success
  assert_output "i686-unknown-linux-musl"
}

@test "os__rust_triple returns 1 for unsupported kernel/arch combination" {
  reload_lib os.sh
  _OS__KERNEL="Linux"
  run os__rust_triple mips
  assert_failure
}

# ---------------------------------------------------------------------------
# os__match_spec
# ---------------------------------------------------------------------------

_os_set_release() {
  # Populate _OSPKG__OS_RELEASE for os__match_spec / os__match_when tests.
  reload_lib os.sh
  declare -gA _OSPKG__OS_RELEASE=(
    [kernel]="${1:-linux}"
    [arch]="${2:-amd64}"
    [pm]="${3:-apt}"
    [id]="${4:-debian}"
  )
  _OSPKG__DETECTED=true
}

@test "os__match_spec: no args always matches" {
  _os_set_release
  run os__match_spec
  assert_success
}

@test "os__match_spec: single key matches" {
  _os_set_release linux amd64 apt ubuntu
  run os__match_spec "id=ubuntu"
  assert_success
}

@test "os__match_spec: single key fails when value differs" {
  _os_set_release linux amd64 apt debian
  run os__match_spec "id=ubuntu"
  assert_failure
}

@test "os__match_spec: OR values — first alternative matches" {
  _os_set_release linux amd64 apt debian
  run os__match_spec "pm=apt|dnf"
  assert_success
}

@test "os__match_spec: OR values — second alternative matches" {
  _os_set_release linux amd64 dnf debian
  run os__match_spec "pm=apt|dnf"
  assert_success
}

@test "os__match_spec: OR values — no alternative matches" {
  _os_set_release linux amd64 apk alpine
  run os__match_spec "pm=apt|dnf"
  assert_failure
}

@test "os__match_spec: AND across multiple pairs — all match" {
  _os_set_release linux amd64 apt ubuntu
  run os__match_spec "id=ubuntu" "pm=apt"
  assert_success
}

@test "os__match_spec: AND across multiple pairs — second fails" {
  _os_set_release linux amd64 dnf ubuntu
  run os__match_spec "id=ubuntu" "pm=apt"
  assert_failure
}

@test "os__match_spec: case-insensitive matching" {
  _os_set_release linux amd64 apt ubuntu
  run os__match_spec "id=Ubuntu"
  assert_success
}

# ---------------------------------------------------------------------------
# os__match_when
# ---------------------------------------------------------------------------

@test "os__match_when: empty string always matches" {
  _os_set_release
  run os__match_when ""
  assert_success
}

@test "os__match_when: single key matches" {
  _os_set_release linux amd64 apt ubuntu
  run os__match_when "id=ubuntu"
  assert_success
}

@test "os__match_when: single key fails when value differs" {
  _os_set_release linux amd64 apt debian
  run os__match_when "id=ubuntu"
  assert_failure
}

@test "os__match_when: OR values in a key — first alternative matches" {
  _os_set_release linux amd64 apt debian
  run os__match_when "pm=apt|dnf"
  assert_success
}

@test "os__match_when: OR values in a key — second alternative matches" {
  _os_set_release linux amd64 dnf debian
  run os__match_when "pm=apt|dnf"
  assert_success
}

@test "os__match_when: OR values in a key — no alternative matches" {
  _os_set_release linux amd64 apk alpine
  run os__match_when "pm=apt|dnf"
  assert_failure
}

@test "os__match_when: AND across multiple atoms — all match" {
  _os_set_release linux amd64 apt ubuntu
  run os__match_when "id=ubuntu pm=apt"
  assert_success
}

@test "os__match_when: AND across multiple atoms — second fails" {
  _os_set_release linux amd64 dnf ubuntu
  run os__match_when "id=ubuntu pm=apt"
  assert_failure
}

@test "os__match_when: multi-group OR — first group matches" {
  _os_set_release linux amd64 apt ubuntu
  run os__match_when $'id=ubuntu\nkernel=darwin'
  assert_success
}

@test "os__match_when: multi-group OR — second group matches" {
  _os_set_release darwin arm64 brew macos
  run os__match_when $'id=ubuntu\nkernel=darwin'
  assert_success
}

@test "os__match_when: multi-group OR — neither group matches" {
  _os_set_release linux amd64 apk alpine
  run os__match_when $'id=ubuntu\nkernel=darwin'
  assert_failure
}

@test "os__match_when: case-insensitive matching" {
  _os_set_release linux amd64 apt ubuntu
  run os__match_when "id=Ubuntu"
  assert_success
}
